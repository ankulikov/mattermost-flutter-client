# Drafts

Drafts are a session-owned in-memory projection keyed by channel and optional
thread root. Mattermost owns durable storage for synchronized drafts. Team loads
are shared across consumers and direct conversations are deduplicated by their
destination. The composer retains the same raw Markdown buffer in quick and
full-editor modes and suspends draft writes while editing a posted message.

Changes are debounced for 5 seconds and operations for a destination are
serialized. An attachment-only draft remains in session memory because the v4
API treats an empty message as deletion. Local typing takes precedence over a server draft that arrives later and is
synchronized normally. Server-provided type, props, priority,
and file metadata are preserved when saving an edited draft.

The Drafts destination lists drafts for the selected team and direct
conversations. Refresh and errors retain the existing list. Drafts and sync
metadata are not stored in Drift.

The account's `advanced_settings/sync_drafts` preference gates synchronization;
a disabled preference or an unsupported server leaves drafts in session memory.
Preference events and realtime recovery refresh that decision. Draft events and
recovery reconcile loaded teams through the API. Transient saves and deletes use
bounded retries and honor `Retry-After`. A sent draft whose deletion fails is
marked for cleanup so a retry does not create another post.
