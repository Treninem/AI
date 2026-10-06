# AuroraFox future distribution foundation

This standalone reference package prepares V1.6+ delivery. Nothing imports it from
V1.5 Core, updater, installer, API startup or normal chat. It does not bump versions,
change release keys, sign a production release, change bucket policy or delete objects.

## Responsibility and trust

S3 holds opaque immutable package bytes, identity reservations and signed manifests.
Database/control plane holds principals, entitlements, active/stable/rollback references,
manifest routing, delivery state and privacy-safe capability metadata. Existing SQLite
is sufficient for this preparation; no DB migration is introduced.

API authenticates and supplies a small signed manifest and bounded download authorization.
Clients pin distribution public keys independently of supplied manifests. A manifest key_id
selects an already trusted key; it cannot install a new trust anchor. Ed25519 is this
foundation's signature contract, **not** a replacement for existing V1.5 release signing.
Key rollout/revocation and public API integration need a separately accepted V1.6 contract.
Private keys live outside the repository and never enter downloaded packages.

Clients use AuthorizedHTTPProvider with an in-memory per-chunk URL resolver. It can renew
short-lived authorization after interruption without persisting URLs. Redirects are refused;
production uses HTTPS and checks HTTP206/Content-Range/length. No permanent S3 key ships.
The S3 admin adapter uses boto3 lazily. SDK exceptions and URLs never appear in public errors.
The local provider writes real files and is suitable for deterministic offline acceptance.

## Layout and immutable identity

Namespace roots:

- aurorafox/bootstrap/manifests
- aurorafox/models/core/{lite,full}
- aurorafox/knowledge/{seed,standard,full,domain}
- aurorafox/capabilities/{vision,image,video,stt,tts,embeddings}
- aurorafox/experience/shared
- aurorafox/releases/{windows,android}
- aurorafox/metadata/{identities,checksums,signatures}

S3 prefixes are logical; no fake directory marker objects are necessary.
Payload path: root/type/profile/artifact_id/version/sha256/filename.
Identity: artifact_id + version, globally unique regardless of profile/provider/channel.
Changing bytes requires a new version; even a new hash path cannot bypass the identity record.
Identity JSON is reserved atomically with If-None-Match:* before payload upload. Reservation
is not upload success. A failed upload may leave a reservation; retry of identical identity
is safe. Conflicting identity fails without overwrite. Existing unknown objects are untouched.
LocalProvider implements equivalent atomic create-if-absent with hard links.

S3 adapter refuses unsupported conditional writes; it never degrades to HEAD-then-unconditional
PUT. Exact provider support must be proven before production use. Uploads <=5,000,000,000 bytes
use a streaming single conditional PUT, enough for the pinned 429 MB Knowledge archive.
Larger future packages must be split into independent immutable dependency packages;
no unsafe unconditioned SDK multipart completion fallback is provided. SDK transfer failures
are per-operation failures, not a total deadline for the entire download.

Uploader verifies signed metadata and local complete SHA, claims identity, performs conditional
PUT, then re-reads every range, checks every part and complete SHA/size. ETag and metadata SHA
are insufficient. Only then is the signed manifest published and re-read exactly. Returned
UPLOADED_VERIFIED is evidence for this execution, not an unverified remote boolean.

## Manifest and capabilities

manifest.schema.json is strict Draft2020-12 JSON Schema with closed objects. The lightweight
reference validator implements precisely its small vocabulary and rejects unknown keywords.
Tests cross-check the schema with the standard jsonschema validator. Semantic validation adds
exact ordered/nonoverlapping chunk coverage, object identity, compatibility ordering, required
vs optional exclusivity, safe Windows filenames and public provenance URL restrictions.
JSON duplicate keys and nonfinite numbers are rejected.

Signed canonical payload is ASCII JSON (sort_keys, compact separators, escaped Unicode,
no nonfinite numbers), omitting only signature. The signature covers status, resource budgets,
provider identity, dependencies, rollback references, complete hash and all chunk hashes.
This is an explicitly versioned serialization, not a claim of RFC8785 equivalence.
All byte counts are integers <=2^53-1 for portable JSON consumers. RAM/VRAM/disk are bytes.
part_size <=16MiB bounds memory; default4MiB. Manifest limits bound metadata cardinality.

Capability names (core.chat, vision.analyze, image.generate, image.edit, video.generate,
stt.transcribe, tts.speak, embedding.generate) remain independent of provider_id/version.
Optional provider absence only disables that capability. Downloaded payload is data; this
reference never unpacks/executes arbitrary content or imports private raw Experience globally.
Only curated privacy-safe shared Experience/Skills qualify for later publication.

## Production Knowledge reservation

knowledge.production.pending.json records the existing production contract exactly:
429588529 packed bytes; SHA256bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614;
1924345221 genuine content bytes;60shards; source and CC BY-SA4.0 attribution preserved.
No archive or chunk hashes are fabricated. Status EXTERNAL_ARTIFACT_PENDING permits metadata
validation but prohibits upload/download/signing. RAM0 here means no new delivery-layer RAM
minimum is asserted; the production importer/hardware matrix remains separately authoritative.
Before converting to READY, obtain actual bytes, verify pinned full hash/size, calculate chunks,
review V1.6 resource/profile compatibility and sign using an externally controlled key.

## Download, staging, activation and recovery

A private single-writer workspace is OS-locked; process exit releases its lock.
No symlinks are accepted. Manifest authenticity is checked before data requests.
Completed parts are fsynced and atomically renamed. Restart hashes every cached part;
corrupt/missing parts are downloaded again, never trusted from a progress bitmap.
Partial assembly is never returned as ready. Ordered parts and full hash are verified before
artifact.verified is published. Cancellation preserves complete parts, reports a safe code,
and does not activate partial bytes. A request has an operational timeout; no overall deadline
discards already verified progress. Resume is explicit retry, avoiding endless background loops.
Progress callback receives verified received bytes and total, including resumed bytes.

Disk preflight reserves remaining parts + assembled artifact + manifest minimum_disk.
For Knowledge minimum_disk includes packed copy plus expanded file bytes. This conservative
reservation keeps install/rollout capacity distinct from RAM and S3 capacity. Concurrent external
disk consumption can still cause an I/O failure; it cannot activate incomplete bytes.

ArtifactStaging copies verified bytes onto the activation filesystem, verifies again, fsyncs,
then installs an immutable versions/hash file. Active state is one atomically replaced JSON
pointer. Before switching, a durable activation transaction records old active/known-good state.
Health is supplied by the future platform integrator and must return literal True. Failure
restores the old pointer; old version bytes are retained. Restart recovers an incomplete
transaction conservatively. A durable committed marker prevents late cleanup/crash from rolling
back a completed health check. Normal consumers must use the pointer/recovery contract and
verify selected local bytes; no V1.5 consumer has been switched to it.

This is reference package activation, not actual Windows/Android model extraction/loading
acceptance. Future platform adapters need their own installed-device health tests, sandboxed
package extraction where applicable, app lifecycle/locking integration and launch recovery.

## Future bootstrap

Pure bootstrap.plan consumes authenticated manifests, hardware profile and product version.
Profiles may be mapped by artifact type (model=lite, knowledge=seed, capability=vision),
or a catalog may use a uniform profile alias. It filters platform/architecture/RAM/VRAM/version,
selects required profile and requested optional
capabilities, checks dependencies and topologically orders delivery. Missing/cyclic dependencies
or absent core.chat + knowledge.retrieve baseline fail before normal launch. Optional incompatible
providers are omitted. Disk reserve covers all selected packages. Lite/Full and Seed/Standard/Full
catalog choices remain control-plane data, not hardcoded model names.

Accepted first-install options remain bundled Lite+Seed, or verified install-time baseline before
normal usable launch. Full offline installer remains possible. Post-download local asset access
and activation require no S3/API/Internet. Reference tests prove this asset-level invariant;
actual offline Chat/Core/Memory/Knowledge remains the existing product/device acceptance suite.

## Capacity and retention

Default capacity10,000,000,000 bytes (decimal10GB); provider quota units must be confirmed on
real inspection. Capacity counts all current listed bucket objects, including unmanaged keys,
identity/manifest metadata. Versions/noncurrent objects and unfinished multipart usage may not
appear in list_objects_v2: inspect provider billing/version inventory separately before relying
on reported free capacity. Report never claims an uninspected bucket's used/free bytes.

Review threshold75%, configurable only70..75%. Review only informs; no purchase/deletion occurs.
Metadata flags protect stable, previous-known-good, release-required, rollback-required and active
candidate. Only explicitly abandoned/expired/unreferenced/superseded nonprotected objects become
prune candidates; unknown objects stay protected. Caller must supply complete accepted release
references; missing knowledge does not justify deletion. Report is deterministic and dry-run.
No provider delete/ACL/policy/bucket-create method exists in this package.

## Standalone admin commands

Install tools/distribution/requirements-admin.txt in an isolated Python3.11+ environment.
cryptography46.0.0 supplies portable Ed25519 verification; boto3 provides maintained SigV4/TLS,
range reads and conditional PUT. Neither enters normal Windows/Android runtime. Optional test
requirements add jsonschema for independent schema comparison. Pins belong to this preparation,
and must be reviewed for security/support before production deployment.

Environment names only:
AURORAFOX_S3_ENDPOINT, AURORAFOX_S3_REGION, AURORAFOX_S3_BUCKET,
AURORAFOX_S3_ACCESS_KEY_ID, AURORAFOX_S3_SECRET_ACCESS_KEY;
optional AURORAFOX_S3_SESSION_TOKEN. Missing any required name fails EXTERNAL_SETUP_PENDING.
No credential discovery from chats, no private key generation or real upload is implicit.

Examples (paths contain no credentials):

```sh
python tools/distribution/admin.py validate distribution/knowledge.production.pending.json
python tools/distribution/admin.py capacity --retention /private/retention.json
python tools/distribution/admin.py --local-store /private/object-fixture capacity
python tools/distribution/admin.py --public-key /private/distribution-public.pem --key-id distribution-owner upload /private/manifest.json /private/artifact.bin
python tools/distribution/admin.py --public-key /private/distribution-public.pem download /private/manifest.json /private/staging
python -m unittest discover -s tests/distribution -p 'test_*.py' -v
```

Describe command accepts artifact, metadata, output and mandatory external --private-key;
it signs distribution metadata only, never a production application release. The pending
Knowledge document is a metadata reservation, not a runnable input until actual hashes exist.
Validate command reports schema validation separately from signature verification.
Upload publication is explicit. First real operation is capacity/read-only bucket inspection:
confirm endpoint/bucket/region/quota/versions/policy with owner-controlled environment, then
fixture upload/byte verification/download, and finally the real pinned Knowledge artifact.
Do not enable public ACLs, overwrite unknown objects, remove local canonical archives or run
retention deletion. Record real evidence only in PROJECT_MASTER_LOG.md.

## Replacing providers

DistributionProvider requires size, bounded range read, atomic create-if-absent and inventory.
Manifest identity, signature, SHA and activation contracts stay provider-neutral. Client authorization
can change independently of admin credentials. A new provider must pass the same fixture protocol,
conditional collision, interruption/corruption/hash and capacity tests plus a real-provider smoke.
