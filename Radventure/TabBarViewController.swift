import UIKit

/// Hosts map, live leaderboard, and profile with one shared session store.
/// - Example: Installed by SceneDelegate for a verified account.
@MainActor
final class TabBarViewController: UITabBarController {
    private let store = GameStore()

    /// Create labeled navigation tabs and connect the signed-in user's backend.
    /// - Returns: Nothing.
    /// - Example: Called by UIKit when the authenticated interface opens.
    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.tintColor = UIColor(named: "AppColor3") ?? .systemIndigo
        let controllers: [(UIViewController, String, String)] = [
            (HomeMapViewController(store: store), "Explore", "map"),
            (ScoreboardViewController(store: store), "Leaderboard", "list.number"),
            (ProfileViewController(store: store), "Profile", "person.crop.circle"),
        ]
        viewControllers = controllers.map { controller, title, symbol in
            controller.title = title
            let navigation = UINavigationController(rootViewController: controller)
            navigation.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), tag: 0)
            return navigation
        }
        Task { await store.connect() }
    }
}
