# Macro supply-chain contract v2

Macro packs are inspectable artifacts until their canonical content hash and
signature verify against a non-revoked key. The signing generator sorts JSON
keys and removes the mutable signature envelope before hashing. The verifier
performs the same calculation offline and fails closed for changed content,
unknown signatures, revoked keys, or unsigned packs.

The manifest binds source, build inputs, certificates, adapters, dependencies,
permissions, and provenance. Key rotation is represented by a new key id;
revocation input is a JSON object such as {"revoked_keys":["old-key"]}.
Only trusted reports may simulate or apply a pack.
