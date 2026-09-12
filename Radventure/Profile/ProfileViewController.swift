import UIKit
import FirebaseAuth
import FirebaseFirestore

/// Shows account identity and paginated shared activity history.
/// - Note: Signing out does not erase or lock the player's active session.
/// - Example: `ProfileViewController(store: store)`.
@MainActor
final class ProfileViewController: TaskViewController, UITableViewDataSource {
    private let store: GameStore
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let accountLabel = AppUI.label(style: .title2)
    private var history: [GameSession] = []
    private var cursor: DocumentSnapshot?
    private var moreAvailable = true

    /// Inject the current account's shared store.
    /// - Parameter store: Live account state.
    /// - Returns: A profile controller.
    /// - Example: `ProfileViewController(store: store)`.
    init(store: GameStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }

    /// Build the account controls and history table.
    /// - Returns: Nothing.
    /// - Example: Called by UIKit.
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        accountLabel.text = "\(Auth.auth().currentUser?.displayName ?? "Player")\n\(Auth.auth().currentUser?.email ?? "")"
        table.dataSource = self
        table.heightAnchor.constraint(equalToConstant: 420).isActive = true
        let loadMore = AppUI.button("Load more history", action: UIAction { [weak self] _ in self?.loadHistory(reset: false) })
        let signOut = AppUI.button("Sign out", action: UIAction { [weak self] _ in self?.run { try Auth.auth().signOut() } })
        let delete = AppUI.button("Delete account", action: UIAction { [weak self] _ in self?.deleteAccount() })
        AppUI.form([accountLabel, AppUI.label("Activity history", style: .headline), table, loadMore, signOut, delete], in: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Refresh", primaryAction: UIAction { [weak self] _ in self?.loadHistory(reset: true) })
    }

    /// Refresh server history whenever the profile becomes visible.
    /// - Parameter animated: UIKit animation flag.
    /// - Returns: Nothing.
    /// - Example: Called after completing an activity on the map.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadHistory(reset: true)
    }

    private func loadHistory(reset: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if !reset && !moreAvailable { showMessage("You have reached the end of your activity history."); return }
        run { [self] in
            var query = Backend.db.collection("sessions").whereField("memberIds", arrayContains: uid).order(by: "createdAt", descending: true).limit(to: 25)
            if !reset, let cursor { query = query.start(afterDocument: cursor) }
            let result = try await query.getDocuments(source: .server)
            let page = try result.documents.map { try GameSession.decode(id: $0.documentID, data: $0.data()) }
            if reset { history = page } else { history.append(contentsOf: page.filter { item in !history.contains { $0.id == item.id } }) }
            cursor = result.documents.last
            moreAvailable = result.documents.count == 25
            table.backgroundView = history.isEmpty ? AppUI.label("No activities yet. Join a team to get started.") : nil
            table.reloadData()
        }
    }

    private func deleteAccount() {
        guard let user = Auth.auth().currentUser, let email = user.email else { return }
        let alert = UIAlertController(title: "Delete your account?", message: "This permanently removes your account and personal membership history. Shared team results remain without your identity. Finish or leave your current activity first. Enter your password to confirm.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Current password"; $0.isSecureTextEntry = true; $0.textContentType = .password }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete account", style: .destructive) { [weak self, weak alert] _ in
            guard let password = alert?.textFields?.first?.text, !password.isEmpty else { return }
            self?.run {
                let credential = EmailAuthProvider.credential(withEmail: email, password: password)
                _ = try await user.reauthenticate(with: credential)
                _ = try await user.getIDTokenResult(forcingRefresh: true)
                try await Backend.call("deleteAccount")
                try Auth.auth().signOut()
            }
        })
        present(alert, animated: true)
    }

    /// Return the number of loaded history records.
    /// - Parameters:
    ///   - tableView: History table.
    ///   - section: Requested section.
    /// - Returns: Current row count.
    /// - Example: Called by UITableView.
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { history.count }

    /// Render an activity's recorded score, status, and date.
    /// - Parameters:
    ///   - tableView: History table.
    ///   - indexPath: Requested history row.
    /// - Returns: A configured history cell.
    /// - Example: Called by UITableView.
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = history[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "history") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "history")
        var content = cell.defaultContentConfiguration()
        content.text = "\(item.gameName) · \(item.teamName)"
        let status = ["active", "waiting"].contains(item.status) && !item.isOpen(at: Backend.now) ? "expired" : item.status
        content.secondaryText = "\(item.score) points · \(status)\n\(item.createdDate.formatted(date: .abbreviated, time: .shortened))"
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }
}
