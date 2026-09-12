import XCTest
@testable import Radventure

/// Regression tests for decoding, session deadlines, and duration presentation.
/// - Example: Run the RadventureTests target in Xcode.
final class RadventureTests: XCTestCase {
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
