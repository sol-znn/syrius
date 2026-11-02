# Captured account history source cases

These finite offline cases exercise the existing `AccountBlockUtils` helpers through the pinned SDK `LedgerApi` JSON decoder and injected `Client` responses. The socket fixture overrides dispatch and never initializes a connection. No fixture creates a wallet, signer, filesystem store, or real SDK transport.

The cases cover linked descending pagination through an exact timestamp boundary or genesis, positive confirmation and timestamp requirements, finite page admission, partial/null/empty catalogue refusals, exact-height timestamps, captured client/URL/chain/source departures, and retention of original errors. An actual empty first list with `count == 0` and `more != true` is the existing protocol's positive empty proof. Optional `more` and `count` do not establish a count-to-height invariant.

Every injected unresolved reply is fixture-owned, has an error observer, and is released before teardown awaits the original admitted reads. The current executed local scope is recorded in [the build environment](../../docs/environment.md). These fixtures do not establish live RPC behavior, native signing or running-wallet integration.
