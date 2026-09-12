import UIKit
import FirebaseAuth

extension Notification.Name {
    static let accountDidChange = Notification.Name("compass.accountDidChange")
}

/// Routes each scene from authentication state, without stacking duplicate screens.
/// - Example: UIKit constructs this delegate from the scene manifest.
@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var authListener: AuthStateDidChangeListenerHandle?
    private var accountObserver: NSObjectProtocol?
    private var currentRoute = ""

    /// Create the scene window and subscribe to account changes.
    /// - Parameters:
    ///   - scene: Connecting window scene.
    ///   - session: UIKit scene session.
    ///   - connectionOptions: System connection context.
    /// - Returns: Nothing.
    /// - Example: Invoked by UIKit on launch.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        if let error = Backend.setupError {
            let controller = TaskViewController()
            controller.view.backgroundColor = .systemBackground
            AppUI.form([AppUI.label("Connect your backend", style: .largeTitle), AppUI.label(error)], in: controller)
            window?.rootViewController = controller
        } else {
            authListener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.route() }
            }
            accountObserver = NotificationCenter.default.addObserver(forName: .accountDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.route() }
            }
            route()
        }
        window?.makeKeyAndVisible()
    }

    private func route() {
        let user = Auth.auth().currentUser
        let destination = user == nil ? "login" : (user?.isEmailVerified == true ? "app" : "verify")
        guard destination != currentRoute else { return }
        currentRoute = destination
        let controller: UIViewController = destination == "app" ? TabBarViewController() : UINavigationController(rootViewController: LogInViewController())
        window?.rootViewController = controller
    }

    deinit {
        if let authListener { Auth.auth().removeStateDidChangeListener(authListener) }
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
    }
}
