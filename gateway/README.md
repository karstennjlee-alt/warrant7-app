# Warrant gateway

The enforcement point. The agent has no provider credential and no way around this process — it
submits an exact action, deterministic policy answers `ALLOW`, `REVIEW` or `BLOCK`, and every
lifecycle event becomes a signed, hash-linked receipt.

Zero dependencies. Node 20+.

```bash
cd gateway
node server.mjs          # http://localhost:8787
```

Open `http://localhost:8787/` for the console that stands in for the agent and the operator.

## Why this exists

The brief describes "the existing Next.js gateway". There wasn't one — not deployed, not in any
repo — so this implements the same `/api/v1` contract in the smallest thing that could be
correct. Swapping in a real Next.js deployment is a change to `API_BASE_URL` and nothing else;
the phone has no opinion about what serves it.

## The part that matters

`lib/canonical.mjs` and `lib/chain.mjs` have to agree with `WarrantKit` **byte for byte**, or
honest receipts fail verification on the phone. Two things make that fragile, and both are
handled explicitly:

- **Member ordering.** RFC 8785 sorts by UTF-16 code units. JavaScript's `Array.sort()` does
  exactly that — but you cannot store the result in an object, because JS enumerates
  integer-like keys first regardless of insertion order. `{"\r":…,"1":…}` re-emits with `"1"`
  in front. The canonicalizer therefore builds the string directly and never round-trips
  through an object. This was a real bug, caught by the golden vectors.
- **Digest construction.** `SHA-256(previous_hash ‖ canonical(body))` with the previous hash as
  32 **raw bytes**, and the signature over those 32 digest bytes. That pairs with
  `ChainFormat(linkage: .rawBytes, signaturePayload: .digestBytes)` on the device.

`GatewayInteropTests` in the Swift package verifies a bundle this server produced. That test is
the contract between the two implementations — if it goes red, one side drifted.

## Auth

`/api/v1/*` needs `Authorization: Bearer <WARRANT_DEV_TOKEN>` (default `warrant-dev-token`).
That is a development stand-in for a Supabase session so the approval loop can be exercised
without an email round-trip. A real deployment verifies a Supabase JWT here instead; the phone
sends whatever token its `SessionProviding` hands it and is unaffected either way.

## Endpoints

Per §4 of the brief: `/api/v1/me`, `/approvals`, `/approvals/:id`, `/approvals/:id/approve`,
`/approvals/:id/deny`, `/actions`, `/receipts`, `/receipts/export`, `/policy`, `/devices`,
`/devices/:id`, plus `/api/demo/reset`.

Console-only helpers: `POST /api/agent/refund` (the agent tries something),
`POST /api/lab/tamper` (edit a stored record in place, without re-signing),
`GET /api/lab/selfcheck`.

## Fail-closed behaviour

| attempt | answer |
|---|---|
| decision on an expired approval | `APPROVAL_EXPIRED` |
| second decision, new idempotency key | `ALREADY_CONSUMED` |
| same idempotency key again | the recorded decision, replayed — no second receipt |
| `bound_digest` that doesn't match | `DIGEST_MISMATCH` |
| missing or wrong bearer token | `401` |

## The signing key

Generated on first run into `.data/signing-key.pem`, gitignored, mode 0600. It is the only
secret here, and it never goes near a device — the phone holds the public half and can check a
signature without being able to make one. That asymmetry is the product.
