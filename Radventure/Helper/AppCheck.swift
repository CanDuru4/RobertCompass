import DeviceCheck
import FirebaseAppCheck
import FirebaseCore

/// Attests production requests without embedding administrator secrets in the app.
/// - Note: DeviceCheck supports devices where App Attest is unavailable.
/// - Example: Register before Firebase configuration.
final class MyAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    /// Select the strongest available production provider.
    /// - Parameter app: Configured Firebase app.
    /// - Returns: App Attest or DeviceCheck provider.
    /// - Example: Called by Firebase when requesting an App Check token.
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if DCAppAttestService.shared.isSupported { return AppAttestProvider(app: app) }
        return DeviceCheckProvider(app: app)
    }
}
