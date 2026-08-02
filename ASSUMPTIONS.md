# Open questions and standing assumptions

Written while building the crypto core. Each of these is a place where I picked a default that
is easy to change once the real answer arrives. Nothing here is load-bearing on a guess that
would be expensive to unwind.

## 1. Receipt schema

The verifier assumes each record is a JSON object where:

- `digest` and `signature` are **envelope**, excluded before hashing (`ChainVerifier.envelopeKeys`)
- everything else, including `prev` and `seq`, is **body** and is hashed
- `digest` = SHA-256 over the RFC 8785 canonical form of the body, lowercase hex
- `signature` = Ed25519 over the **raw 32 digest bytes**, base64
  (`ChainVerifier.signaturePayload`; the alternative, signing the canonical body bytes, is
  already implemented as `.canonicalBody`)
- the first record's `prev` is 64 zeros

Body field names follow the design prototype: `actor`, `amount_minor`, `currency`, `event`,
`prev`, `recipient`, `resource`, `seq`, `ts`.

## 2. Numbers

RFC 8785 canonicalizes numbers through IEEE-754 binary64, so `JSONValue` holds `Double`.
Integers above 2^53 cannot round-trip. `amount_minor` is nowhere near that, but if the gateway
ever emits a large integer id inside a hashed body, this needs revisiting.

## 3. Approve gesture

The design shows slide-to-approve; the build rules require biometric authentication on approve
and none on deny. These compose rather than conflict: the slide completes, then Face ID runs,
then the decision is submitted. Deny stays one tap. Assumed unless told otherwise.

## 4. Device key material

The build rules say the device holds a session token and the org's **public** key, never a
signing private key. The pairing screen in the design says "the key pair is generated here; the
private half never leaves the handset."

Read as compatible: the device may hold **its own approver key** in the Secure Enclave for
countersigning a decision, and never holds the **organization's ledger signing key**. The
verifier only ever needs the org public key. Confirm before any pairing code is written —
it changes what `POST /approvals/{id}/decision` carries.

## 5. Unit test location

WarrantKit's tests live in the package (`swift test` from `WarrantKit/`), not in an Xcode
`WarrantTests` target, so they cannot accidentally import the app. `WarrantUITests` remains an
Xcode target. Say the word if the Xcode-target layout is required instead.

## 6. Not yet validated

`project.yml` is written but **not generated** — XcodeGen is not installed on this machine
(`brew install xcodegen`). It has not been run, so treat it as a draft until it generates.
