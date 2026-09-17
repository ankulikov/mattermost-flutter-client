/// A legacy Mattermost message attachment rendered alongside a post's text.
///
/// This is deliberately separate from file attachments. It contains only the
/// presentation and action data that is safe to expose outside the data layer.
final class RichAttachment {
  const RichAttachment({
    this.fallback = '',
    this.color = '',
    this.pretext = '',
    this.authorName = '',
    this.authorLink = '',
    this.authorIconUrl = '',
    this.title = '',
    this.titleLink = '',
    this.text = '',
    this.fields = const <RichAttachmentField>[],
    this.imageUrl = '',
    this.thumbnailUrl = '',
    this.footer = '',
    this.footerIconUrl = '',
    this.timestamp,
    this.actions = const <RichAttachmentAction>[],
  });

  final String fallback;
  final String color;
  final String pretext;
  final String authorName;
  final String authorLink;
  final String authorIconUrl;
  final String title;
  final String titleLink;
  final String text;
  final List<RichAttachmentField> fields;
  final String imageUrl;
  final String thumbnailUrl;
  final String footer;
  final String footerIconUrl;
  final DateTime? timestamp;
  final List<RichAttachmentAction> actions;
}

final class RichAttachmentField {
  const RichAttachmentField({
    required this.title,
    required this.value,
    this.isShort = false,
  });

  final String title;
  final String value;
  final bool isShort;
}

/// A selectable value. Both fields are display-safe domain values; neither is
/// interpreted as integration configuration by the client.
final class RichAttachmentOption {
  const RichAttachmentOption({required this.text, required this.value});

  final String text;
  final String value;
}

/// Encrypted action data that must be passed back to Mattermost unchanged.
///
/// Keeping it in a value object prevents presentation code from treating the
/// token as integration context or parsing its implementation-specific value.
final class RichAttachmentActionToken {
  const RichAttachmentActionToken(this.value)
    : assert(value != '', 'An action token must not be empty.');

  final String value;
}

sealed class RichAttachmentAction {
  const RichAttachmentAction({
    required this.id,
    required this.name,
    this.token,
  });

  final String id;
  final String name;
  final RichAttachmentActionToken? token;
}

/// Semantic styles understood by Mattermost legacy buttons.
///
/// [good] and [success] remain distinct protocol spellings even though a
/// renderer may intentionally give both the same positive treatment.
enum RichAttachmentButtonStyle {
  defaultStyle,
  primary,
  good,
  success,
  warning,
  danger,
  customColor,
  unknown,
}

final class RichAttachmentButtonAction extends RichAttachmentAction {
  const RichAttachmentButtonAction({
    required super.id,
    required super.name,
    super.token,
    this.tooltip = '',
    this.style = RichAttachmentButtonStyle.defaultStyle,
    this.customColor = '',
  }) : assert(
         style == RichAttachmentButtonStyle.customColor || customColor == '',
         'A custom color is only valid for the customColor button style.',
       );

  final String tooltip;
  final RichAttachmentButtonStyle style;

  /// Original legacy hex color when [style] is [RichAttachmentButtonStyle.customColor].
  final String customColor;
}

enum RichAttachmentSelectDataSource { channels, users, unknown }

final class RichAttachmentSelectAction extends RichAttachmentAction {
  const RichAttachmentSelectAction({
    required super.id,
    required super.name,
    super.token,
    this.options = const <RichAttachmentOption>[],
    this.defaultOption,
    this.dataSource,
  });

  /// Static choices. This is empty for a system-backed select.
  final List<RichAttachmentOption> options;

  /// Value of the initially selected option, when supplied by the server.
  final String? defaultOption;

  /// `null` means a static select backed by [options].
  final RichAttachmentSelectDataSource? dataSource;
}

/// A forward-compatible action which the current client cannot execute.
final class RichAttachmentUnknownAction extends RichAttachmentAction {
  const RichAttachmentUnknownAction({
    required super.id,
    required super.name,
    required this.type,
    super.token,
  });

  final String type;
}
