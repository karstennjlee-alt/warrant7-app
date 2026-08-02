# Open questions and standing decisions

Each of these is a place I picked a default. None is expensive to unwind.

## 1. Which design

Built to **`Warrant Mobile.dc.html`** — the primary file in the handoff bundle. The paper /
security-document world described in §8 of the build prompt matches
`Warrant Mobile v1 (paper).dc.html` instead, so §8's tokens, Archivo Expanded, Public Sans, the
notary stamp, the perforated tape and the guilloche are **not** in the app.

What replaced them:

| §8 (paper variant) | Built (primary design) |
|---|---|
| `paper #E9EDE6`, 2pt radius | `canvas #F4F5F2` / `surface #F7F8F6`, 14–18pt radius |
| Archivo Expanded + Public Sans | Instrument Sans |
| `seal #1D4B3C` / `stamp #B8332A` / `ochre #B57A21` / `pen #23349B` | `green #1B7A5A` / `red #D0402F` / `ochre #B8801E` / `blue #2B3BD6` |
| Notary stamp, guilloche, perforated tape | Rounded brand mark, plain cards |
| Two buttons, Deny left / Approve right | Slide-to-approve + one-tap Deny |

What carried over unchanged: JetBrains Mono for everything the system computed, light appearance
only, no SF Symbols for the brand mark, and every rule in §1.

Fonts are OFL and vendored in `Warrant/Resources/Fonts` with their licences.

## 2. Receipt schema and digest construction

`ChainVerifier` follows §5.4: `SHA-256(previous_hash ‖ canonical)`, signature over the resulting
32 digest bytes, `hash` and `signature` excluded from the body before hashing, first record's
`prev` is 64 zeros.

**Two wire-format choices are still guesses**, both isolated in `ChainFormat`:

- `ChainLinkage.rawBytes` — the previous hash is concatenated as 32 raw bytes, not as its 64
  ASCII hex characters. Both are implemented; one edit switches it.
- `SignaturePayload.digestBytes` — the signature covers the digest, not the canonical body.

If the gateway disagrees on either, honest evidence reads as forged. This needs the web
implementation before Phase 2 can really close.

## 3. T-01 golden vectors are provisional

`WarrantKit/Tests/WarrantKitTests/Fixtures/canonical-vectors.json` holds eight vectors I
authored from RFC 8785 directly, because the web repo is not on this machine. §10 says import
theirs and do not keep a second set. Replace that file wholesale and re-run — the test reads it
and asserts nothing else.

## 4. Failure-code ordering

§5.4 lists `HASH_MISMATCH` and `SIGNATURE_INVALID` separately, but T-03 wants an altered amount
to yield `SIGNATURE_INVALID`. Altering a field breaks both, so the verifier checks the signature
first against its own recomputation, and reserves `HASH_MISMATCH` for a stored hash that
disagrees with a recomputation whose signature still validates. Say if you meant it the other
way round.

## 5. Palette contrast — three tokens changed

§11 sets a 4.5:1 floor for text. Measured against the surfaces text is actually drawn on,
three of the design's tokens missed it, so they are **1–2 RGB units darker** than the file:

| token | design | built | was | now |
|---|---|---|---|---|
| `soft` | `#6B7480` | `#6A737F` | 4.44:1 | 4.51:1 |
| `red` | `#D0402F` | `#CE3F2E` | 4.42:1 | 4.51:1 |
| `mute` | `#9AA2AC` | `#899099` | 2.42:1 | 3.03:1 |

`soft` and `red` are body text throughout. `mute` carries ids, timestamps and key fragments —
mono, small, and still read by people, so it clears the 3:1 non-text floor rather than being
left at 2.4:1. The first two are invisible side by side; `mute` is a shade darker and visible
if you look for it.

`ochre #B8801E` is **unchanged** at 3.1:1. It is a fill — the envelope band, status dots, the
timer arc — and never carries prose.

`ContrastTests` measures all of this from the same hex literals the app renders, so a future
palette edit that drops below the floor fails the build. Say the word and I'll revert any of
the three to the design value.

## 6. Not built

- **Pairing screen.** The design's "Link this phone" generates a key pair on the handset. §1
  rule 1 says the device holds a session token and the org's public key, nothing else. Rather
  than pick one, sign-in is the magic link from §3. If you want the pairing flow, say which of
  the two wins.
- **Lock-screen mock.** The design's first screen is iOS's own lock screen; the real thing is
  the Live Activity plus the notification category, both built.

## 7. Tabs

The design has four (Queue, Limits, Receipts, Lab); §5.5 wants Verify as a standalone tab that
works signed out. Built five — Queue, Receipts, Verify, Limits, Lab — with Activity and Settings
behind the queue header, so no required screen was dropped and no tab is a rarely-used slot.

## 8. Git

`warrant-ios/` is **not** a git repository. §13 asks for a commit at every gate; the opening
instruction says ask before touching git history. Say the word and I'll `git init` and commit —
`.gitignore` is already written and already excludes `Config.xcconfig`, `*.p8` and the generated
`.xcodeproj`.
