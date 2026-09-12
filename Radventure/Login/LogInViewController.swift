import UIKit
import FirebaseAuth

/// Email-based authentication, registration, verification, and recovery.
/// - Note: No school tenant or Microsoft account is required.
/// - Example: Present from the scene's unauthenticated route.
@MainActor
final class LogInViewController: TaskViewController {
    private let email = UITextField()
    private let password = UITextField()
    private let name = UITextField()
    private var registration = false

    /// Build the appropriate sign-in or verification form.
    /// - Returns: Nothing.
    /// - Example: Called by UIKit when the view loads.
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Robert Compass"
        if let user = Auth.auth().currentUser, !user.isEmailVerified { verificationForm(user) }
        else { signInForm() }
    }

    private func field(_ field: UITextField, title: String, content: UITextContentType) {
        field.placeholder = title
        field.accessibilityIdentifier = title
        field.borderStyle = .roundedRect
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textContentType = content
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        field.autocorrectionType = .no
    }

    private func signInForm() {
        field(email, title: "Email", content: .emailAddress)
        email.keyboardType = .emailAddress
        email.autocapitalizationType = .none
        field(password, title: "Password", content: .password)
        password.isSecureTextEntry = true
        field(name, title: "Display name", content: .name)
        name.isHidden = true
        let submit = AppUI.button("Sign in", action: UIAction { [weak self] _ in self?.submit() })
        let toggle = AppUI.button("Create an account", action: UIAction { [weak self, weak submit] action in
            guard let self else { return }
            registration.toggle()
            name.isHidden = !registration
            password.textContentType = registration ? .newPassword : .password
            submit?.configuration?.title = registration ? "Create account" : "Sign in"
            (action.sender as? UIButton)?.configuration?.title = registration ? "I already have an account" : "Create an account"
        })
        let reset = AppUI.button("Forgot password", action: UIAction { [weak self] _ in self?.resetPassword() })
        let logo = UIImageView(image: UIImage(named: "AppLogo"))
        logo.contentMode = .scaleAspectFit
        logo.backgroundColor = UIColor(named: "AppColor3")
        logo.layer.cornerRadius = 16
        logo.clipsToBounds = true
        logo.heightAnchor.constraint(equalToConstant: 110).isActive = true
        AppUI.form([logo, AppUI.label("Explore together", style: .largeTitle),
                    AppUI.label("Visit checkpoints, answer questions, and follow your team's progress."), name, email, password, submit, toggle, reset], in: self)
    }

    private func submit() {
        let address = email.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = password.text ?? ""
        guard address.contains("@"), !secret.isEmpty else { showMessage("Enter your email and password."); return }
        let displayName = name.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if registration && (displayName.isEmpty || displayName.count > 60 || secret.count < 12) {
            showMessage("Enter a display name up to 60 characters and a password of at least 12 characters.")
            return
        }
        run { [self] in
            if registration {
                let result = try await Auth.auth().createUser(withEmail: address, password: secret)
                let change = result.user.createProfileChangeRequest()
                change.displayName = displayName
                try await change.commitChanges()
                try await result.user.sendEmailVerification()
            } else {
                _ = try await Auth.auth().signIn(withEmail: address, password: secret)
            }
            password.text = nil
            NotificationCenter.default.post(name: .accountDidChange, object: nil)
        }
    }

    private func resetPassword() {
        let address = email.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard address.contains("@") else { showMessage("Enter your email above first."); return }
        run { [self] in
            try await Auth.auth().sendPasswordReset(withEmail: address)
            showMessage("If an account exists for that address, a password reset email will arrive shortly.")
        }
    }

    private func verificationForm(_ user: User) {
        let refresh = AppUI.button("I verified my email", action: UIAction { [weak self] _ in
            self?.run {
                try await user.reload()
                _ = try await user.getIDTokenResult(forcingRefresh: true)
                if user.isEmailVerified { NotificationCenter.default.post(name: .accountDidChange, object: nil) }
                else { self?.showMessage("Open the verification link in your email, then try again.") }
            }
        })
        let resend = AppUI.button("Resend verification email", action: UIAction { [weak self] _ in
            self?.run { try await user.sendEmailVerification(); self?.showMessage("Verification email sent.") }
        })
        let signOut = AppUI.button("Use another account", action: UIAction { [weak self] _ in
            self?.run { try Auth.auth().signOut() }
        })
        AppUI.form([AppUI.label("Check your email", style: .largeTitle),
                    AppUI.label("Verify \(user.email ?? "your address") to join courses and teams."), refresh, resend, signOut], in: self)
    }
}
