import XCTest
import FirebaseCore
import FirebaseAppCheck
import FirebaseFirestore
import FirebaseAuth
@testable import Radventure

/// Regression tests for models, deadlines, presentation, and physical-device attestation.
/// - Example: Run the RadventureTests target in Xcode.
final class RadventureTests: XCTestCase {
    /// Exercise the production game service and App Check using a disposable device account.
    /// - Note: An explicit test tag and owner-prepared fixture are required. Existing sign-ins are preserved.
    /// - Throws: XCTest skip, Firebase failures, or failed gameplay assertions.
    /// - Example: Run only this test using the documented temporary xctestrun environment.
    @MainActor
    func testLiveGameplayOnPhysicalDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Live App Check gameplay requires a physical device.")
        #else
        guard let tag = ProcessInfo.processInfo.environment["COMPASS_QA_TAG"],
              tag.range(of: "^[a-f0-9]{16}$", options: .regularExpression) != nil else {
            throw XCTSkip("An explicit temporary live fixture is required.")
        }
        try XCTSkipIf(Auth.auth().currentUser != nil, "Preserve the owner's signed-in account.")
        let email = "compass-device-\(tag)@example.test"
        let password = UUID().uuidString + UUID().uuidString
        let user = try await Auth.auth().createUser(withEmail: email, password: password).user
        for _ in 0..<30 {
            try await user.reload()
            if user.isEmailVerified { break }
            try await Task.sleep(nanoseconds: 2000000000)
        }
        XCTAssertTrue(user.isEmailVerified, "The owner-side fixture must verify this exact temporary account.")
        _ = try await user.getIDTokenResult(forcingRefresh: true)
        _ = try await AppCheck.appCheck().token(forcingRefresh: true)
        try await Backend.call("syncProfile", ["displayName": "Device QA"])
        let result = try await Backend.call("createTeam", ["gameId": "qa-device-\(tag)", "teamName": "Device QA"])
        let id = try XCTUnwrap(result["sessionId"] as? String)
        try await Backend.call("startGame", ["sessionId": id])
        let response = try await Backend.call("submitAnswer", ["sessionId": id, "checkpointId": "point", "answer": "correct",
            "location": ["latitude": 41.0, "longitude": 29.0, "accuracy": 5.0, "capturedAt": Backend.now.timeIntervalSince1970 * 1000]])
        XCTAssertEqual(response["accepted"] as? Bool, true)
        let score = try await Backend.db.collection("games").document("qa-device-\(tag)").collection("leaderboard").document(id).getDocument(source: .server)
        XCTAssertEqual(score.data()?["score"] as? Int, 100)
        XCTAssertEqual(score.data()?["status"] as? String, "completed")
        try await Backend.call("deleteAccount")
        XCTAssertNil(Auth.auth().currentUser)
        #endif
    }

    /// Verify the bundled cloud configuration and Apple attestation on a real device.
    /// - Note: Simulators and unconfigured checkouts skip this live service check.
    /// - Throws: XCTest skip or missing-configuration errors; token values are never logged.
    /// - Example: Run RadventureTests on a paired iPhone with the new Firebase configuration.
    @MainActor
    func testLiveAppAttestOnPhysicalDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("App Attest requires a physical device.")
        #else
        try XCTSkipIf(Backend.isEmulator || Backend.setupError != nil, "This check requires live Firebase configuration.")
        let app = try XCTUnwrap(FirebaseApp.app())
        XCTAssertEqual(app.options.bundleID, Bundle.main.bundleIdentifier)
        do {
            let result = try await AppCheck.appCheck().token(forcingRefresh: true)
            XCTAssertFalse(result.token.isEmpty)
            XCTAssertGreaterThan(result.expirationDate, Date())
        } catch {
            let failure = error as NSError
            XCTFail("App Attest failed with domain \(failure.domain), code \(failure.code).")
        }
        #endif
    }

    private func session(expiresAt: Double = 100000, status: String = "active") throws -> GameSession {
        try GameSession.decode(id: "session-1", data: [
            "gameId": "course", "gameName": "Course", "teamName": "Team", "ownerId": "owner",
            "memberIds": ["owner"], "memberNames": ["owner": "Player"], "joinCode": "123456ABCDEF",
            "status": status, "score": 100, "checkpointIds": ["one", "two"], "completedIds": ["one"],
            "createdAt": 0, "expiresAt": expiresAt,
        ])
    }

    /// Ensure equality at the deadline is expired, even after a suspended timer.
    /// - Throws: Model decoding errors.
    /// - Example: Run with XCTest.
    func testDeadlineExpiresAtExactBoundary() throws {
        let value = try session()
        XCTAssertTrue(value.isOpen(at: Date(timeIntervalSince1970: 99.9)))
        XCTAssertFalse(value.isOpen(at: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(value.isOpen(at: Date(timeIntervalSince1970: 120)))
        XCTAssertEqual(value.remainingSeconds(at: Date(timeIntervalSince1970: 120)), 0)
    }

    /// Decode Spark timestamps using the same millisecond boundary as security rules.
    /// - Throws: Model decoding errors.
    /// - Example: Run with XCTest.
    func testSparkDeadlineUsesTrustedTimestampsAndCourseEnd() throws {
        var fields: [String: Any] = [
            "schemaVersion": 2, "gameId": "course", "gameName": "Course", "teamName": "Team", "ownerId": "owner",
            "memberIds": ["owner"], "memberNames": ["owner": "Player"], "joinCode": "123456ABCDEF",
            "status": "waiting", "score": 0, "checkpointIds": [], "completedIds": [],
            "createdAt": Timestamp(seconds: 100, nanoseconds: 123456000), "startedAt": NSNull(),
            "durationSeconds": 60, "gameEndsAt": 9000000.0, "expiresAt": 99999999.0,
        ]
        let waiting = try GameSession.decode(id: "spark", data: fields)
        XCTAssertEqual(waiting.expiresAt, 3700123)
        fields["startedAt"] = Timestamp(seconds: 110, nanoseconds: 654321000)
        fields["status"] = "active"
        let active = try GameSession.decode(id: "spark", data: fields)
        XCTAssertEqual(active.expiresAt, 170654)
        XCTAssertFalse(active.isOpen(at: Date(timeIntervalSince1970: 170.654)))
        fields["gameEndsAt"] = 150000.0
        XCTAssertEqual(try GameSession.decode(id: "spark", data: fields).expiresAt, 150000)
        fields["durationSeconds"] = Int.max
        XCTAssertThrowsError(try GameSession.decode(id: "spark", data: fields))
    }

    /// Use absolute dates so a course can cross midnight or a timezone boundary.
    /// - Throws: Model decoding errors.
    /// - Example: Run with XCTest.
    func testCountdownCrossesMidnightAndRoundsUp() throws {
        let end = ISO8601DateFormatter().date(from: "2026-09-13T00:01:00Z")!
        let value = try session(expiresAt: end.timeIntervalSince1970 * 1000)
        XCTAssertEqual(value.remainingSeconds(at: end.addingTimeInterval(-61.1)), 62)
        XCTAssertEqual(value.remainingSeconds(at: end.addingTimeInterval(-60)), 60)
    }

    /// Completed sessions never become active because their deadline is in the future.
    /// - Throws: Model decoding errors.
    /// - Example: Run with XCTest.
    func testCompletedSessionCannotResumeGameplay() throws {
        XCTAssertFalse(try session(status: "completed").isOpen(at: Date(timeIntervalSince1970: 1)))
    }

    /// A corrupt deadline cannot overflow an integer or crash the timer display.
    /// - Throws: Model decoding errors.
    /// - Example: Run with XCTest.
    func testExtremeDeadlineCannotOverflowCountdown() throws {
        XCTAssertEqual(try session(expiresAt: 1e100).remainingSeconds(at: Date()), 86400)
        XCTAssertEqual(try session(expiresAt: -1e100).remainingSeconds(at: Date()), 0)
    }

    /// Malformed records return a recoverable error rather than forcing an unwrap.
    /// - Returns: Nothing.
    /// - Example: Run with XCTest.
    func testIncompleteAndWrongTypedDocumentsAreRejected() {
        XCTAssertThrowsError(try GameSession.decode(id: "session", data: [:]))
        XCTAssertThrowsError(try LeaderboardEntry.decode(id: "session", data: ["teamName": "Team", "score": "100", "elapsedSeconds": 4, "status": "active"]))
        XCTAssertThrowsError(try LeaderboardEntry.decode(id: "session", data: ["teamName": "Team", "score": true, "elapsedSeconds": 4, "status": "active"]))
    }

    /// Stable IDs come from the database path, not a conflicting embedded field.
    /// - Throws: Decoding errors.
    /// - Example: Run with XCTest.
    func testDocumentIdentifierCannotBeOverridden() throws {
        let row = try LeaderboardEntry.decode(id: "real-id", data: ["id": "forged-id", "teamName": "Team", "score": 100, "elapsedSeconds": 61, "status": "completed"])
        XCTAssertEqual(row.id, "real-id")
    }

    /// Format elapsed seconds without dropping leading zeros or wrapping after an hour.
    /// - Returns: Nothing.
    /// - Example: Run with XCTest.
    @MainActor
    func testDurationFormatting() {
        XCTAssertEqual(AppUI.duration(0), "00:00")
        XCTAssertEqual(AppUI.duration(9), "00:09")
        XCTAssertEqual(AppUI.duration(65), "01:05")
        XCTAssertEqual(AppUI.duration(3601), "60:01")
        XCTAssertEqual(AppUI.duration(-1), "00:00")
    }
}
