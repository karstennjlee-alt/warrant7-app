import Foundation

/// Every user-facing occurrence of the product name goes through here.
///
/// "Warrant" is an existing authorization brand that WorkOS acquired, so this is a working
/// title. Renaming is one edit in this file plus `BUNDLE_ID` in `Config.xcconfig` — nothing
/// else in the codebase spells the name out.
public enum Brand {
    public static let name = "Warrant"
    public static let scheme = "warrant"

    /// The honest claim, used verbatim in Settings → About and nowhere paraphrased.
    ///
    /// Claims discipline: this product is **tamper evident**. It is not tamper proof, not
    /// unhackable, not military grade, and it cannot prove what an agent did *not* do.
    public static let claimLine = """
    The receipts can be edited, but they cannot be secretly edited without verification failing.
    """

    public static let tagline = "\(name) gives AI agents narrowly scoped permission slips for exactly one action, then creates signed receipts that cannot be secretly altered."
}
