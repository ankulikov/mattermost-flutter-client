# Legacy attachment protocol fixtures

These fixtures freeze the wire shapes used by the legacy Mattermost attachment
milestone. Post fixtures are complete `Post` response objects: legacy cards are
stored in `props.attachments`. `action_api_response.json` is the response body
from `POST /api/v4/posts/{post_id}/actions/{action_id}`.

`integration` and `integration.context` are intentionally present where useful
to mirror server payloads, but client models must neither decode nor expose
them. Unknown fields remain available only through the lossless raw post props.
The value of `cookie` is opaque client-side and must be returned unchanged when
executing the corresponding action.

## Compatibility matrix

| Wire object | Supported fields | Compatibility behavior |
| --- | --- | --- |
| Attachment | `fallback`, `color`, `pretext`, `author_name`, `author_link`, `author_icon`, `title`, `title_link`, `text`, `fields`, `image_url`, `thumb_url`, `footer`, `footer_icon`, `ts`, `actions` | Decode valid children independently; preserve unknown raw props. |
| Field | `title`, `value`, `short` | Ignore one malformed field without dropping its attachment or valid siblings. |
| Action (common) | `id`, `type`, `name`, `tooltip`, `style`, `disabled`, `data_source`, `options`, `default_option`, `cookie` | Model `button` and `select`; retain an unknown type as an unknown action. Treat `cookie` as an opaque token. |
| Option | `text`, `value` | Ignore one malformed option without dropping its action or valid siblings. |
| Action internals | `integration`, `integration.context` | Do not decode or expose; keep only in raw props. |
| Action API response | `status`, `trigger_id`, `goto_location` | Decode optional navigation location without interpreting it in the transport layer. |

The malformed fixture deliberately contains invalid attachment, field, action,
and option children next to valid siblings. Its JSON syntax is valid; its child
shapes are not.
