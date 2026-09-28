# Message search

Search is a self-contained network-first feature. Its Riverpod state owns the
draft query, submitted query, suggestions, results, pagination cursors, errors,
and scroll position until the search screen closes.

## Requests

Team search uses `POST /teams/{team_id}/posts/search`. Channel suggestions come
from `GET /teams/{team_id}/channels/search_autocomplete`; the `from:` modifier
uses a bounded user autocomplete request. The repository restores server order,
keeps root posts and replies, batch-loads authors, and fetches missing channel
metadata with bounded concurrency.

The first page uses `page=0&per_page=60`. Pagination continues only while the
server returns new post IDs and a new order fingerprint. This stops request
loops on SQL backends that do not advance search pagination.

Superseded suggestion and search requests are canceled. Query text and message
bodies do not enter logs or diagnostics. Search results and query history are
not stored in Drift or updated by WebSocket events; refresh requests a new
server snapshot.

## Navigation and errors

An initial failure shows a retry state. Refresh and pagination failures keep
existing results on screen and provide a local retry action.

"Search in channel" passes a launch intent that can insert a canonical `in:`
token and focus the field. It does not submit an empty search. Selecting a
result opens the shared permalink route, so root and reply resolution stays
consistent across layouts. Back returns to the saved query, result list, and
scroll position.

## Relevant code

- `lib/src/features/search/`
- `lib/src/ui/posts/post_permalink_route.dart`
