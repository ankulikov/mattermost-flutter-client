import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/repositories/attachment_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/attachment_strings.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class MessageAttachments extends ConsumerWidget {
  const MessageAttachments({required this.attachments, super.key});

  final List<PostAttachment> attachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final List<PostAttachment> images = attachments
        .where((PostAttachment attachment) => attachment.isImage)
        .toList(growable: false);
    if (attachments.length == 1 && images.length == 1) {
      return _LargeImageAttachment(
        attachment: images.single,
        onOpen: () => _openViewer(context, images, 0),
      );
    }
    return Semantics(
      label: AttachmentStrings.attachments,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final PostAttachment attachment in attachments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AttachmentCard(
                attachment: attachment,
                onPressed: attachment.isImage
                    ? () => _openViewer(
                        context,
                        images,
                        images.indexOf(attachment),
                      )
                    : () => unawaited(_download(context, ref, attachment)),
              ),
            ),
        ],
      ),
    );
  }

  void _openViewer(
    BuildContext context,
    List<PostAttachment> images,
    int initialIndex,
  ) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) =>
              AttachmentImageViewer(images: images, initialIndex: initialIndex),
        ),
      ),
    );
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    PostAttachment attachment,
  ) async {
    try {
      final bool saved = await ref
          .read(attachmentRepositoryProvider)
          .download(attachment);
      if (!saved) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AttachmentStrings.downloadSucceeded)),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AttachmentStrings.downloadFailed)),
      );
    }
  }
}

class _LargeImageAttachment extends StatelessWidget {
  const _LargeImageAttachment({required this.attachment, required this.onOpen});

  final PostAttachment attachment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final double width = constraints.maxWidth.clamp(160, 720);
      final double sourceRatio = attachment.width > 0 && attachment.height > 0
          ? attachment.width / attachment.height
          : 16 / 9;
      final double height = (width / sourceRatio).clamp(160, 480);
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          button: true,
          image: true,
          label: attachment.name,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: height),
            child: AspectRatio(
              aspectRatio: width / height,
              child: Material(
                key: ValueKey<String>('large-attachment-${attachment.id}'),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: onOpen,
                  child: _AttachmentImage(
                    attachment: attachment,
                    variant: attachment.hasPreviewImage
                        ? AttachmentVariant.preview
                        : AttachmentVariant.original,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.attachment, required this.onPressed});

  final PostAttachment attachment;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640, minHeight: 96),
      child: Material(
        key: ValueKey<String>('attachment-card-${attachment.id}'),
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: 68,
                  child: attachment.isImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: _AttachmentImage(
                            attachment: attachment,
                            variant: attachment.hasPreviewImage
                                ? AttachmentVariant.thumbnail
                                : AttachmentVariant.original,
                            fit: BoxFit.cover,
                          ),
                        )
                      : _FileIcon(extension: attachment.extension),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        attachment.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _fileDescription(attachment),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  attachment.isImage
                      ? Icons.open_in_full
                      : Icons.download_outlined,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.extension});

  final String extension;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: Icon(
        _iconForExtension(extension),
        size: 34,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    ),
  );

  IconData _iconForExtension(String extension) => switch (extension
      .toLowerCase()) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'zip' || 'tar' || 'gz' || '7z' => Icons.folder_zip_outlined,
    'mp3' || 'wav' || 'ogg' => Icons.audio_file_outlined,
    'mp4' || 'mov' || 'webm' => Icons.video_file_outlined,
    'html' || 'htm' || 'js' || 'dart' || 'json' || 'xml' => Icons.code_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

class _AttachmentImage extends ConsumerWidget {
  const _AttachmentImage({
    required this.attachment,
    required this.variant,
    required this.fit,
  });

  final PostAttachment attachment;
  final AttachmentVariant variant;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AttachmentContentRequest request = (
      fileId: attachment.id,
      variant: variant,
    );
    final AsyncValue<AttachmentContent> content = ref.watch(
      attachmentContentProvider(request),
    );
    return content.when(
      data: (AttachmentContent value) => Image.memory(
        value.bytes,
        fit: fit,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => _ImageError(
          onRetry: () => ref.invalidate(attachmentContentProvider(request)),
        ),
      ),
      loading: () => const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) => _ImageError(
        onRetry: () => ref.invalidate(attachmentContentProvider(request)),
      ),
    );
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: IconButton(
      tooltip: AttachmentStrings.imageLoadFailed,
      onPressed: onRetry,
      icon: const Icon(Icons.broken_image_outlined),
    ),
  );
}

class AttachmentImageViewer extends ConsumerStatefulWidget {
  const AttachmentImageViewer({
    required this.images,
    required this.initialIndex,
    super.key,
  });

  final List<PostAttachment> images;
  final int initialIndex;

  @override
  ConsumerState<AttachmentImageViewer> createState() =>
      _AttachmentImageViewerState();
}

class _AttachmentImageViewerState extends ConsumerState<AttachmentImageViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _isDownloading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PostAttachment current = widget.images[_index];
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NextImageIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _CloseViewerIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PreviousImageIntent: CallbackAction<_PreviousImageIntent>(
            onInvoke: (_) => _showPrevious(),
          ),
          _NextImageIntent: CallbackAction<_NextImageIntent>(
            onInvoke: (_) => _showNext(),
          ),
          _CloseViewerIntent: CallbackAction<_CloseViewerIntent>(
            onInvoke: (_) => Navigator.of(context).maybePop(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: const ValueKey<String>('attachment-image-viewer'),
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              title: Text(current.name, overflow: TextOverflow.ellipsis),
              centerTitle: false,
              actions: <Widget>[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      AttachmentStrings.imagePosition(
                        _index + 1,
                        widget.images.length,
                      ),
                    ),
                  ),
                ),
                if (_isDownloading)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: AttachmentStrings.download,
                    onPressed: () => unawaited(_download(current)),
                    icon: const Icon(Icons.download_outlined),
                  ),
                IconButton(
                  tooltip: AttachmentStrings.close,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            body: Stack(
              children: <Widget>[
                PageView.builder(
                  controller: _controller,
                  itemCount: widget.images.length,
                  onPageChanged: (int value) => setState(() => _index = value),
                  itemBuilder: (BuildContext context, int index) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: _AttachmentImage(
                      attachment: widget.images[index],
                      variant: AttachmentVariant.original,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (_index > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton.filledTonal(
                      tooltip: AttachmentStrings.previousImage,
                      onPressed: _showPrevious,
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ),
                if (_index + 1 < widget.images.length)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton.filledTonal(
                      tooltip: AttachmentStrings.nextImage,
                      onPressed: _showNext,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPrevious() {
    if (_index == 0) return;
    unawaited(
      _controller.previousPage(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      ),
    );
  }

  void _showNext() {
    if (_index + 1 >= widget.images.length) return;
    unawaited(
      _controller.nextPage(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      ),
    );
  }

  Future<void> _download(PostAttachment attachment) async {
    setState(() => _isDownloading = true);
    try {
      final bool saved = await ref
          .read(attachmentRepositoryProvider)
          .download(attachment);
      if (!saved) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AttachmentStrings.downloadSucceeded)),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AttachmentStrings.downloadFailed)),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }
}

final class _PreviousImageIntent extends Intent {
  const _PreviousImageIntent();
}

final class _NextImageIntent extends Intent {
  const _NextImageIntent();
}

final class _CloseViewerIntent extends Intent {
  const _CloseViewerIntent();
}

String _fileDescription(PostAttachment attachment) {
  final String type = attachment.extension.isEmpty
      ? (attachment.mimeType.isEmpty ? 'FILE' : attachment.mimeType)
      : attachment.extension.toUpperCase();
  return '$type ${_formatFileSize(attachment.size)}';
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final double kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(0)} KB';
  final double megabytes = kilobytes / 1024;
  if (megabytes < 1024) return '${megabytes.toStringAsFixed(1)} MB';
  return '${(megabytes / 1024).toStringAsFixed(1)} GB';
}
