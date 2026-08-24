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
