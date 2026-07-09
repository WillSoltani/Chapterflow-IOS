/// Availability state for the on-device AI features lane.
///
/// Mapped from `SystemLanguageModel.Availability` on iOS 26+, or derived
/// from the OS version / feature flag on older systems.
public enum OnDeviceAIAvailability: Equatable, Sendable {
    /// The on-device model is loaded and ready to use.
    case available
    /// Running on iOS < 26 — FoundationModels is not in the SDK.
    case unavailableOSVersion
    /// The device hardware does not support Apple Intelligence.
    case unavailableDeviceNotEligible
    /// Apple Intelligence is supported but not enabled in Settings.
    case unavailableNotEnabled
    /// The model is still downloading or the system is busy.
    case unavailableModelNotReady
    /// The feature flag is explicitly turned off.
    case unavailableFeatureDisabled
    /// An unknown unavailability reason reported by the system.
    case unavailableUnknown

    /// Convenience: true only for `.available`.
    public var isAvailable: Bool { self == .available }

    /// A human-readable hint used in Settings / debug UI.
    public var debugDescription: String {
        switch self {
        case .available: return "Available"
        case .unavailableOSVersion: return "Requires iOS 26+"
        case .unavailableDeviceNotEligible: return "Device not eligible for Apple Intelligence"
        case .unavailableNotEnabled: return "Apple Intelligence not enabled"
        case .unavailableModelNotReady: return "Model not ready (still downloading)"
        case .unavailableFeatureDisabled: return "Feature disabled via flag"
        case .unavailableUnknown: return "Unavailable (unknown reason)"
        }
    }
}
