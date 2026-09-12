import Foundation
import CoreLocation
import FirebaseFirestore

/// Public course configuration. Answers are kept in server-only documents.
/// - Example: `try Course.decode(id: documentID, data: fields)`.
struct Course: Decodable, DocumentModel {
    let id: String
    let name: String
    let rules: String
    let startsAt: Double
    let endsAt: Double
    let durationSeconds: Int
    let maxTeamSize: Int
    let requiresEntryCode: Bool
    let latitude: Double
    let longitude: Double
    var startDate: Date { Date(timeIntervalSince1970: startsAt / 1000) }
    var endDate: Date { Date(timeIntervalSince1970: endsAt / 1000) }
}

/// A checkpoint's public question and GPS requirement, excluding its answer.
/// - Example: `try Checkpoint.decode(id: "gate", data: fields)`.
struct Checkpoint: Decodable, DocumentModel {
    let id: String
    let name: String
    let question: String
    let options: [String]
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    let points: Int
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var isValid: Bool { abs(latitude) <= 90 && abs(longitude) <= 180 && radiusMeters > 0 && points > 0 }
}

/// Rules-validated team state that can be restored across devices and app suspension.
/// - Note: All numeric dates are epoch milliseconds, independent of local timezone.
/// - Example: `session.remainingSeconds(at: Date())`.
struct GameSession: Decodable, DocumentModel {
    let id: String
    let gameId: String
    let gameName: String
    let teamName: String
    let ownerId: String
    let memberIds: [String]
    let memberNames: [String: String]
    let joinCode: String
    let status: String
    let score: Int
    let checkpointIds: [String]
    let completedIds: [String]
    let createdAt: Double
    let expiresAt: Double
    var createdDate: Date { Date(timeIntervalSince1970: createdAt / 1000) }
    var expiryDate: Date { Date(timeIntervalSince1970: expiresAt / 1000) }

    /// Return a nonnegative countdown that survives suspension and midnight.
    /// - Parameter date: Current server-adjusted wall clock.
    /// - Returns: Whole seconds remaining, rounded up for display.
    /// - Example: `session.remainingSeconds(at: Date())`.
    func remainingSeconds(at date: Date) -> Int {
        let seconds = ceil(expiryDate.timeIntervalSince(date))
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds, 86400))
    }

    /// Check whether the session still accepts lobby or gameplay operations.
    /// - Parameter date: Current server-adjusted time.
    /// - Returns: True only for an unexpired waiting or active session.
    /// - Example: `session.isOpen(at: Date())`.
    func isOpen(at date: Date) -> Bool { ["waiting", "active"].contains(status) && expiryDate > date }
}

/// Public score projection without private account details or team invite codes.
/// - Example: `try LeaderboardEntry.decode(id: documentID, data: fields)`.
struct LeaderboardEntry: Decodable, DocumentModel {
    let id: String
    let teamName: String
    let score: Int
    let elapsedSeconds: Int
    let status: String
}

/// Decodes Firestore's JSON-compatible fields through a typed contract.
/// - Example: `try Course.decode(id: "campus", data: document.data())`.
protocol DocumentModel: Decodable {}
extension DocumentModel {
    /// Decode a dictionary after injecting its stable Firestore identifier.
    /// - Parameters:
    ///   - id: Document identifier, never read from user-controlled fields.
    ///   - data: Server-written JSON-compatible data.
    /// - Returns: Validated field types for this model.
    /// - Throws: `DataError.invalid` if data is malformed or fields are missing.
    /// - Example: `try GameSession.decode(id: documentID, data: fields)`.
    static func decode(id: String, data: [String: Any]) throws -> Self {
        var fields = data.mapValues { value -> Any in
            if let timestamp = value as? Timestamp {
                return Double(timestamp.seconds * 1000 + Int64(timestamp.nanoseconds / 1000000))
            }
            return value
        }
        if fields["schemaVersion"] as? Int == 2, let created = fields["createdAt"] as? Double,
           let end = fields["gameEndsAt"] as? Double, let duration = fields["durationSeconds"] as? Int {
            guard (60...86400).contains(duration), end.isFinite else { throw DataError.invalid }
            let start = fields["startedAt"] as? Double
            fields["expiresAt"] = min((start ?? created) + Double(start == nil ? 3600000 : duration * 1000), end)
        }
        fields["id"] = id
        do {
            let encoded = try JSONSerialization.data(withJSONObject: fields)
            return try JSONDecoder().decode(Self.self, from: encoded)
        } catch { throw DataError.invalid }
    }
}

enum DataError: LocalizedError {
    case invalid
    var errorDescription: String? { "Some course data is incomplete. Ask the organizer to check the course setup." }
}
