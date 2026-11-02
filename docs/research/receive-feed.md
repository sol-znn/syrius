# Captured receive feeds

An automatic receive belongs to the original unlocked wallet, account list,
connection, chain and shared sender. Replacing one of those resources revokes
that origin. A delayed scan cannot acquire authority from a later session.

`ReceiveFeedConnection` keeps the two original subscription futures, including
failed or uncertain admissions, until a new connection supplies a broadcaster.
Rearming an unlocked view reuses those receipts. Closing or locking the view
revokes its listener and synchronization notice before deferred work resumes.

The notification envelope follows the pinned node implementation:

- [`rpc/server/json.go`](https://github.com/zenon-network/go-zenon/blob/590f43ca7a24dccd8e883bc8903a0cb02e54528a/rpc/server/json.go)
  defines the `.subscription` method suffix and the `subscription` and `result`
  members of the notification parameters.
- [`rpc/server/subscription.go`](https://github.com/zenon-network/go-zenon/blob/590f43ca7a24dccd8e883bc8903a0cb02e54528a/rpc/server/subscription.go)
  constructs that notification from the namespace, exact subscription ID and
  result. The receive feed accepts only `ledger.subscription` notifications
  carrying one of its own IDs.

Malformed envelopes and empty results do not authorize a receive. Account
events need an exact hash and a destination in the captured member snapshot.
The worker reserves the original shared sender, reads the inbound block through
its independently bound ledger, and verifies its destination and chain before
constructing a receive with the captured chain identifier.

The durable journal retains the inbound identity and original publication
outcome. It does not retain the wallet origin or decrypted wallet material.
An uncertain publication remains held; a reconnect, timer or confirmation
cannot turn it into permission to publish a replacement.

Node-chain discovery needs a positive frontier response from the original
transport. Failure or a nonpositive chain identifier stays unknown. There is
no mainnet fallback for authorization.

These source contracts and injected offline tests do not establish a working
node subscription, a real-wallet receive, native UI behavior or live-chain
confirmation. Those require separate owned integration evidence.
