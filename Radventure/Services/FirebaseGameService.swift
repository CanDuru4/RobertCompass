import Foundation
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

/// Implements shared gameplay with Firestore transactions validated by database rules.
/// - Note: Server timestamps and private answer receipts replace paid callable functions.
/// - Example: `try await service.call("createTeam", data: values)`.
final class FirebaseGameService {
    private let db: Firestore
    private let user: User
    private let offset: TimeInterval
    private var uid: String { user.uid }
    private var profile: DocumentReference { db.collection("users").document(uid) }
    private var now: Date { Date().addingTimeInterval(offset) }

    /// Bind one operation service to the current account and database.
    /// - Parameters:
    ///   - db: Live Firestore or its loopback emulator.
    ///   - user: The signed-in Firebase account.
    ///   - offset: Display-clock adjustment; security rules always use server time.
    /// - Example: `FirebaseGameService(db: db, user: user, offset: 0)`.
    init(db: Firestore, user: User, offset: TimeInterval) {
        self.db = db
        self.user = user
        self.offset = offset
    }

    /// Dispatch the existing app operation contract to protected database transactions.
    /// - Parameters:
    ///   - name: A supported gameplay or account operation.
    ///   - data: Bounded player input; database rules independently validate every write.
    /// - Returns: The operation result and server time when available.
    /// - Throws: Actionable validation, network, or Firebase authorization errors.
    /// - Example: `try await service.call("refreshSession", data: ["sessionId": id])`.
    func call(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        guard user.isEmailVerified else { throw GameWriteError("Verify your email before joining an activity.") }
        switch name {
        case "syncProfile": return try await syncProfile(data)
        case "createTeam": return try await createTeam(data)
        case "joinTeam": return try await joinTeam(data)
        case "startGame": return try await startGame(data)
        case "submitAnswer": return try await submitAnswer(data)
        case "refreshSession": return try await refreshSession(data)
        case "leaveTeam": return try await leaveTeam(data)
        case "deleteAccount": return try await deleteAccount()
        default: throw GameWriteError("This operation is not available.")
        }
    }

    private func transaction(_ work: @escaping (Transaction) throws -> Any) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ transaction, error in
                do { return try work(transaction) }
                catch let failure { error?.pointee = failure as NSError; return nil }
            }, completion: { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value ?? [:]) }
            })
        }
    }

    private func syncProfile(_ data: [String: Any]) async throws -> [String: Any] {
        let name = try text(data["displayName"] ?? user.displayName ?? "Player", limit: 60)
        _ = try await transaction { [self] tx in
            let existing = try tx.getDocument(profile).data()
            guard existing?["deleting"] as? Bool != true else { throw GameWriteError("Account deletion is in progress. Open Profile to finish it.") }
            if existing == nil {
                tx.setData(["displayName": name, "activeSessionId": NSNull(), "deleting": false,
                            "updatedAt": FieldValue.serverTimestamp()], forDocument: profile)
            } else {
                tx.updateData(["displayName": name, "updatedAt": FieldValue.serverTimestamp()], forDocument: profile)
            }
            return [:]
        }
        let data = try await profile.getDocument(source: .server).data()
        let time = (data?["updatedAt"] as? Timestamp)?.dateValue().timeIntervalSince1970 ?? now.timeIntervalSince1970
        if let old = try? await profile.collection("attempts")
            .whereField("receivedAt", isLessThan: Timestamp(date: Date(timeIntervalSince1970: time - 86400)))
            .limit(to: 100).getDocuments(source: .server), !old.isEmpty {
            let cleanup = db.batch()
            old.documents.forEach { cleanup.deleteDocument($0.reference) }
            try? await cleanup.commit()
        }
        return ["ok": true, "serverTime": time * 1000]
    }

    private func createTeam(_ data: [String: Any]) async throws -> [String: Any] {
        let gameId = try identifier(data["gameId"])
        let name = try text(data["teamName"], limit: 60)
        let course = db.collection("games").document(gameId)
        let courseData = try await course.getDocument(source: .server).data()
        if courseData?["requiresEntryCode"] as? Bool == true {
            let value = data["entryCode"] as? String ?? ""
            guard value.count <= 128 else { throw GameWriteError("The course entry code is invalid.") }
            let hash = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
            do { try await profile.collection("entries").document(gameId).setData(["hash": hash, "updatedAt": FieldValue.serverTimestamp()]) }
            catch { throw GameWriteError("The course entry code could not be verified.") }
        }
        let ref = db.collection("sessions").document()
        let code = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
        let invite = db.collection("joinCodes").document(code)
        _ = try await transaction { [self] tx in
            let g = try required(tx.getDocument(course))
            let p = try required(tx.getDocument(profile))
            let occupied = try tx.getDocument(invite).exists
            try available(tx, profile: p)
            guard !occupied, g["published"] as? Bool == true,
                  let end = g["endsAt"] as? Double, end > now.timeIntervalSince1970 * 1000,
                  let duration = g["durationSeconds"] as? Int, let gameName = g["name"] as? String else {
                throw GameWriteError("This course is unavailable. Refresh the course list and try again.")
            }
            let value: [String: Any] = ["schemaVersion": 2, "gameId": gameId, "gameName": gameName, "teamName": name,
                "ownerId": uid, "memberIds": [uid], "memberNames": [uid: p["displayName"] as? String ?? "Player"],
                "joinCode": code, "createdAt": FieldValue.serverTimestamp(), "updatedAt": FieldValue.serverTimestamp(),
                "startedAt": NSNull(), "finishedAt": NSNull(), "lastScoredAt": NSNull(), "lastCheckpointId": NSNull(),
                "status": "waiting", "score": 0, "checkpointIds": [], "completedIds": [],
                "durationSeconds": duration, "gameEndsAt": end, "routeIndex": NSNull()]
            tx.setData(value, forDocument: ref)
            tx.setData(["sessionId": ref.documentID], forDocument: invite)
            tx.updateData(["activeSessionId": ref.documentID, "updatedAt": FieldValue.serverTimestamp()], forDocument: profile)
            return [:]
        }
        return ["sessionId": ref.documentID]
    }

    private func joinTeam(_ data: [String: Any]) async throws -> [String: Any] {
        let code = try text(data["joinCode"], limit: 12).uppercased()
        guard code.range(of: "^[A-F0-9]{12}$", options: .regularExpression) != nil else { throw GameWriteError("Enter the 12-character team code.") }
        let invite = try await db.collection("joinCodes").document(code).getDocument(source: .server)
        guard let id = invite.data()?["sessionId"] as? String else { throw GameWriteError("Team code not found.") }
        let ref = db.collection("sessions").document(id)
        do {
            _ = try await transaction { [self] tx in
                var s = try required(tx.getDocument(ref))
                var members = s["memberIds"] as? [String] ?? []
                if members.contains(uid) { return [:] }
                let p = try required(tx.getDocument(profile))
                let g = try required(tx.getDocument(db.collection("games").document(try identifier(s["gameId"]))))
                try available(tx, profile: p)
                guard s["status"] as? String == "waiting", isOpen(s), members.count < (g["maxTeamSize"] as? Int ?? 0) else {
                    throw GameWriteError("This team is full, expired, or already started.")
                }
                members.append(uid)
                var names = s["memberNames"] as? [String: String] ?? [:]
                names[uid] = p["displayName"] as? String ?? "Player"
                s["memberIds"] = members; s["memberNames"] = names; s["updatedAt"] = FieldValue.serverTimestamp()
                tx.setData(s, forDocument: ref)
                tx.updateData(["activeSessionId": id, "updatedAt": FieldValue.serverTimestamp()], forDocument: profile)
                return [:]
            }
        } catch {
            let current = try? await ref.getDocument(source: .server).data()
            guard (current?["memberIds"] as? [String])?.contains(uid) == true else { throw error }
        }
        return ["sessionId": id]
    }

    private func startGame(_ data: [String: Any]) async throws -> [String: Any] {
        let ref = db.collection("sessions").document(try identifier(data["sessionId"]))
        _ = try await transaction { [self] tx in
            var s = try required(tx.getDocument(ref))
            guard s["ownerId"] as? String == uid else { throw GameWriteError("Only your team captain can start.") }
            if s["status"] as? String == "active", isOpen(s) { return [:] }
            let g = try required(tx.getDocument(db.collection("games").document(try identifier(s["gameId"]))))
            guard s["status"] as? String == "waiting", isOpen(s), let created = s["createdAt"] as? Timestamp,
                  let routes = g["routes"] as? [[String: Any]], !routes.isEmpty else { throw GameWriteError("The lobby or course is unavailable.") }
            let index = Int(created.nanoseconds / 1000) % routes.count
            guard let points = routes[index]["checkpointIds"] as? [String], !points.isEmpty else { throw DataError.invalid }
            s["status"] = "active"; s["startedAt"] = FieldValue.serverTimestamp()
            s["checkpointIds"] = points; s["routeIndex"] = index; s["updatedAt"] = FieldValue.serverTimestamp()
            tx.setData(s, forDocument: ref)
            tx.setData(try projection(s), forDocument: try boardReference(s, id: ref.documentID))
            return [:]
        }
        return ["ok": true]
    }

    private func submitAnswer(_ data: [String: Any]) async throws -> [String: Any] {
        let id = try identifier(data["sessionId"])
        let pointId = try identifier(data["checkpointId"])
        let ref = db.collection("sessions").document(id)
        let receipt = profile.collection("attempts").document(id + "_" + pointId)
        let original = try required(await ref.getDocument(source: .server))
        if (original["completedIds"] as? [String])?.contains(pointId) == true {
            try? await receipt.delete()
            return ["accepted": true, "duplicate": true, "score": original["score"] ?? 0]
        }
        let answer = try text(data["answer"], limit: 300).precomposedStringWithCompatibilityMapping
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").lowercased()
        guard let fix = data["location"] as? [String: Any], let latitude = fix["latitude"] as? Double,
              let longitude = fix["longitude"] as? Double, let accuracy = fix["accuracy"] as? Double,
              let capturedAt = fix["capturedAt"] as? Double, [latitude, longitude, accuracy, capturedAt].allSatisfy(\.isFinite),
              abs(latitude) <= 90, abs(longitude) <= 180 else { throw GameWriteError("A current precise location is required.") }
        do {
            try await receipt.setData(["sessionId": id, "checkpointId": pointId, "answer": answer,
                "location": GeoPoint(latitude: latitude, longitude: longitude), "accuracy": accuracy,
                "capturedAt": capturedAt, "receivedAt": FieldValue.serverTimestamp()])
        } catch {
            let latest = try? await ref.getDocument(source: .server).data()
            if (latest?["completedIds"] as? [String])?.contains(pointId) == true {
                return ["accepted": true, "duplicate": true, "score": latest?["score"] ?? 0]
            }
            throw GameWriteError("The answer could not be accepted. Check your answer, location, and activity time.")
        }
        for attempt in 0..<3 {
            do {
                let result = try await transaction { [self] tx in
                    var s = try required(tx.getDocument(ref))
                    var completed = s["completedIds"] as? [String] ?? []
                    if completed.contains(pointId) { return ["accepted": true, "duplicate": true, "score": s["score"] ?? 0] }
                    let a = try required(tx.getDocument(receipt))
                    let point = try required(tx.getDocument(db.collection("games").document(try identifier(s["gameId"])).collection("checkpoints").document(pointId)))
                    guard let receivedAt = a["receivedAt"] as? Timestamp, let points = point["points"] as? Int,
                          let score = s["score"] as? Int, let route = s["checkpointIds"] as? [String] else { throw DataError.invalid }
                    let previous = s["lastScoredAt"] as? Timestamp
                    let scoredAt: Timestamp
                    if let previous, previous.dateValue() > receivedAt.dateValue() { scoredAt = previous }
                    else { scoredAt = receivedAt }
                    completed.append(pointId)
                    let complete = completed.count == route.count
                    s["score"] = score + points; s["completedIds"] = completed; s["lastScoredAt"] = scoredAt
                    s["lastCheckpointId"] = pointId; s["status"] = complete ? "completed" : "active"
                    s["finishedAt"] = complete ? scoredAt : NSNull(); s["updatedAt"] = FieldValue.serverTimestamp()
                    tx.setData(s, forDocument: ref)
                    tx.setData(try projection(s), forDocument: try boardReference(s, id: id))
                    return ["accepted": true, "duplicate": false, "score": score + points]
                }
                try? await receipt.delete()
                return result as? [String: Any] ?? [:]
            } catch {
                let current = try await ref.getDocument(source: .server).data()
                if (current?["completedIds"] as? [String])?.contains(pointId) == true {
                    try? await receipt.delete()
                    return ["accepted": true, "duplicate": true, "score": current?["score"] ?? 0]
                }
                if attempt == 2 || current?["status"] as? String != "active" { throw error }
            }
        }
        throw GameWriteError("Your team is updating. Please try again.")
    }

    private func refreshSession(_ data: [String: Any]) async throws -> [String: Any] {
        let clock = try await syncProfile([:])
        let ref = db.collection("sessions").document(try identifier(data["sessionId"]))
        let milliseconds = clock["serverTime"] as? Double ?? now.timeIntervalSince1970 * 1000
        _ = try await transaction { [self] tx in
            var s = try required(tx.getDocument(ref))
            let end = try deadline(s)
            guard ["waiting", "active"].contains(s["status"] as? String ?? ""), end <= milliseconds else { return [:] }
            let endMilliseconds = Int64(end)
            s["status"] = "expired"
            s["finishedAt"] = Timestamp(seconds: endMilliseconds / 1000, nanoseconds: Int32(endMilliseconds % 1000) * 1000000)
            s["updatedAt"] = FieldValue.serverTimestamp()
            tx.setData(s, forDocument: ref)
            if s["startedAt"] is Timestamp { tx.setData(try projection(s), forDocument: try boardReference(s, id: ref.documentID)) }
            return [:]
        }
        return clock
    }

    private func leaveTeam(_ data: [String: Any]) async throws -> [String: Any] {
        let ref = db.collection("sessions").document(try identifier(data["sessionId"]))
        _ = try await transaction { [self] tx in
            var s = try required(tx.getDocument(ref))
            guard ["waiting", "active"].contains(s["status"] as? String ?? "") else { return [:] }
            if s["ownerId"] as? String == uid {
                s["status"] = "cancelled"; s["finishedAt"] = FieldValue.serverTimestamp()
                s["updatedAt"] = FieldValue.serverTimestamp()
                tx.setData(s, forDocument: ref)
                if s["startedAt"] is Timestamp { tx.setData(try projection(s), forDocument: try boardReference(s, id: ref.documentID)) }
            } else {
                guard s["status"] as? String == "waiting" else { throw GameWriteError("Ask your team captain to end the activity.") }
                s["memberIds"] = (s["memberIds"] as? [String] ?? []).filter { $0 != uid }
                var names = s["memberNames"] as? [String: String] ?? [:]; names.removeValue(forKey: uid)
                s["memberNames"] = names; s["updatedAt"] = FieldValue.serverTimestamp()
                tx.setData(s, forDocument: ref)
                tx.updateData(["activeSessionId": NSNull(), "updatedAt": FieldValue.serverTimestamp()], forDocument: profile)
            }
            return [:]
        }
        return ["ok": true]
    }

    private func deleteAccount() async throws -> [String: Any] {
        try await profile.updateData(["deleting": true, "displayName": "Deleted player", "activeSessionId": NSNull(), "updatedAt": FieldValue.serverTimestamp()])
        while true {
            let page = try await db.collection("sessions").whereField("memberIds", arrayContains: uid).limit(to: 20).getDocuments(source: .server)
            if page.isEmpty { break }
            for document in page.documents {
                _ = try await transaction { [self] tx in
                    var s = try required(tx.getDocument(document.reference))
                    let members = (s["memberIds"] as? [String] ?? []).filter { $0 != uid }
                    var names = s["memberNames"] as? [String: String] ?? [:]; names.removeValue(forKey: uid)
                    s["memberIds"] = members; s["memberNames"] = names
                    if s["ownerId"] as? String == uid { s["ownerId"] = members.first ?? "" }
                    if members.isEmpty { s["teamName"] = "Deleted team" }
                    s["updatedAt"] = FieldValue.serverTimestamp()
                    tx.setData(s, forDocument: document.reference)
                    if s["startedAt"] is Timestamp { tx.setData(try projection(s), forDocument: try boardReference(s, id: document.documentID)) }
                    return [:]
                }
            }
        }
        for collection in ["attempts", "entries"] {
            while true {
                let page = try await profile.collection(collection).limit(to: 100).getDocuments(source: .server)
                if page.isEmpty { break }
                let batch = db.batch()
                page.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        }
        try await user.delete()
        return ["ok": true]
    }

    private func available(_ tx: Transaction, profile: [String: Any]) throws {
        guard profile["deleting"] as? Bool != true else { throw GameWriteError("Account deletion is in progress.") }
        if let previous = profile["activeSessionId"] as? String,
           let s = try tx.getDocument(db.collection("sessions").document(previous)).data(), isOpen(s) {
            throw GameWriteError("Finish or leave your current team first.")
        }
    }

    private func isOpen(_ data: [String: Any]) -> Bool {
        ["waiting", "active"].contains(data["status"] as? String ?? "") && ((try? deadline(data)) ?? 0) > now.timeIntervalSince1970 * 1000
    }

    private func deadline(_ data: [String: Any]) throws -> Double {
        guard let created = data["createdAt"] as? Timestamp, let duration = data["durationSeconds"] as? Int,
              let end = data["gameEndsAt"] as? Double, (60...86400).contains(duration),
              end.isFinite, end >= 0, end <= 9007199254740991 else { throw DataError.invalid }
        let started = data["startedAt"] as? Timestamp
        return min(Double(milliseconds(started ?? created)) + Double(started == nil ? 3600000 : duration * 1000), end)
    }

    private func projection(_ data: [String: Any]) throws -> [String: Any] {
        var elapsed = 0
        if let start = data["startedAt"] as? Timestamp {
            if data["status"] as? String == "expired" {
                elapsed = Int((try deadline(data) - Double(milliseconds(start))) / 1000)
            } else if let last = data["lastScoredAt"] as? Timestamp {
                elapsed = Int((last.seconds - start.seconds) * 1000 + Int64(last.nanoseconds / 1000000 - start.nanoseconds / 1000000)) / 1000
            }
        }
        return ["teamName": data["teamName"] ?? "Team", "score": data["score"] ?? 0,
            "status": data["status"] ?? "waiting", "elapsedSeconds": max(0, elapsed), "updatedAt": FieldValue.serverTimestamp()]
    }

    private func boardReference(_ data: [String: Any], id: String) throws -> DocumentReference {
        db.collection("games").document(try identifier(data["gameId"])).collection("leaderboard").document(id)
    }

    private func milliseconds(_ timestamp: Timestamp) -> Int64 {
        timestamp.seconds * 1000 + Int64(timestamp.nanoseconds / 1000000)
    }

    private func required(_ document: DocumentSnapshot) throws -> [String: Any] {
        guard let data = document.data() else { throw GameWriteError("The requested activity is unavailable.") }
        return data
    }

    private func text(_ value: Any?, limit: Int) throws -> String {
        guard let raw = value as? String else { throw GameWriteError("Complete the required fields.") }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= limit, value.rangeOfCharacter(from: .controlCharacters) == nil else { throw GameWriteError("The entered text is invalid or too long.") }
        return value
    }

    private func identifier(_ value: Any?) throws -> String {
        let result = try text(value, limit: 128)
        guard result.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw GameWriteError("The activity identifier is invalid.") }
        return result
    }
}

/// Presents a safe, actionable gameplay error without exposing database details.
/// - Example: `throw GameWriteError("This team is full.")`.
struct GameWriteError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
