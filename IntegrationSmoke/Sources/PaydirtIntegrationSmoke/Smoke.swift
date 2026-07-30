import Paydirt

/// Keeps the integration fixture as a real module even before the public
/// adapter templates are copied into it by the smoke-test script.
enum PaydirtIntegrationSmoke {
    static let sdkType = Paydirt.self
}
