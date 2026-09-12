import UIKit
import Combine
import FirebaseFirestore

/// Shows a live, server-ranked leaderboard for the selected course.
/// - Note: One listener replaces repeated full-database polling.
/// - Example: `ScoreboardViewController(store: store)`.
@MainActor
final class ScoreboardViewController: TaskViewController, UITableViewDataSource {
    private let store: GameStore
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let message = AppUI.label("Choose a course to see its leaderboard.")
    private var entries: [LeaderboardEntry] = []
    private var listener: ListenerRegistration?
    private var selectedID: String?
    private var subscriptions = Set<AnyCancellable>()

    /// Inject the signed-in course and session store.
    /// - Parameter store: Shared account state.
    /// - Returns: A leaderboard controller.
    /// - Example: `ScoreboardViewController(store: store)`.
    init(store: GameStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }

    /// Build the course picker and accessible leaderboard table.
    /// - Returns: Nothing.
    /// - Example: Called by UIKit.
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        table.dataSource = self
        table.accessibilityIdentifier = "Leaderboard results"
        table.translatesAutoresizingMaskIntoConstraints = false
        message.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(message)
        view.addSubview(table)
        NSLayoutConstraint.activate([
            message.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            table.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 12),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Course", primaryAction: UIAction { [weak self] _ in self?.chooseCourse() })
        store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.selectDefault() }.store(in: &subscriptions)
        selectDefault()
    }

    private func selectDefault() {
        guard selectedID == nil, let course = store.courses.first(where: { $0.id == store.session?.gameId }) ?? store.courses.first else { return }
        select(course)
    }

    private func chooseCourse() {
        run { [self] in
            try await store.loadCourses()
            guard !store.courses.isEmpty else { showMessage("No courses are available yet."); return }
            let alert = UIAlertController(title: "Leaderboard course", message: nil, preferredStyle: .actionSheet)
            store.courses.forEach { course in alert.addAction(UIAlertAction(title: course.name, style: .default) { [weak self] _ in self?.select(course) }) }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
            present(alert, animated: true)
        }
    }

    private func select(_ course: Course) {
        selectedID = course.id
        listener?.remove()
        entries = []
        table.reloadData()
        message.text = "\(course.name)\nLoading results..."
        listener = Backend.db.collection("games").document(course.id).collection("leaderboard")
            .order(by: "score", descending: true).order(by: "elapsedSeconds").limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self, selectedID == course.id else { return }
                    if let error { message.text = error.localizedDescription; return }
                    do {
                        entries = try (snapshot?.documents ?? []).map { try LeaderboardEntry.decode(id: $0.documentID, data: $0.data()) }
                        message.text = "\(course.name)\n\(entries.isEmpty ? "No scores yet. Start a team activity to appear here." : "Top 100 teams · points, then elapsed time")"
                        if snapshot?.metadata.isFromCache == true { message.text?.append("\nOffline: showing saved results.") }
                        table.reloadData()
                    } catch { message.text = error.localizedDescription }
                }
            }
    }

    /// Return the number of visible leaderboard entries.
    /// - Parameters:
    ///   - tableView: Leaderboard table.
    ///   - section: Requested section.
    /// - Returns: Number of server-ranked rows.
    /// - Example: Called by UITableView.
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count }

    /// Render one result without relying on reusable cell state from another row.
    /// - Parameters:
    ///   - tableView: Leaderboard table.
    ///   - indexPath: Requested rank.
    /// - Returns: Configured result cell.
    /// - Example: Called by UITableView.
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = entries[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "result") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "result")
        var content = cell.defaultContentConfiguration()
        content.text = "\(indexPath.row + 1). \(item.teamName)"
        content.secondaryText = "\(item.score) points · \(AppUI.duration(item.elapsedSeconds)) · \(item.status)"
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }

    deinit { listener?.remove() }
}
