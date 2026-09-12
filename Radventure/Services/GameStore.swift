import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Owns one signed-in player's live session and cleans up subscriptions on logout.
/// - Note: Controllers share this store instead of writing separate copies of scores.
/// - Example: `let store = GameStore()` after email verification.
@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var session: GameSession?
    @Published private(set) var courses: [Course] = []
    @Published private(set) var checkpoints: [Checkpoint] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = true
    private var profileListener: ListenerRegistration?
    private var sessionListener: ListenerRegistration?
    private var watchedID: String?
    private var courseTask: Task<Void, Never>?
    private var connecting = false

    /// Connect the profile listener and load available courses.
    /// - Returns: Nothing; published properties reflect results or an actionable error.
    /// - Example: `await store.connect()` when the tab controller opens.
    func connect() async {
        guard !connecting, let user = Auth.auth().currentUser else { return }
        connecting = true
        isLoading = true
        errorMessage = nil
        defer { connecting = false; isLoading = false }
        do {
            try await Backend.call("syncProfile", ["displayName": user.displayName ?? "Player"])
            try await loadCourses()
            profileListener?.remove()
            profileListener = Backend.db.collection("users").document(user.uid).addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error { errorMessage = error.localizedDescription; return }
                    watchSession(snapshot?.data()?["activeSessionId"] as? String)
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Reload published courses from the server without hiding connection failures.
    /// - Returns: Nothing; `courses` includes published historical courses for results.
    /// - Throws: A Firebase or decoding error.
    /// - Example: `try await store.loadCourses()` before opening the course picker.
    func loadCourses() async throws {
        let result = try await Backend.db.collection("games").whereField("published", isEqualTo: true).getDocuments(source: .server)
        courses = try result.documents.map { try Course.decode(id: $0.documentID, data: $0.data()) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Attach to the requested session, replacing all listeners from the previous one.
    /// - Parameter id: Session identifier from the authenticated profile or a callable.
    /// - Returns: Nothing; session and checkpoint changes are published.
    /// - Example: `store.watchSession(response["sessionId"] as? String)`.
    func watchSession(_ id: String?) {
        guard watchedID != id else { return }
        watchedID = id
        sessionListener?.remove()
        courseTask?.cancel()
        session = nil
        checkpoints = []
        guard let id else { return }
        sessionListener = Backend.db.collection("sessions").document(id).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self, watchedID == id else { return }
                if let error { errorMessage = error.localizedDescription; return }
                guard let data = snapshot?.data() else { session = nil; return }
                do {
                    let next = try GameSession.decode(id: id, data: data)
                    let changedCourse = session?.gameId != next.gameId
                    session = next
                    errorMessage = snapshot?.metadata.isFromCache == true ? "Showing saved progress. Reconnect before submitting an answer." : nil
                    if changedCourse { loadCheckpoints(gameId: next.gameId, sessionId: id) }
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func loadCheckpoints(gameId: String, sessionId: String) {
        courseTask?.cancel()
        courseTask = Task { [weak self] in
            do {
                let result = try await Backend.db.collection("games").document(gameId).collection("checkpoints").getDocuments()
                let points = try result.documents.map { try Checkpoint.decode(id: $0.documentID, data: $0.data()) }
                guard points.allSatisfy(\.isValid) else { throw DataError.invalid }
                guard !Task.isCancelled, let self, watchedID == sessionId else { return }
                checkpoints = points
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    /// Refresh authoritative expiry after suspension or when the countdown reaches zero.
    /// - Returns: Nothing; the session listener receives finalized state.
    /// - Throws: Connection or authorization errors from the server.
    /// - Example: `try await store.refresh()` on foreground entry.
    func refresh() async throws {
        guard let session else { return }
        try await Backend.call("refreshSession", ["sessionId": session.id])
    }

    deinit {
        profileListener?.remove()
        sessionListener?.remove()
        courseTask?.cancel()
    }
}
