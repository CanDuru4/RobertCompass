import UIKit

/// Displays locally available rules instead of opening an inaccessible Google document.
/// - Example: `RulesViewController(rules: course.rules)`.
final class RulesViewController: TaskViewController {
    private let rules: String

    /// Set the current course rules, with a useful general fallback.
    /// - Parameter rules: Organizer-authored course instructions.
    /// - Returns: A rules screen.
    /// - Example: `RulesViewController(rules: nil)` for general instructions.
    init(rules: String?) {
        self.rules = rules ?? "Create a team or join using your captain's invite code. The captain starts the activity once everyone has joined. Visit the marked checkpoints and answer their questions within the stated GPS radius. Correct answers add points once for the whole team. The server enforces the deadline. Your progress remains available when you return to the app. Follow the organizer's course and safety instructions."
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    /// Display readable, scrollable rules with Dynamic Type support.
    /// - Returns: Nothing.
    /// - Example: Called by UIKit.
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Rules"
        view.backgroundColor = .systemBackground
        AppUI.form([AppUI.label("How to play", style: .largeTitle), AppUI.label(rules)], in: self)
    }
}
