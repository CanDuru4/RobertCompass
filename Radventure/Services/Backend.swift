import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck

/// Owns Firebase configuration and prevents accidental access to the retired project.
/// - Note: Local emulators are available only in Debug with `--emulator`.
/// - Example: `Backend.configure()` at application launch.
@MainActor
enum Backend {
    static private(set) var setupError: String?
    static private(set) var isEmulator = false
    static var db: Firestore { Firestore.firestore() }
    static var serverOffset: TimeInterval = 0
    static var now: Date { Date().addingTimeInterval(serverOffset) }

    /// Initialize the selected backend or show a setup screen without crashing.
    /// - Returns: Nothing; `setupError` explains a missing configuration.
    /// - Note: Legacy `GoogleService-Info.plist` and `Keys.plist` are never loaded.
    /// - Example: `Backend.configure()`.
    static func configure() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--emulator") {
            isEmulator = true
            let options = FirebaseOptions(googleAppID: "1:123456789:ios:0123456789abcdef", gcmSenderID: "123456789")
            options.projectID = "demo-robert-compass"
            options.apiKey = "demo-emulator-api-key"
            FirebaseApp.configure(options: options)
            Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            let settings = db.settings
            settings.host = "127.0.0.1:8080"
            settings.isSSLEnabled = false
            settings.cacheSettings = MemoryCacheSettings()
            db.settings = settings
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--unconfigured") {
            setupError = "The app is ready for a new Firebase project. Follow the project README to connect it."
            return
        }
        #endif
        guard let file = Bundle.main.path(forResource: "FirebaseConfig", ofType: "plist", inDirectory: "Configuration"),
              let options = FirebaseOptions(contentsOfFile: file),
              let project = options.projectID, !project.isEmpty, project != "radventure-robert",
              options.bundleID == Bundle.main.bundleIdentifier else {
            setupError = "Firebase setup is incomplete. Add the new project's FirebaseConfig.plist as described in the README."
            return
        }
        AppCheck.setAppCheckProviderFactory(MyAppCheckProviderFactory())
        FirebaseApp.configure(options: options)
    }

    /// Run a rules-validated Firebase operation and update the display clock when available.
    /// - Parameters:
    ///   - name: Supported game or account operation.
    ///   - data: User input for that operation; database rules validate it.
    /// - Returns: The operation response dictionary.
    /// - Throws: Firebase errors for network failures or rejected operations.
    /// - Example: `try await Backend.call("refreshSession", ["sessionId": id])`.
    @discardableResult
    static func call(_ name: String, _ data: [String: Any] = [:]) async throws -> [String: Any] {
        guard let user = Auth.auth().currentUser else { throw GameWriteError("Sign in to continue.") }
        let service = FirebaseGameService(db: db, user: user, offset: serverOffset)
        let response = try await service.call(name, data: data)
        if let millis = response["serverTime"] as? NSNumber {
            serverOffset = millis.doubleValue / 1000 - Date().timeIntervalSince1970
        }
        return response
    }
}
