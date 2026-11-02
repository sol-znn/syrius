# Syrius lab

A go-zenon devnet of this repository's own, chain 321. Every harnessed run
that sends a block goes here, never to a public devnet: a spork activated from
a wallet as a test stopped a public devnet on 2026-10-11.

```sh
tools/devnet/lab/lab.sh up       # fetches go-zenon, builds the image and the assets on first use
tools/devnet/lab/lab.sh status   # containers, and whether momentums are being produced
tools/devnet/lab/lab.sh down     # stop, chain kept
tools/devnet/lab/lab.sh wipe     # stop, delete the chain and the assets
```

Needs bash (Git Bash on Windows), git, Docker and Node. Nothing outside this
repository: `lab.sh` fetches go-zenon from GitHub at one pinned commit into
`.build/` (`GO_ZENON_REV` and `GO_ZENON_URL` override it) and builds the image
from an export of that commit.

## What it is

go-zenon's five-node devnet (three pillars, an RPC node, an observer) under
names of its own, so it shares nothing with any other devnet on the machine:

| | The lab |
|---|---|
| Compose project | `syrius-lab` |
| Containers | `syrius-lab-*` |
| Network | `syrius-lab`, 172.37.0.0/24 |
| RPC on the host | `127.0.0.1:45997` HTTP, `127.0.0.1:45998` WS |
| Chain identifier | 321 |
| Restart policy | none: it stays down until `up` |

The chain identifier is the one change to go-zenon's devnet genesis
(`make-assets.js`). It is signed into every block and is the p2p network id,
so a block signed for the lab is worth nothing on any other chain.

Everything else is go-zenon's committed devnet, so its accounts hold: the
devnet mnemonic's index 1 (`z1qq6eg8n43g032hanpsfp02qcdmv7zfj3y2lt5d`) has
10,000 ZNN and 100,000 QSR and owns pillar `dev1`, index 0 produces for it and
is the spork address, and the genesis carries three fuses of 10,000 QSR owned
by index 1. The devnet mnemonic is public, in go-zenon's repository:

```
abstract affair idle position alien fluid board ordinary exist afraid chapter wood wood guide sun walnut crew perfect place firm poverty model side million
```

## Pointing the harness at it

```sh
harness/h start --fresh
harness/h import --mnemonic "<the devnet mnemonic>" --password '<password>' --node ws://127.0.0.1:45998 --chain 321
harness/h chain 321
```

The wallet signs with its own client chain identifier, default 1, and does not
follow the node: a send fails with "different network Id (1)" until `chain 321`.
Then add a second address in Settings and select it: index 1 is the funded
one. Check `lab.sh status` says "producing" before the first send: a stopped
chain accepts blocks into its pool and looks alive.

For an account that pays with proof of work, send ZNN from index 1 to another
index through the wallet and select that index.

## Limits

- The three genesis fuses cannot be cancelled: the plasma contract answers
  CancelFuse for one with an error (its receive block carries code 2 and sends
  nothing back), seen 2026-10-11 at momentum 33; the reason was not found. A
  fuse made on the lab can be cancelled only after 3,600 momentums
  (`FuseExpiration`, about 15 hours here), so a batch cancel needs a lab that
  has been left running.
- Momentums take about 15 s on Docker Desktop, not 10. The first momentum of
  a new chain comes about 90 s after the nodes start.
- The bridge contract is not usable: the `bridge-liq` spork is inactive in the
  devnet genesis and the bridge administrator is an address compiled into
  znnd that no devnet key holds.
- The Sporks page is read-only here: the wallet knows the spork administrator
  of chains 1 and 69 only. Do not activate a spork as a test on any chain.

## Hosted qualification

The manual `Public Contribution Qualification` workflow has a default-off
`chain321_lab` input. It prepares two independent fresh runners:

- Linux builds the pinned node command and runs five containers on an internal
  Docker network, exposing HTTP and WS through owned loopback relays only.
- Windows builds the same pinned node command and runs five native processes.
  Peer addresses and RPC bind to loopback; each original process has a separate
  data directory. Docker Desktop and a personal Windows computer are unnecessary
  for this native backend.

By default both use go-zenon `590f43ca7a24dccd8e883bc8903a0cb02e54528a`, Go 1.24.1,
the repository's chain-321 genesis generator and the original public devnet
keys. Native configuration changes only deployment paths, listen addresses
and peer ports. The Docker image contains the source-built static node command;
its image ID is recorded. No node binary, source archive or SDK is uploaded.
The compiler version and `-buildvcs=false` follow the
[pinned node release workflow](https://github.com/zenon-network/go-zenon/blob/590f43ca7a24dccd8e883bc8903a0cb02e54528a/.github/workflows/znn_builder.yml);
source provenance is checked independently. Module restoration
remains read-only. Compiler failures expose allowlisted codes and public symbols,
with no raw command output or private paths.

The Python suite runs before either lab starts. The controller requires a clean
source, exact source and binary hashes, fresh private directories, free ports,
five live original resources, matching HTTP/WS genesis and momentum observations,
positive height/timestamp progression and positive original shutdown. Command
output stays private; the explicit artifact is a finite allowlisted manifest.
No public RPC listener, external tunnel, real wallet or public-chain send is used.
The 4 GiB working cap uses cooperative samples rather than an OS disk quota.
Fresh non-secret hosted regression VMs use an explicitly separate 2 GiB floor
plus the 4 GiB declared reserve. The controller refuses self-hosted execution.
The local production store keeps its 10 GiB floor and existing quotas.
Ephemeral-runner destruction is separate from verified process shutdown and is
not claimed as qualified storage cleanup.

These jobs qualify two independent lab instances. They do not connect a Windows
runner to the Linux runner, admit a seed recipe, create a wallet checkpoint or
prove any screen match. Full native wallet preparation, captures and motion
acceptance must consume actual owned runtime evidence in a later integration;
the existing recipe and entry guards stay in force. Execution status and exact
run/source bindings are recorded in `docs/environment.md` and the progress log.

The same workflow can inspect a completed lab run by supplying
`inspect_chain321_run` and its exact `inspect_chain321_head`, with other inputs
disabled. This read-only job verifies the two finite manifest archives in memory
and emits only allowed stages and compiler codes as job annotations. It starts
no node and repeats no build. The GitHub API credential is removed before the
signed artifact request; redirects, hashes, ZIP member type, CRC, source/run
bindings and size limits are checked. Saved reports remain observations and
cannot authorize a wallet, seed recipe or new runtime.

The hosted node build enables Cgo because the pinned secp256k1 dependency
requires it. GCC target/version are recorded; node and module versions remain
locked. External static linkage with `netgo,osusergo` is requested on both
platforms. Linux binaries must pass a bounded ELF64/AMD64 check with no
interpreter or dynamic section before entering the scratch image. Compiler
success and image checks are prerequisites, separate from advancing chain
production and original shutdown.

Runtime reports retain finite wire-policy codes and the first observation
failure separately from close failure. Observation phase, original process
exit/signal facts, created-resource Docker state and allowlisted node failure
categories can be inspected without publishing raw node logs. These fields
remain evidence only and cannot adopt a runtime or admit wallet preparation.

The pinned node selects RPC listeners from nonempty host strings. Non-RPC roles
therefore receive empty HTTP/WS hosts as well as disabled flags. Public
keystore fixtures contain an embedded deployment Path; the controller moves
only that exact field to the new owned wallet path. Every encrypted and other
non-path field is preserved, before/after hashes are recorded, and deployed
fixture bytes are rechecked after production. This is deployment relocation,
with no fixture decryption or re-encryption.

A committed fixture filename may differ from its baseAddress metadata. The
controller preserves that metadata independently and retains the exact source
Path check; it does not invent an equality the node itself does not require.
The node continues to validate the actual derived producer address.

On hosted Linux, the controller probes the exact RPC member on its internal
bridge, then binds two owned loopback relays to the existing fixed HTTP/WS
origins. Both direct ports and current resource ownership must pass first.
Destinations are fixed; there is no DNS, external listener, daemon change or
published host port. Byte/buffer/time/connection limits and positive original
socket/thread closure are separate from node shutdown and chain production.

Use the manual chain321_backend choice to select both backends (the default),
native Windows only or Linux Docker only. The same choice selects which
original manifest archives a read-only inspection requires. Native shutdown
requests all five original peer handles before waiting; each signal remains
one-attempt, and zero/complete/unforced exit is still mandatory. Saved
momentum observations and successful jobs never authorize wallet or seed use.

After each original native process has exited, the controller may inspect the
pinned node's two fixed log files inside its owned data directory. Existing
regular-file, ancestor, identity and one-MiB guards apply. The manifest retains
finite shutdown-stage codes, missing/refused/read status, sizes and hashes;
raw logs and paths are not uploaded. This projection cannot convert a timeout
or forced exit into successful shutdown.

The separate native_stack_diagnostic input defaults off. It enables the pinned
node's existing profiler on original roles at separate preflighted loopback
ports: RPC 45999, pillar 46000, pillar2 46001, pillar3 46002 and observer 46003.
Each original handle retains its fixed role and port; a changed binding is
refused before a connection. A real shutdown timeout permits one bounded
loopback read before that original's existing forced cleanup. Only fixed
codes from a single shutdown goroutine, byte count and hash are retained.
Inspection validates every probe and retains per-role statuses plus one
captured detail, or the first attempted detail if none was captured. Older
RPC-only records retain their separate scope. No raw stack is uploaded, no
external listener is opened and no diagnostic observation can turn a forced
exit into success.

After an original shutdown stack is captured, a bounded worker projection
can locate its protocol syncer and message-handler paths. It keeps only
fixed kind/wait-state codes, a public protocol package, relative-source-path
digest and line number. Actual matching-worker count is retained with at
most four unique sites; inspection validates all sites and projects two,
prioritizing the syncer. Unknown waits become OTHER and malformed data
refuses partial worker facts. Raw paths, arguments and goroutine identifiers
remain private. These locations do not change any original exit or admit a
wallet, seed, checkpoint or recovered process.

Docker shutdown verifies the original container set before submitting all
verified identities in one stop command. Daemon grace remains twenty seconds
and the original parent command remains bounded at thirty seconds. Its actual
exit, output-completeness and forced facts are retained. Every original is
reinspected with its image and owner before exit-zero/no-OOM admission.
Changed identities are excluded and keep the result failed. A failed first
attempt cannot be replaced by another stop or later successful observation.

Native retirement requests all five original peers in creation order before
waiting for any member. The upstream peer server joins workers, so retiring
one member while its peers remain live can keep it pending. Each handle
retains its one signal attempt and strict zero/complete/unforced exit
requirement. Attempted role order and coordinated mode are finite evidence
only; any original failure keeps the lab failed.

The explicit chain321_node_source choice defaults to original. Selecting
upstream uses only commit 2d1b929cc3fa5269cf133757d4a6963821137984, tree
4467fff960ea6a5409908d7c85497a68482e0edb, which joins the legacy run loop and
protocol workers during shutdown. These two choices reject moving branches
and unrecorded source changes. This path requires all seven named upstream Go shutdown tests and
the package pass, without skips, before starting the lab. Exact SHA/tree and
regression outcomes remain separate from chain production and original exit.
Retained-manifest inspection must select the same node source. The older
default's failed native results and successful Linux result remain separate.

An original native panic has a separate bounded projection after terminal
exit. It records a fixed category, output byte count and digest, and up to
three public package names with relative-source-path digests and line
numbers from the crashing goroutine. A path digest hashes the relative path,
not file contents. Unknown text is never echoed. Ambiguous or malformed
stacks keep an explicit status. Inspection validates every panic receipt,
then emits only the first detail and a count to keep its notice complete.
These observations cannot change an original exit code or qualify shutdown.

The separate lab-fix choice starts from that exact upstream SHA/tree and
applies only the checked-in closed-producer-task correction. Before applying
it, the controller copies a pinned Go regression into the fresh node checkout
and requires the actual named test to fail with the observed nil-task panic.
A zero exit, empty test filter, unrelated crash, compiler failure or skipped
test refuses the correction. It then applies the pinned patch, verifies the
entire staged compiled tree, requires the same test and package to pass, and
runs all seven upstream shutdown regressions before lab startup.

The base tree remains 4467fff960ea6a5409908d7c85497a68482e0edb. The compiled
lab-fix tree is a9262cce18190bfc01e85ac903558500379d014f. Patch and test-fixture
SHA-256 values, both actual test exits and staged/worktree correspondence are
checked. Source changes outside the two expected files are refused. A cold
regression compile has a 600-second parent bound; its test runtime remains
30 seconds. The patched test has a 180-second parent bound. Native shutdown
still requires zero, complete, unforced original exits with the same wait.
Neither pristine source choice, the wallet SDK nor embedded binaries change.
Inspection requires lab-fix explicitly and cannot relabel its result as an
unmodified node result. All wallet, checkpoint, seed and visual gates remain
separate from this isolated node correction.

If the seven upstream shutdown tests fail before startup, the manifest keeps
the original command exit, output-completeness and forced-termination facts.
Its bounded observer emits only known parent names and their pass, fail,
skip or active states, public shutdown_test.go line numbers and fixed failure
categories. It retains no raw paths or messages, retries nothing, and
rethrows the original failure. Observation completeness cannot qualify a
test pass or admit a lab, wallet or seed. The seven-test gate stays required.
The pinned reconnect assertion can additionally report a fixed error
category only after that original named parent fails. Unknown errors stay
unclassified. The client error text and socket details are never emitted;
the expected disconnect reason and all Go assertions remain unchanged.

The Windows wallet-tour lane uses an explicit qualification-only client
fixture after building the node. It changes only `dialHandshake` in the
pinned test file: read the server's early protocol rejection before sending
the client protocol message. The seven test bodies are byte-identical,
including the required `DiscAlreadyConnected` assertion. No reset error is
accepted as a replacement disconnect reason.

The original file, patch, adapted file and complete test-body suffix have
fixed digests. The CLI remains built from producer-corrected tree
`a9262cce18190bfc01e85ac903558500379d014f`. The fixture applies only to
the seven-test command, then restores the exact original test file and
rechecks the complete production tree before asset creation. A normal
failed test is restored but remains failed; a forced, incomplete or unknown
command or changed file is held without reverse application. Source-only
validation and local policy cases do not qualify Windows runtime behaviour.
The ordinary native and Docker node-only lanes keep their original client.
