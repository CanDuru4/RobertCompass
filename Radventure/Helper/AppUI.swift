import UIKit

/// Shared accessible UIKit controls and error presentation.
/// - Example: `AppUI.button("Start", action: UIAction { _ in ... })`.
@MainActor
enum AppUI {
    /// Make a standard button with Dynamic Type and a comfortable touch target.
    /// - Parameters:
    ///   - title: Visible and accessible title.
    ///   - action: Action invoked on tap.
    /// - Returns: A configured button.
    /// - Example: `AppUI.button("Retry", action: retryAction)`.
    static func button(_ title: String, action: UIAction) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = UIColor(named: "AppColor3") ?? .systemIndigo
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        let button = UIButton(configuration: config, primaryAction: action)
        button.accessibilityIdentifier = title
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        return button
    }

    /// Create a wrapping, scalable label.
    /// - Parameters:
    ///   - text: Initial copy.
    ///   - style: System text style.
    /// - Returns: Accessible multiline label.
    /// - Example: `AppUI.label("Welcome", style: .title1)`.
    static func label(_ text: String = "", style: UIFont.TextStyle = .body) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }

    /// Lay out a scrolling vertical form that remains usable with the keyboard open.
    /// - Parameters:
    ///   - views: Ordered arranged subviews.
    ///   - controller: Owner of the form.
    /// - Returns: The stack for later content changes.
    /// - Example: `AppUI.form([email, password, submit], in: self)`.
    @discardableResult
    static func form(_ views: [UIView], in controller: UIViewController) -> UIStackView {
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 16
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: controller.view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
        ])
        return stack
    }

    /// Format a duration without local date or timezone assumptions.
    /// - Parameter seconds: Nonnegative duration in seconds.
    /// - Returns: Minute and second display.
    /// - Example: `AppUI.duration(65)` returns `01:05`.
    static func duration(_ seconds: Int) -> String { String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60) }
}

/// Base controller that serializes taps and always restores controls after a failure.
/// - Example: Subclass and call `run { try await service.save() }`.
@MainActor
class TaskViewController: UIViewController {
    private var working = false
    private let spinner = UIActivityIndicatorView(style: .large)

    /// Run one asynchronous user action with a visible progress indicator.
    /// - Parameter operation: Main-actor operation which may throw.
    /// - Returns: Immediately; duplicate actions are ignored until completion.
    /// - Example: `run { try await Backend.call("startGame", data) }`.
    func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !working else { return }
        working = true
        view.endEditing(true)
        view.isUserInteractionEnabled = false
        spinner.center = view.center
        spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        view.addSubview(spinner)
        spinner.startAnimating()
        Task {
            defer {
                working = false
                view.isUserInteractionEnabled = true
                spinner.stopAnimating()
            }
            do { try await operation() } catch { showMessage(error.localizedDescription, title: "Could not complete the request") }
        }
    }

    /// Present a single actionable message without stacking competing alerts.
    /// - Parameters:
    ///   - message: User-facing explanation, never a credential.
    ///   - title: Short alert title.
    /// - Returns: Nothing.
    /// - Example: `showMessage("Check your connection.")`.
    func showMessage(_ message: String, title: String = "Robert Compass") {
        guard presentedViewController == nil, viewIfLoaded?.window != nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
