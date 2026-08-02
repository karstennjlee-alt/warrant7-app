import Foundation

/// Everything that can go wrong, already translated.
///
/// §4 and §9.5: a person never sees a reason code, an HTTP status, a UUID, a stack trace, or
/// the word "Error:". They see a sentence that tells them what happened to their money and
/// what to do about it. Raw codes stay on this side of the boundary.
public enum WarrantError: Error, Sendable, Hashable {

    // Server reason codes
    case approvalExpired
    case alreadyConsumed
    case digestMismatch
    case humanDenied

    // Transport and session
    case network
    case unauthorized
    case forbidden
    case notFound
    case server
    case decoding

    /// The app has no gateway address configured, so no call was attempted.
    case notConfigured

    /// Local guard: the countdown reached zero before the tap landed. No request was sent.
    case locallyExpired

    case biometricsFailed
    case biometricsUnavailable

    public var message: String {
        switch self {
        case .approvalExpired:
            "This request expired. The agent will need to submit a new one."
        case .alreadyConsumed:
            "Already decided. Someone on your team answered this first."
        case .digestMismatch:
            "The request changed after it was sent to you. Nothing was executed."
        case .humanDenied:
            "Denied. The action was never forwarded."
        case .network:
            // The most important sentence in the app. An approver unsure whether their tap
            // landed will tap again, so say plainly that nothing happened.
            "Can't reach \(Brand.name). Nothing was approved. Retrying."
        case .unauthorized:
            "Your session ended. Sign in again to keep deciding."
        case .forbidden:
            "Your role doesn't allow this. Ask an owner of this organization."
        case .notFound:
            "That request isn't here anymore."
        case .server:
            "\(Brand.name) couldn't complete that. Nothing was approved."
        case .decoding:
            "\(Brand.name) couldn't read the response. Nothing was approved."
        case .notConfigured:
            "No gateway is configured yet, so \(Brand.name) is running on demo data."
        case .locallyExpired:
            "This request expired while you were reading it. Nothing was sent."
        case .biometricsFailed:
            "Not approved — \(Brand.name) couldn't confirm it was you."
        case .biometricsUnavailable:
            "Set up Face ID or a passcode on this device to approve. Denying still works."
        }
    }

    /// Whether the app should keep trying by itself.
    public var isRetryable: Bool {
        self == .network || self == .server
    }

    /// Map a gateway reason code. Unknown codes become a generic server failure rather than
    /// being echoed at a person.
    public static func from(reasonCode: String) -> WarrantError {
        switch reasonCode.uppercased() {
        case "APPROVAL_EXPIRED": .approvalExpired
        case "ALREADY_CONSUMED": .alreadyConsumed
        case "DIGEST_MISMATCH": .digestMismatch
        case "HUMAN_DENIED": .humanDenied
        default: .server
        }
    }

    public static func from(statusCode: Int) -> WarrantError {
        switch statusCode {
        case 401: .unauthorized
        case 403: .forbidden
        case 404: .notFound
        default: .server
        }
    }
}
