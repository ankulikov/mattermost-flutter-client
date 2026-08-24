# Channel sidebar

The sidebar is a vertical feature slice. Presentation watches the local sidebar
store through the domain repository. Refreshes fetch the current user's first
team, that team's joined channels, and the user's channel categories. Direct and
group channel participants are resolved to display names with the users API.

Mattermost endpoints used by the initial implementation:

- `GET /users/me/teams`
- `GET /users/{user_id}/teams/{team_id}/channels`
- `GET /users/{user_id}/teams/{team_id}/channels/categories`
- `POST /users/ids`
- `POST /users/group_channels`

Channel and category responses are mapped to domain entities before entering the
store. The category response's separate `order` array defines the section order;
each category's `channel_ids` defines its channel order. The UI never consumes
HTTP responses directly. Drift persists normalized team, channel, category, and
ordering rows in one transaction. Every row is scoped by server/account key so
data from different Mattermost installations cannot mix.

The server category extensions `collapsed`, `muted`, and `sorting` are persisted
with the category. A collapsed category starts closed until the user overrides
it. Muted categories and their channels use a subdued visual emphasis. An empty
`sorting` value is treated as `manual`; `recent` orders channels by descending
`max(last_post_at, update_at)`, preserving the API's `channel_ids` order for
ties. This favors recent conversations while retaining a useful timestamp for
channels without posts.
