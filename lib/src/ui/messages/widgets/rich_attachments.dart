import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/post_action.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/ui/messages/post_action_controller.dart';
import 'package:mattermost_flutter/src/ui/messages/rich_attachment_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/system_select_picker.dart';

typedef RichAttachmentActionCallback =
    FutureOr<void> Function(
      RichAttachmentAction action,
      String? selectedOption,
    );

/// Renders legacy Mattermost attachment cards without exposing integration data.
class RichAttachments extends StatelessWidget {
  const RichAttachments({
    required this.attachments,
    this.customEmojis = const <CustomEmojiReference>[],
    this.serverUrl,
    this.onSelectChannel,
    this.onOpenPostLink,
    this.onAction,
    this.postId,
    this.channelId,
    this.sourceRootPostId,
    this.actionScopeId,
    this.onPostUpdated,
    this.onGotoLocation,
    super.key,
  });

  final List<RichAttachment> attachments;
  final List<CustomEmojiReference> customEmojis;
  final Uri? serverUrl;
  final ValueChanged<String>? onSelectChannel;
  final ValueChanged<String>? onOpenPostLink;
  final RichAttachmentActionCallback? onAction;
  final String? postId;
  final String? channelId;
  final String? sourceRootPostId;
  final String? actionScopeId;
  final ValueChanged<ChannelPost>? onPostUpdated;
  final ValueChanged<String>? onGotoLocation;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: RichAttachmentStrings.attachments,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final RichAttachment attachment in attachments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RichAttachmentCard(
                attachment: attachment,
                customEmojis: customEmojis,
                serverUrl: serverUrl,
                onSelectChannel: onSelectChannel,
                onOpenPostLink: onOpenPostLink,
                onAction: onAction,
                postId: postId,
                channelId: channelId,
                sourceRootPostId: sourceRootPostId,
                actionScopeId: actionScopeId,
                onPostUpdated: onPostUpdated,
                onGotoLocation: onGotoLocation,
              ),
            ),
        ],
      ),
    );
  }
}

class _RichAttachmentCard extends StatelessWidget {
  const _RichAttachmentCard({
    required this.attachment,
    required this.customEmojis,
    required this.serverUrl,
    required this.onSelectChannel,
    required this.onOpenPostLink,
    required this.onAction,
    required this.postId,
    required this.channelId,
    required this.sourceRootPostId,
    required this.actionScopeId,
    required this.onPostUpdated,
    required this.onGotoLocation,
  });

  final RichAttachment attachment;
  final List<CustomEmojiReference> customEmojis;
  final Uri? serverUrl;
  final ValueChanged<String>? onSelectChannel;
  final ValueChanged<String>? onOpenPostLink;
  final RichAttachmentActionCallback? onAction;
  final String? postId;
  final String? channelId;
  final String? sourceRootPostId;
  final String? actionScopeId;
  final ValueChanged<ChannelPost>? onPostUpdated;
  final ValueChanged<String>? onGotoLocation;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = _accentColor(attachment.color, colors);
    return Semantics(
      container: true,
      child: DecoratedBox(
        key: ValueKey<String>('rich-attachment-${attachment.title}'),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(left: BorderSide(color: accent, width: 4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (attachment.pretext.isNotEmpty) ...<Widget>[
                _MarkdownText(attachment.pretext, this),
                const SizedBox(height: 8),
              ],
              if (attachment.authorName.isNotEmpty)
                _AuthorLine(attachment: attachment, card: this),
              if (attachment.title.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _AttachmentTitle(attachment: attachment, card: this),
              ],
              if (attachment.text.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _MarkdownText(attachment.text, this),
              ],
              if (attachment.fields.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                _Fields(fields: attachment.fields, card: this),
              ],
              if (attachment.imageUrl.isNotEmpty ||
                  attachment.thumbnailUrl.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                _RemoteAttachmentImage(
                  url: attachment.imageUrl.isNotEmpty
                      ? attachment.imageUrl
                      : attachment.thumbnailUrl,
                ),
              ],
              if (attachment.actions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                _Actions(
                  actions: attachment.actions,
                  onAction: onAction,
                  postId: postId,
                  channelId: channelId,
                  sourceRootPostId: sourceRootPostId,
                  actionScopeId: actionScopeId,
                  onPostUpdated: onPostUpdated,
                  onGotoLocation: onGotoLocation,
                ),
              ],
              if (attachment.footer.isNotEmpty ||
                  attachment.timestamp != null) ...<Widget>[
                const SizedBox(height: 10),
                _Footer(attachment: attachment),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkdownText extends StatelessWidget {
  const _MarkdownText(this.data, this.card, {this.style});

  final String data;
  final _RichAttachmentCard card;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => MessageMarkdown(
    data: data,
    customEmojis: card.customEmojis,
    serverUrl: card.serverUrl,
    onSelectChannel: card.onSelectChannel,
    onOpenPostLink: card.onOpenPostLink,
    textStyle: style,
  );
}

class _AuthorLine extends StatelessWidget {
  const _AuthorLine({required this.attachment, required this.card});

  final RichAttachment attachment;
  final _RichAttachmentCard card;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      if (attachment.authorIconUrl.isNotEmpty) ...<Widget>[
        _RemoteAttachmentImage(url: attachment.authorIconUrl, avatar: true),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: _MarkdownText(
          _linkedMarkdown(attachment.authorName, attachment.authorLink),
          card,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _AttachmentTitle extends StatelessWidget {
  const _AttachmentTitle({required this.attachment, required this.card});

  final RichAttachment attachment;
  final _RichAttachmentCard card;

  @override
  Widget build(BuildContext context) => _MarkdownText(
    _linkedMarkdown(attachment.title, attachment.titleLink),
    card,
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _Fields extends StatelessWidget {
  const _Fields({required this.fields, required this.card});

  final List<RichAttachmentField> fields;
  final _RichAttachmentCard card;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final double availableWidth = constraints.maxWidth;
      final double shortWidth = availableWidth >= 360
          ? (availableWidth - 16) / 2
          : availableWidth;
      return Wrap(
        spacing: 16,
        runSpacing: 8,
        children: fields
            .map(
              (RichAttachmentField field) => SizedBox(
                width: field.isShort ? shortWidth : availableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _MarkdownText(
                      field.title,
                      card,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _MarkdownText(field.value, card),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      );
    },
  );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.attachment});

  final RichAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final String timestamp = attachment.timestamp == null
        ? ''
        : DateFormat.yMMMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).format(attachment.timestamp!.toLocal());
    final String label = <String>[
      attachment.footer,
      timestamp,
    ].where((String part) => part.isNotEmpty).join(' • ');
    return Row(
      children: <Widget>[
        if (attachment.footerIconUrl.isNotEmpty) ...<Widget>[
          _RemoteAttachmentImage(url: attachment.footerIconUrl, avatar: true),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.actions,
    required this.onAction,
    required this.postId,
    required this.channelId,
    required this.sourceRootPostId,
    required this.actionScopeId,
    required this.onPostUpdated,
    required this.onGotoLocation,
  });

  final List<RichAttachmentAction> actions;
  final RichAttachmentActionCallback? onAction;
  final String? postId;
  final String? channelId;
  final String? sourceRootPostId;
  final String? actionScopeId;
  final ValueChanged<ChannelPost>? onPostUpdated;
  final ValueChanged<String>? onGotoLocation;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: OrderedTraversalPolicy(),
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: actions.indexed
            .map(
              ((int, RichAttachmentAction) indexed) => FocusTraversalOrder(
                order: NumericFocusOrder(indexed.$1.toDouble()),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: switch (indexed.$2) {
                    final RichAttachmentButtonAction action => _ButtonAction(
                      action: action,
                      onAction: onAction,
                      postId: postId,
                      channelId: channelId,
                      sourceRootPostId: sourceRootPostId,
                      actionScopeId: actionScopeId,
                      onPostUpdated: onPostUpdated,
                      onGotoLocation: onGotoLocation,
                    ),
                    final RichAttachmentSelectAction action => _SelectAction(
                      action: action,
                      onAction: onAction,
                      postId: postId,
                      channelId: channelId,
                      sourceRootPostId: sourceRootPostId,
                      actionScopeId: actionScopeId,
                      onPostUpdated: onPostUpdated,
                      onGotoLocation: onGotoLocation,
                    ),
                    final RichAttachmentUnknownAction action => Tooltip(
                      message: RichAttachmentStrings.unsupportedAction,
                      child: OutlinedButton(
                        onPressed: null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(44, 44),
                        ),
                        child: Text(action.name),
                      ),
                    ),
                  },
                ),
              ),
            )
            .toList(growable: false),
      ),
    ),
  );
}

class _ButtonAction extends ConsumerWidget {
  const _ButtonAction({
    required this.action,
    required this.onAction,
    required this.postId,
    required this.channelId,
    required this.sourceRootPostId,
    required this.actionScopeId,
    required this.onPostUpdated,
    required this.onGotoLocation,
  });

  final RichAttachmentButtonAction action;
  final RichAttachmentActionCallback? onAction;
  final String? postId;
  final String? channelId;
  final String? sourceRootPostId;
  final String? actionScopeId;
  final ValueChanged<ChannelPost>? onPostUpdated;
  final ValueChanged<String>? onGotoLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ButtonStyle style = _buttonStyle(context, action);
    final PostActionControlKey? key = _controlKey(
      postId,
      actionScopeId,
      channelId,
      sourceRootPostId,
      action,
    );
    final PostActionControlState? actionState = key == null
        ? null
        : ref.watch(postActionControlProvider(key));
    if (key != null) {
      ref.listen<ChannelPost?>(
        postActionControlProvider(
          key,
        ).select((PostActionControlState state) => state.realtimeUpdatedPost),
        (ChannelPost? previous, ChannelPost? next) {
          if (next != null && !identical(previous, next)) {
            onPostUpdated?.call(next);
          }
        },
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Tooltip(
          message: action.tooltip,
          child: ElevatedButton(
            onPressed: onAction == null || (actionState?.isLoading ?? false)
                ? null
                : () => unawaited(
                    _execute(
                      context,
                      ref,
                      key,
                      action,
                      null,
                      onAction,
                      onPostUpdated,
                      onGotoLocation,
                    ),
                  ),
            style: style,
            child: Text(action.name),
          ),
        ),
        if (actionState?.error != null) const _ActionError(),
        if (actionState?.feedback.isNotEmpty == true)
          _ActionFeedback(actionState!.feedback),
      ],
    );
  }
}

class _SelectAction extends ConsumerWidget {
  const _SelectAction({
    required this.action,
    required this.onAction,
    required this.postId,
    required this.channelId,
    required this.sourceRootPostId,
    required this.actionScopeId,
    required this.onPostUpdated,
    required this.onGotoLocation,
  });

  final RichAttachmentSelectAction action;
  final RichAttachmentActionCallback? onAction;
  final String? postId;
  final String? channelId;
  final String? sourceRootPostId;
  final String? actionScopeId;
  final ValueChanged<ChannelPost>? onPostUpdated;
  final ValueChanged<String>? onGotoLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PostActionControlKey? key = _controlKey(
      postId,
      actionScopeId,
      channelId,
      sourceRootPostId,
      action,
    );
    final PostActionControlState? actionState = key == null
        ? null
        : ref.watch(postActionControlProvider(key));
    if (key != null) {
      ref.listen<ChannelPost?>(
        postActionControlProvider(
          key,
        ).select((PostActionControlState state) => state.realtimeUpdatedPost),
        (ChannelPost? previous, ChannelPost? next) {
          if (next != null && !identical(previous, next)) {
            onPostUpdated?.call(next);
          }
        },
      );
    }
    final String? selected = action.options
        .where(
          (RichAttachmentOption option) => option.value == action.defaultOption,
        )
        .map((RichAttachmentOption option) => option.value)
        .firstOrNull;
    final bool isSystemSelect =
        action.dataSource == RichAttachmentSelectDataSource.users ||
        action.dataSource == RichAttachmentSelectDataSource.channels;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableWidth = constraints.maxWidth;
        final double controlWidth = isSystemSelect ? 220 : 180;
        return SizedBox(
          width: availableWidth < controlWidth ? availableWidth : controlWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (isSystemSelect)
                OutlinedButton.icon(
                  onPressed:
                      onAction == null || (actionState?.isLoading ?? false)
                      ? null
                      : () async {
                          final String? value = await showSystemSelectPicker(
                            context: context,
                            title: action.name,
                            dataSource: action.dataSource!,
                          );
                          if (value == null || !context.mounted) return;
                          await _execute(
                            context,
                            ref,
                            key,
                            action,
                            value,
                            onAction,
                            onPostUpdated,
                            onGotoLocation,
                          );
                        },
                  icon: const Icon(Icons.search),
                  label: Text(action.name, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: action.name),
                  hint: const Text(RichAttachmentStrings.select),
                  items: action.options
                      .map(
                        (RichAttachmentOption option) =>
                            DropdownMenuItem<String>(
                              value: option.value,
                              child: Text(
                                option.text,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      )
                      .toList(growable: false),
                  onChanged:
                      onAction == null ||
                          action.options.isEmpty ||
                          (actionState?.isLoading ?? false)
                      ? null
                      : (String? value) {
                          if (value != null) {
                            unawaited(
                              _execute(
                                context,
                                ref,
                                key,
                                action,
                                value,
                                onAction,
                                onPostUpdated,
                                onGotoLocation,
                              ),
                            );
                          }
                        },
                ),
              if (actionState?.error != null) const _ActionError(),
              if (actionState?.feedback.isNotEmpty == true)
                _ActionFeedback(actionState!.feedback),
            ],
          ),
        );
      },
    );
  }
}

class _ActionError extends StatelessWidget {
  const _ActionError();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        RichAttachmentStrings.actionFailed,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    ),
  );
}

class _ActionFeedback extends StatelessWidget {
  const _ActionFeedback(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

PostActionControlKey? _controlKey(
  String? postId,
  String? scopeId,
  String? channelId,
  String? sourceRootPostId,
  RichAttachmentAction action,
) =>
    postId == null ||
        scopeId == null ||
        channelId == null ||
        sourceRootPostId == null
    ? null
    : (
        scopeId: scopeId,
        postId: postId,
        actionId: action.id,
        channelId: channelId,
        sourceRootPostId: sourceRootPostId,
      );

Future<void> _execute(
  BuildContext context,
  WidgetRef ref,
  PostActionControlKey? key,
  RichAttachmentAction action,
  String? selectedOption,
  RichAttachmentActionCallback? fallback,
  ValueChanged<ChannelPost>? onPostUpdated,
  ValueChanged<String>? onGotoLocation,
) async {
  if (key == null) {
    await fallback?.call(action, selectedOption);
    return;
  }
  final PostActionResult? result = await ref
      .read(postActionControlProvider(key).notifier)
      .submit(action: action, selectedOption: selectedOption);
  if (!context.mounted || result == null) return;
  onPostUpdated?.call(result.updatedPost);
  if (result.gotoLocation.isNotEmpty) onGotoLocation?.call(result.gotoLocation);
}

class _RemoteAttachmentImage extends StatelessWidget {
  const _RemoteAttachmentImage({required this.url, this.avatar = false});

  final String url;
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    final Uri? uri = Uri.tryParse(url);
    final bool valid =
        uri != null &&
        const <String>{'http', 'https'}.contains(uri.scheme.toLowerCase());
    final double size = avatar ? 20 : 240;
    final Widget fallback = Semantics(
      label: RichAttachmentStrings.imageUnavailable,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
    if (!valid) return fallback;
    return Semantics(
      label: RichAttachmentStrings.image,
      image: true,
      child: SizedBox(
        width: avatar ? size : null,
        height: avatar ? size : null,
        child: ConstrainedBox(
          constraints: avatar
              ? const BoxConstraints.tightFor(width: 20, height: 20)
              : const BoxConstraints(maxHeight: 320, maxWidth: 560),
          child: Image.network(
            uri.toString(),
            fit: avatar ? BoxFit.cover : BoxFit.contain,
            loadingBuilder: (_, Widget child, ImageChunkEvent? progress) =>
                progress == null
                ? child
                : const Center(
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
            errorBuilder: (_, _, _) => fallback,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}

ButtonStyle _buttonStyle(
  BuildContext context,
  RichAttachmentButtonAction action,
) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final Color? background = switch (action.style) {
    RichAttachmentButtonStyle.primary => colors.primary,
    RichAttachmentButtonStyle.good ||
    RichAttachmentButtonStyle.success => Colors.green.shade700,
    RichAttachmentButtonStyle.warning => Colors.orange.shade800,
    RichAttachmentButtonStyle.danger => colors.error,
    RichAttachmentButtonStyle.customColor => _hexColor(action.customColor),
    _ => null,
  };
  return ElevatedButton.styleFrom(
    minimumSize: const Size(44, 44),
    backgroundColor: background,
    foregroundColor: background == null
        ? null
        : ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black,
  );
}

Color _accentColor(String value, ColorScheme colors) =>
    _hexColor(value) ?? colors.primary;

Color? _hexColor(String value) {
  final Match? match = RegExp(
    r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
  ).firstMatch(value);
  if (match == null) return null;
  final String hex = match.group(1)!;
  final int parsed = int.parse(hex, radix: 16);
  return Color(hex.length == 6 ? 0xff000000 | parsed : parsed);
}

String _linkedMarkdown(String label, String destination) {
  if (destination.isEmpty) return label;
  final String escaped = label.replaceAllMapped(
    RegExp(r'([\\`*_{}\[\]<>])'),
    (Match match) => '\\${match.group(0)}',
  );
  return '[$escaped](<$destination>)';
}
