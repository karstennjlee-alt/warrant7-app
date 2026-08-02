import Testing
import CryptoKit
import Foundation
@testable import WarrantKit

@Suite("T-13 · Amount formatting")
struct MoneyTests {

    @Test("T-13 · Minor units render correctly across locales")
    func formattingAcrossLocales() {
        let amount = Money(minorUnits: 240_000, currencyCode: "USD")

        #expect(amount.formatted(locale: Locale(identifier: "en_US")) == "$2,400.00")
        // Grouping and symbol placement change; the number does not.
        let german = amount.formatted(locale: Locale(identifier: "de_DE"))
        #expect(german.contains("2.400,00"))
        let french = amount.formatted(locale: Locale(identifier: "fr_FR"))
        #expect(french.contains("2") && french.contains("400"))
    }

    @Test("T-13 · JPY has no decimal part, so 240000 minor units is ¥240,000")
    func yenHasNoFraction() {
        let yen = Money(minorUnits: 240_000, currencyCode: "JPY")

        #expect(yen.fractionDigits == 0)
        #expect(yen.decimalAmount == 240_000)
        let formatted = yen.formatted(locale: Locale(identifier: "en_US"))
        #expect(formatted.contains("240,000"))
        #expect(!formatted.contains(".00"), "treating JPY as hundredths would be off by 100×")
    }

    @Test("T-13 · Three-decimal currencies are not rounded to two")
    func dinarHasThreeDigits() {
        let dinar = Money(minorUnits: 2_400_500, currencyCode: "KWD")
        #expect(dinar.fractionDigits == 3)
        #expect(dinar.decimalAmount == Decimal(string: "2400.5"))
    }

    @Test("T-13 · Zero and negative amounts format without surprises")
    func edgeAmounts() {
        #expect(Money(minorUnits: 0).formatted(locale: Locale(identifier: "en_US")) == "$0.00")
        #expect(Money(minorUnits: 1).formatted(locale: Locale(identifier: "en_US")) == "$0.01")
        #expect(Money(minorUnits: -5_000).formatted(locale: Locale(identifier: "en_US")).contains("50.00"))
    }

    @Test("Amounts are spelled out for VoiceOver")
    func spelledOut() {
        let spoken = Money(minorUnits: 240_000).spelledOut(locale: Locale(identifier: "en_US"))
        #expect(spoken.contains("two thousand four hundred"))
    }

    @Test("Comparison stays in minor units")
    func comparison() {
        #expect(Money(minorUnits: 50_000) < Money(minorUnits: 240_000))
        #expect(Money(minorUnits: 240_000) == Money(minorUnits: 240_000))
    }
}

@Suite("T-14 · Keychain")
struct KeychainTests {

    // Runs on the simulator and on device. A `swift test` process on macOS has no application
    // keychain to write to, and making this pass there would mean testing something other than
    // what ships.
    #if os(iOS)
    @Test("T-14 · A token is stored, read back, and cleared with nothing left behind")
    func roundTripAndClear() throws {
        let store = KeychainStore(service: "test.\(UUID().uuidString)")
        let account = KeychainStore.Account.sessionToken

        #expect(try store.string(for: account) == nil)

        try store.setString("session-token-value", for: account)
        #expect(try store.string(for: account) == "session-token-value")

        // Overwriting must update in place rather than leaving a second item behind.
        try store.setString("session-token-value-2", for: account)
        #expect(try store.string(for: account) == "session-token-value-2")

        try store.removeItem(for: account)
        #expect(try store.data(for: account) == nil)

        // Removing what is already gone is not an error — sign out must be idempotent.
        #expect(throws: Never.self) { try store.removeItem(for: account) }
    }

    @Test("T-14 · The public key store rejects anything that is not an Ed25519 key")
    func publicKeyValidation() throws {
        let store = PublicKeyStore(keychain: KeychainStore(service: "test.\(UUID().uuidString)"))

        #expect(throws: PublicKeyStore.Failure.notAnEd25519Key) {
            try store.store(base64: Data("too short".utf8).base64EncodedString())
        }

        let real = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        try store.store(base64: real)
        #expect(try store.base64() == real)
        #expect(try store.key() != nil)

        try store.clear()
        #expect(try store.base64() == nil)
    }
    #endif

    @Test("A public key is grouped so two people can read it to each other")
    func readableKey() {
        #expect(PublicKeyStore.readable("abcdefgh") == "abcd efgh")
    }
}

@Suite("Offline behaviour")
struct OfflineCacheTests {

    @Test("The offline strip says how stale it is, in mono, without an error tone")
    func offlineStrip() {
        let cache = OfflineCache()
        cache.clear()
        #expect(cache.offlineStrip() == "OFFLINE · never synced")

        cache.markSynced(at: Date().addingTimeInterval(-14))
        #expect(cache.offlineStrip().hasPrefix("OFFLINE · last synced 14s ago"))

        cache.markSynced(at: Date().addingTimeInterval(-3 * 60))
        #expect(cache.offlineStrip().contains("3m ago"))
        cache.clear()
    }

    @Test("Approvals survive a round trip through the cache")
    func cacheRoundTrip() {
        let cache = OfflineCache()
        cache.clear()
        let approvals = [Fixtures.approval()]

        cache.store(approvals, for: .approvals)
        let loaded = cache.load([Approval].self, for: .approvals)

        #expect(loaded?.count == 1)
        #expect(loaded?.first?.amount.minorUnits == 240_000)
        cache.clear()
    }
}

@Suite("Claims discipline")
struct CopyTests {

    /// §0 is a promise about what this product says, and a promise that is not checked is a
    /// preference. These are the words that would make the claim dishonest.
    @Test("No forbidden claim appears in shipped copy")
    func forbiddenClaims() {
        let forbidden = [
            "tamper proof", "tamper-proof", "unhackable", "military grade", "military-grade",
            "100% secure", "nobody can edit"
        ]
        let shippedCopy = [
            Brand.claimLine, Brand.tagline,
            VerificationCode.ok.message, VerificationCode.signatureInvalid.message,
            VerificationCode.hashMismatch.message, VerificationCode.chainBroken.message,
            VerificationCode.sequenceGap.message, VerificationCode.keyMismatch.message,
            VerificationCode.untrusted(dependsOn: 7).message,
            WarrantError.network.message, WarrantError.digestMismatch.message,
            WarrantError.approvalExpired.message, WarrantError.alreadyConsumed.message
        ].map { $0.lowercased() }

        for phrase in forbidden {
            for copy in shippedCopy {
                #expect(!copy.contains(phrase), "'\(phrase)' must never ship")
            }
        }
    }

    @Test("The claim line says the honest thing, exactly")
    func claimLine() {
        #expect(Brand.claimLine.contains("cannot be secretly edited without verification failing"))
    }
}
