#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

/// Shared between the app and the widget extension, which is why it lives in WarrantKit.
///
/// `secondsRemaining` is deliberately absent from the content state: a stored countdown is a
/// countdown that drifts, and a Live Activity that lies about how long you have left is worse
/// than no Live Activity. Everything derives from `expiresAt`.
public struct ApprovalActivityAttributes: Sendable, Hashable, Codable {
    public struct ContentState: Sendable, Hashable, Codable {
        public var expiresAt: Date
        public var status: ApprovalStatus

        public init(expiresAt: Date, status: ApprovalStatus) {
            self.expiresAt = expiresAt
            self.status = status
        }

        public func secondsRemaining(at now: Date = Date()) -> TimeInterval {
            max(0, expiresAt.timeIntervalSince(now))
        }
    }

    public let approvalID: String
    public let orgName: String
    public let actionLine: String
    public let amountMinor: Int
    public let currency: String
    public let boundDigestShort: String

    public init(
        approvalID: String, orgName: String, actionLine: String,
        amountMinor: Int, currency: String, boundDigestShort: String
    ) {
        self.approvalID = approvalID
        self.orgName = orgName
        self.actionLine = actionLine
        self.amountMinor = amountMinor
        self.currency = currency
        self.boundDigestShort = boundDigestShort
    }

    public var amount: Money {
        Money(minorUnits: amountMinor, currencyCode: currency)
    }

    public init(approval: Approval, orgName: String) {
        self.init(
            approvalID: approval.id,
            orgName: orgName,
            actionLine: approval.actionLine,
            amountMinor: approval.amount.minorUnits,
            currency: approval.amount.currencyCode,
            boundDigestShort: approval.boundDigestShort
        )
    }
}

// ActivityKit exists on macOS as a symbol but every member is unavailable there, so the
// conformance has to be gated on the platform rather than on the import.
#if canImport(ActivityKit) && os(iOS)
extension ApprovalActivityAttributes: ActivityAttributes {}
#endif
