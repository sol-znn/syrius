# Swap terms

The existing Start action creates one HTLC deposit. It records no requested
counterparty token or amount and cannot enforce the mockup's two-sided quote.
The new offer action therefore stays behind `swapTerms`. Direct activation
refuses before reads, secret generation, persistence or publication.

The existing Create deposit, Join, Complete, Reclaim and Recover operations
remain separate real capabilities. Their amounts and exact deposit identities
must come from their captured original source. Persisted labels cannot prove
that a deposit exists, has expired or has completed on chain.

The source constants specify an eight-hour initial deposit, a one-hour counter
deposit, six hours for preimage discovery and a ten-minute completion margin.
The mockup's 24-hour text does not change those rules. Reclamation is an
explicit transaction after positive chain-time and deposit proof; neither a
timeout nor an absent read establishes automatic return or success.

Local injected cases qualify ownership and source behavior only. They do not
establish native wallet signing, node integration or real swap safety.
