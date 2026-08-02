import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { canonicalBytes } from './canonical.mjs';

export const GENESIS = '0'.repeat(64);

/**
 * The hash-linked, signed ledger.
 *
 * Digest is SHA-256 over the previous digest's 32 raw bytes followed by the canonical bytes of
 * the record body, and the signature covers those 32 digest bytes. That matches
 * `ChainFormat(linkage: .rawBytes, signaturePayload: .digestBytes)` on the phone — the pairing
 * the Swift side defaults to. Change one side and you must change the other.
 */
export class Ledger {
  #privateKey;
  #publicKey;

  constructor(dataDir) {
    const keyPath = path.join(dataDir, 'signing-key.pem');
    if (fs.existsSync(keyPath)) {
      this.#privateKey = crypto.createPrivateKey(fs.readFileSync(keyPath, 'utf8'));
    } else {
      // Generated once, kept out of git. This is the organization's signing key: it lives on
      // the server and never goes near a device. The phone holds only the public half.
      const { privateKey } = crypto.generateKeyPairSync('ed25519');
      fs.mkdirSync(dataDir, { recursive: true });
      fs.writeFileSync(
        keyPath,
        privateKey.export({ format: 'pem', type: 'pkcs8' }),
        { mode: 0o600 }
      );
      this.#privateKey = privateKey;
    }
    this.#publicKey = crypto.createPublicKey(this.#privateKey);
  }

  /** Raw 32 bytes, base64 — what CryptoKit's Curve25519.Signing.PublicKey wants. */
  get publicKeyBase64() {
    return this.#publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
  }

  /** SHA-256(previous ‖ canonical(body)) */
  digest(body, previousHex) {
    const previous = Buffer.from(previousHex, 'hex');
    const hash = crypto.createHash('sha256');
    hash.update(previous);
    hash.update(canonicalBytes(body));
    return hash.digest();
  }

  /** Seal a body into a record: link it, hash it, then sign the hash. */
  seal(body, previousHex) {
    const linked = { ...body, prev: previousHex };
    const digest = this.digest(linked, previousHex);
    const signature = crypto.sign(null, digest, this.#privateKey);
    return { ...linked, hash: digest.toString('hex'), signature: signature.toString('base64') };
  }

  /**
   * The same check the phone performs, kept here so the server can prove its own chain before
   * handing it out. It is not a substitute for the device doing it — a server vouching for
   * itself is exactly what the phone exists not to trust.
   */
  verify(records) {
    let expected = GENESIS;
    for (const [index, record] of records.entries()) {
      const { hash, signature, ...body } = record;
      if (body.prev !== expected) return { ok: false, index, reason: 'CHAIN_BROKEN' };

      const recomputed = this.digest(body, body.prev);
      if (recomputed.toString('hex') !== hash) return { ok: false, index, reason: 'HASH_MISMATCH' };
      if (!crypto.verify(null, recomputed, this.#publicKey, Buffer.from(signature, 'base64'))) {
        return { ok: false, index, reason: 'SIGNATURE_INVALID' };
      }
      expected = hash;
    }
    return { ok: true, count: records.length };
  }
}
