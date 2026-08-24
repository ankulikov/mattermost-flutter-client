# Local storage

Drift is reserved for feature data that must survive the process. The current
schema is empty: channel navigation, posts, threads, and paging state are
network-first and live only in Riverpod memory. The expected next durable data
owner is the users feature.

Platform-specific database opening belongs in this directory and must use a
background isolate on native platforms and Drift WASM with a worker on Web.
Every future table needs an explicit lifetime, freshness policy, and account
scope.

Authentication tokens are not database columns: keep them in
`flutter_secure_storage` and reference them by account id.
