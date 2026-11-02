# Owned lab admission policy

`tools/devnet/lab/owned_lab.py` is an injected supervisor and wire-protocol
policy for the separate five-node chain-321 lab. It contains no Docker,
subprocess, filesystem, socket, download or wallet adapter, no command-line
entry point and no import-time I/O. Its standard-library source targets Python
3.9 and later. The policy tests use fake authorities, resources, clocks and
byte streams only; separate socket mechanics are described below. Authored
code or passing these tests cannot establish a
native launch, a source-built image, production, a checkpoint or a capture.

The default has no build authority and returns `BUILD_UNKNOWN` before storage
allocation or resource creation. This patch establishes no actual verified
source-build provenance. It does not invoke or change `lab.sh`, `frontier.js`,
the existing Compose project or historical resources.

## Trust boundary

A coordinator supplies trusted integration objects to `Supervisor`. They are
code-level authorities, not values supplied through an RPC request, environment
boolean, Docker label, file chosen by a caller or saved JSON report. Python is
not a sandbox against hostile code with access to these authority objects or
private attributes. An integration must keep those objects and the original
`Owner` in the same trusted supervisor process.

| Injection | Required actual evidence before returning |
|---|---|
| `BuildAuthority.verify/current` | An original retained source-build receipt, verified full source/tree and build-context identities, Dockerfile and base-image identities, Linux image ID/platform, complete assets/config hashes, generated genesis bytes and expected genesis momentum hash. Inspecting image labels is insufficient. Return `None` when this cannot be established. |
| `ManagedStorage.reserve/current` | A fresh approved task-storage reservation, five distinct exclusively created directory identities, correct mount/owner/lease and quota admission, no links or adopted files, and unchanged pinned genesis/config/fixture inputs. Preserve unknown or failed reservations. |
| `Runtime` | Bounded original command receipts and fresh create-returned IDs, followed by independent actual daemon/resource/start-state observations. Do not reconstruct a successful create or start receipt from later inspection. |
| Independent HTTP and WS `Transport` | Fresh direct connections only to the fixed loopback origins, with every connect/read/write/close enforcing the supplied absolute monotonic deadline. A `read(maximum, deadline)` returns at most `maximum` bytes. `Closed` must describe that exact original wire. No DNS, proxy, redirect, transparent reconnect, decompression or connection adoption. |

`Pins` contains expectations. `BuildWitness` is accepted only from the injected
build authority; `StorageReceipt`, `Created`, `Started` and `CommandReceipt`
are accepted only from the original injected operations. None has a report
deserializer. These data types do not independently authenticate their issuer.
The trusted adapters must actually perform the evidence checks in the table;
constructing fixture objects is not a production integration.

An `Owner` is minted inside a single `launch` call after fresh-storage and
preflight admission. Its public views are read-only, its resource collections
are tuples and its issuer and object identity are checked on every entry.
Another supervisor's capability, a copied object, a report or caller claims
cannot enter that lifecycle. A hold is permanent. Returning to an earlier
apparently valid resource does not revive the owner.

## Fixed identity and resource policy

The upstream source is exactly
`zenon-network/go-zenon@590f43ca7a24dccd8e883bc8903a0cb02e54528a`.
The application SHA/tree, upstream tree, immutable `sha256:` image ID,
`linux/amd64` platform, full build-context/Dockerfile/base-image identities,
asset and five config hashes, genesis JSON SHA-256 and genesis momentum hash
are required. Tags and abbreviated revisions are refused. The JSON digest and
momentum hash are separate identities; an adapter must not copy an unverified
RPC answer into the expected genesis pin.

Each launch gets a new random resource namespace. The five roles and subnet
match the existing lab topology. The runtime preflight must refuse any
existing selected container/network/volume, overlapping subnet, occupied
published port or conflicting mount, including stopped resources. It must
check wildcard and IPv6 listeners as well as the requested IPv4 loopback
bindings. Unrelated resources are preserved. Preflight absence alone is not a
creation receipt: the subsequent original create operation must return a new
full resource ID in the same daemon context. The trusted integration must also
exclude concurrent adoption races; an idempotent Docker volume-create result
does not establish fresh ownership.

The policy requests fresh managed bind directories, not Docker named volumes.
Each directory must already hold its exact staged public role fixtures,
config and generated chain-321 genesis. Container adapters must enforce and
inspect the complete mount set; `ContainerState.mounts` contains only the
identical original role-directory handle when no extra mount exists. They
must inspect the complete network/port set, image ID, restart policy `no`,
zero restart count and original start identity. Capped private container logs
are requested explicitly; adapters must enforce that cap and account for it
in the storage reservation.

Only the RPC role publishes `127.0.0.1:45997 -> 35997` and
`127.0.0.1:45998 -> 35998`. A runtime adapter must reject any additional
network, endpoint or published binding. Every ownership check revalidates the
build/storage witnesses, original network membership and all five original
running starts. Docker names, PIDs or labels alone are not these receipts.

## Bounded observation and shutdown

The HTTP parser accepts a successful JSON response with bounded
Content-Length or bounded chunked framing. It refuses duplicate headers,
ambiguous framing, redirects, compression, truncated input and oversized
headers/bodies. The WS parser verifies the RFC 6455 upgrade and accept value,
requests no extensions, masks client frames and bounds server frame sizes,
fragment totals, control frames and reads before parsing JSON. Binary,
masked-server, compressed, invalid continuation and noncanonical length
frames are refused. JSON has duplicate-key, integer-size, depth/node and
strict response-ID checks. The two transports cannot reuse one wire object.

Defaults bound launch/probe admission to 240 seconds, an individual
RPC to three seconds, a native command to twenty seconds and original wire
close to one second. There are at most 36 production polls, eight WS frames
per response, 16 KiB headers and 256 KiB response/frame payloads; the read-call
cap may refuse an input earlier. Original-wire cleanup gets its separate
one-second close bound; successful admission is rechecked afterward against
the original resources and the overall deadline. Trusted adapters must
interrupt their own blocking operations at the supplied deadline. Checking time after a late
return is refusal evidence, not a substitute for enforcing the deadline.

Both endpoints must independently report the expected chain-321 genesis.
Each frontier pair is cross-checked by querying the HTTP hash through WS and
the WS hash through HTTP. Both height and timestamp must advance, hashes must
change and intermediate observations must not regress or change at the same
height. Fixed-count polling only observes the same original resources. It
does not relaunch a node, reconnect a failed WS session or recover a refused
probe. These are bounded local RPC observations, not authenticated consensus
proof or evidence of every possible producer behavior.

`stop(owner)` requests graceful termination once, in reverse original-start
order. It first verifies each exact daemon/container/start identity, then
requires a successful original stop-command receipt and positively observed
zero exit with a distinct finish identity. A stop acknowledgment or command
exit zero alone is insufficient. There is no force/kill, remove, prune,
Compose teardown, restart, replacement, checkpoint restore or volume deletion
operation in this API. Unknown starts are not adopted as cleanup targets.
Known original starts can be stopped after a hold, but the hold remains and
the run cannot become successful. Interrupted, late and partial mutation
outcomes remain held with their original private receipts; resources and
storage remain retained for coordinator review.

The coordinator must retain the supervisor and adapter objects until all
their original operations and storage tasks have honest closure evidence.
The module does not automatically close a task-storage lease or declare
uncertain resources disposable.

## Evidence and staged qualification

`public()` is a fixed historical projection of pins, hashes, finite codes,
counts and booleans. It omits raw daemon/container/start identities, paths,
command text, tokens, fixture material and original diagnostics. It performs
no file write or upload. Private adapters retain original receipts and capped
failure evidence separately. `success` requires positive observation and all
five original zero exits; it cannot be true while the lab is merely running.
The fixed `evidence: injected-source-policy` label does not claim native
execution, even when a fake test reaches that complete state.

1. Qualify these source-policy cases with injected fakes. This proves only the
   finite policy/parser cases actually executed by the qualifier.
2. Separately implement and qualify approved managed-storage, verified-build,
   Linux Docker and bounded-wire adapters. Record the exact source, image,
   generated genesis, original resources and native observations on that host.
   The existing chain-69 BDD workflow cannot satisfy this stage.
3. Connect original wallet-process and verified chain/profile checkpoint
   capabilities on the same host before any seed publication. The existing
   SeedGuard, exact client/signing chain, index-1 funding, original transports,
   exclusive attempt journals and exact original confirmation/effect guards
   remain required. `--checkpoint-ready` continues to be an acknowledgment,
   not checkpoint creation or verification. No saved lab report can authorize
   a later seed run.
4. Qualify source-built Windows worker adapters separately against the same
   ownership and observation boundary. The committed DLL's source provenance
   remains unknown. Matching export names, the Dart SDK revision or these
   Linux source-policy results cannot establish its producer/genesis behavior.

`Owner.seed_admitted` and the `seed_admitted` field in every public projection
are unconditionally false.
This patch connects no wallet or checkpoint capability and closes no native
lab, seed, screen-capture or visual-match acceptance gate.

## Direct socket boundary

The separate `tools/devnet/lab/socket_transport.py` supplies a byte-only
`make_transports()` pair for the fixed HTTP and WS origins. It imports
`tools.devnet.lab.owned_lab` canonically; an integration must use that same
module identity for `Supervisor`, `Refused` and exact `Closed` receipt types.
Construction and import allocate no socket and perform no clock, filesystem,
command or network operation. There is no command-line entry point.

The two distinct transports share a private original-socket ledger. Production
allocation calls `socket.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)` directly.
The underscored factory/waiter/clock injections are trusted source-level seams,
never RPC/report configuration or authority to adopt existing descriptors.
Every newly returned original is retained before later checks, made
nonblocking, checked for an unbound/unconnected initial state and explicitly
bound to numeric IPv4 loopback. One `connect_ex` targets the fixed numeric peer;
pending/EINTR completion waits inspect that attempt without repeating it.
The original object, active descriptor, family, stream type and exact local
and peer endpoints stay pinned. A second object with an active original's
descriptor is held without closing that candidate. A descriptor number may
recur only on a different newly allocated original after positive prior close.

Every operation keeps the supplied absolute monotonic deadline. Additional
caps are three seconds per open/read/write, one separate second per close and
240 seconds per pair from the first admitted operation. HTTP can allocate at
most 128 originals, each for a distinct policy request; WS can allocate one
original and never reconnect. Each read/write/completion loop has at most
64 steps, each read requests at most 4 KiB, one write is at most 65,543 bytes,
and each wire has separate 32,768-call and 1 MiB read/write totals.
Interrupted or would-block I/O can continue only the same operation on the
same original within those bounds. Partial writes advance the exact accepted
prefix. A zero-byte read/write, timeout, invalid return, identity change or
other refusal permanently holds the pair. No operation resets a request
deadline, retries a request or reconnects as recovery.

A failed open closes only its retained, positively identified original once
under the separate close bound. Unproven/colliding descriptors remain held.
After a returned wire fails, the supervisor can close that original once.
Close first checks original descriptor and any established endpoint identity,
uses nonblocking mode with disabled linger, and requires the original object
to report descriptor `-1` within the close deadline. Late, failed, changed or
uncertain close is `CLOSE_UNKNOWN`; no second close, detach, replacement or
descriptor lookup is attempted. This proves local descriptor release only,
not peer receipt, node shutdown or a container's original zero exit. Original
raw errors remain capped private in-memory evidence; raised exceptions expose
only the existing finite policy codes.

`test/ci/test_owned_lab_socket_transport.py` separates deterministic injected
source-policy cases from optional explicit `AF_UNIX` socketpair byte mechanics.
Those optional cases create no TCP listener, DNS query, Docker resource,
service or node; they exercise native local socket I/O only when actually run.
Neither test category establishes a connected lab or advancing chain.
Qualification must identify which cases actually executed and any skips.

This adapter supplies no `BuildAuthority`, managed-storage or Docker runtime
authority and verifies no genesis or chain observation on its own. Those
capabilities remain `UNKNOWN` until separately connected and qualified.
Original wallet and verified checkpoint capabilities are still absent;
`seed_admitted` remains false. The committed Windows DLL's source provenance
remains unknown. No source or socketpair result changes those limits.
