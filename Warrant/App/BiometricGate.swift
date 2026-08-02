import Foundation
import LocalAuthentication
import WarrantKit

/// The last honest checkpoint.
///
/// Approve requires biometrics; deny does not. That asymmetry is the point: the safe action
/// must always be the fast one, and the risky one must always cost a deliberate confirmation
/// from the person the phone belongs to.
///
/// The reason string carries the real amount and the real recipient. If the system prompt says
/// something vaguer than the card did, then the card is no longer what is being approved.
public struct BiometricGate: Sendable {

    public init() {}

    public enum Outcome: Sendable {
        case authenticated
        /// The person deliberately backed out. The card returns unchanged; this is not an error.
        case cancelled
        case failed(WarrantError)
    }

    public func authenticate(reason: String) async -> Outcome {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        // `.deviceOwnerAuthentication` rather than `...WithBiometrics`, so a failed or
        // unavailable Face ID falls back to the device passcode instead of dead-ending.
        let policy = LAPolicy.deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &error) else {
            return .failed(.biometricsUnavailable)
        }

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            return success ? .authenticated : .failed(.biometricsFailed)
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
                return .failed(.biometricsUnavailable)
            default:
                return .failed(.biometricsFailed)
            }
        } catch {
            return .failed(.biometricsFailed)
        }
    }

    /// "Approve a $2,400.00 refund to Northwind"
    public static func reason(for approval: Approval) -> String {
        "Approve \(approval.actionLine.prefix(1).lowercased() + approval.actionLine.dropFirst())"
    }
}
