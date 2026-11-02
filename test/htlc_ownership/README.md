# HTLC ownership source fixtures

These finite offline fixtures create in-memory Boxes, original RPC Futures and
publication responses. They do not open Hive, connect a node, load a wallet or
invoke native signing. See [the environment record](../../docs/environment.md)
for the current executed scope and its source-bound evidence.

The captured store retains actual original backend Futures, encodes writes before
their first suspension, and shares a serial lane for each actual Box. A pre-RPC
reservation prevents terminal close from overtaking a later accepted publication
write. Store ownership requires both original registered and open backends. An
uncertain write or an observed replacement prevents a positive cleanup receipt.
Cipher migration refuses before opening or deleting a backend because an atomic
rollback receipt is unavailable in the existing storage API.

New chain-specific cursor entries advance by exactly one confirmed, linked HTLC
account block at a time. The handler reads pages of at most 100 and admits at
most 1,000 blocks in a default cycle. A positive prefix may be retained, while
expiry and automatic unlock wait for an exact caught-up frontier. Short, missing,
out-of-order, unconfirmed, wrong-chain and unsupported contract input cannot
become an empty account or terminal chain state. Legacy cursor keys are retained.
Expiry requires a matching fresh live deposit and a positive original chain
clock. Terminal history requires the exact confirmed Create and corresponding
confirmed contract receive and transfer output, never getById absence.

Automatic unlock checks the fresh exact recipient, deposit, hash lock, hash type,
key limit and existing SDK digest proof before invoking the captured sender.
The original selected account remains unchanged when another captured wallet
member is the recipient. Publishing and accepted holds remain keyed by chain,
deposit and recipient across remounts, with no retry timer or automatic release.
Manual and automatic withdrawals consult the same exact deposit and owner holds,
so switching callers cannot re-sign an accepted or uncertain original.
Private recovery payloads remain confined to versioned typed metadata in the
encrypted original swaps Box and internal models, never view DTOs, semantics,
logs or snapshot fixtures. The complete Box guard includes metadata while the
history catalogue omits only validated private entries. The disposable cursor
Box contains only reproducible height and hash checkpoints, never recovery.

Explicit New deposit can clear only a positively accepted Start marker matching
the exact confirmed original Create, its private recovery payload and the saved
original outgoing record. A spent live HTLC does not prevent this proof. Optional
live evidence must also match. Deletion refuses retained recovery-anchor records
until this explicit proof succeeds. Failed or unknown rearm keeps the hold.

Terminal shutdown stops the handler and drains its admitted cycle first, then
drains AutoUnlock, then pauses and closes the original store. Notifications and
the shared original publication pipeline need their own positive receipts.
Pending Futures remain pending; errors, timeout, absence and replacement do not
establish quiescence. Paused owners are terminal and must be replaced for a later
session. Actual encrypted backend durability, ABI compatibility, native
lifecycle and live-chain acceptance remain separate qualification requirements.
The environment record identifies which shared initialization, Node transition
and maintenance integration checks have executed.
