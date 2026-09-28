# Local storage

Drift is reserved for feature data that must survive the process. User profiles,
recent emoji names, and the current account's expiring user-group membership
projection have explicit owners. Channel navigation, posts, threads, and paging
state remain network-first and live only in Riverpod memory.

Platform-specific database opening belongs in this directory and must use a
background isolate on native platforms and Drift WASM with a worker on Web.
Every future table needs an explicit lifetime, freshness policy, and account
scope.

Authentication tokens are not database columns: keep them in
`flutter_secure_storage` and reference them by account id.
