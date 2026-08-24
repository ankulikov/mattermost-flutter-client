# Channel sidebar

The sidebar is loaded from Mattermost whenever an authenticated controller is
created. It fetches the current user's first team, joined channels, categories,
and direct/group participant names. The mapped domain snapshot is kept only in
Riverpod memory and is never written to Drift.

Manual refresh keeps the last successful snapshot visible while the request is
running. A failure is shown as a non-blocking banner when data exists, or as an
initial retry state otherwise. Category order, channel order, collapsed/muted
flags, and recent sorting still come from the server response.
