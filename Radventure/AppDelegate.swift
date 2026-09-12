import UIKit

/// Starts the app without requesting unused notification permissions.
/// - Example: UIKit constructs this delegate through `@main`.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Configure services before UIKit connects the first scene.
    /// - Parameters:
    ///   - application: Current UIKit application.
    ///   - launchOptions: System launch context.
    /// - Returns: True, including recoverable configuration failures.
    /// - Example: Called by UIKit during launch.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Backend.configure()
        return true
    }
}
