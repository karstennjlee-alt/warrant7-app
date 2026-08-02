// RFC 8785 JSON Canonicalization Scheme.
//
// This must agree with WarrantKit's CanonicalJSON byte for byte. If the two disagree, honest
// evidence fails verification on the phone — the single worst failure this system has.
//
// JavaScript hands us two of the three rules:
//
//   1. Numbers. JCS adopts ECMAScript's Number::toString, which is what JSON.stringify emits,
//      including `-0` → `0` and `1e21` → `1e+21`.
//   2. Strings. JSON.stringify escapes `"`, `\` and the sub-0x20 controls using the short
//      forms where they exist and \u00xx otherwise, and passes non-ASCII through as UTF-8 —
//      which is what §3.2.2.2 asks for.
//
// The third rule it actively fights us on. JCS sorts members by UTF-16 code units, and
// `Object.keys(o).sort()` does produce that order — but you cannot then *store* that order in
// an object. JavaScript enumerates integer-like keys first, in ascending numeric order, before
// any string key. So `{"\r":…, "1":…}` re-emits with `"1"` in front no matter how carefully it
// was inserted, and one silently wrong digest is enough to make a real receipt look forged.
//
// The fix is to never round-trip through an object: emit the string directly, and use
// JSON.stringify only for scalars, where it is exactly right.

export function canonicalize(value) {
  if (value === null) return 'null';

  switch (typeof value) {
    case 'boolean':
      return value ? 'true' : 'false';

    case 'number':
      if (!Number.isFinite(value)) {
        throw new Error(`cannot canonicalize non-finite number: ${value}`);
      }
      return JSON.stringify(value);

    case 'string':
      return JSON.stringify(value);

    case 'object': {
      if (Array.isArray(value)) {
        // Array order is data, not presentation. It is preserved.
        return `[${value.map(canonicalize).join(',')}]`;
      }
      // .sort() compares by UTF-16 code units, which is what §3.2.3 requires.
      const members = Object.keys(value)
        .sort()
        .map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`);
      return `{${members.join(',')}}`;
    }

    default:
      throw new Error(`cannot canonicalize ${typeof value}`);
  }
}

export function canonicalBytes(value) {
  return Buffer.from(canonicalize(value), 'utf8');
}
