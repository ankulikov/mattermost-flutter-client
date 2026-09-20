import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment_option.dart';
import 'package:mattermost_flutter/src/ui/messages/post_action_controller.dart';
import 'package:mattermost_flutter/src/ui/messages/rich_attachment_strings.dart';

Future<String?> showSystemSelectPicker({
  required BuildContext context,
  required String title,
  required RichAttachmentSelectDataSource dataSource,
}) => showDialog<String>(
  context: context,
  builder: (BuildContext context) =>
      _SystemSelectDialog(title: title, dataSource: dataSource),
);

class _SystemSelectDialog extends ConsumerStatefulWidget {
  const _SystemSelectDialog({required this.title, required this.dataSource});

  final String title;
  final RichAttachmentSelectDataSource dataSource;

  @override
  ConsumerState<_SystemSelectDialog> createState() =>
      _SystemSelectDialogState();
}

class _SystemSelectDialogState extends ConsumerState<_SystemSelectDialog> {
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final RichAttachmentOptionSearchRequest request = (
      dataSource: widget.dataSource,
      query: _query,
    );
    final AsyncValue<List<RichAttachmentSystemOption>> options = ref.watch(
      richAttachmentOptionsProvider(request),
    );
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(
          children: <Widget>[
            TextField(
              autofocus: true,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: RichAttachmentStrings.search,
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: options.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace stackTrace) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(RichAttachmentStrings.optionsFailed),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(
                          richAttachmentOptionsProvider(request),
                        ),
                        child: const Text(RichAttachmentStrings.retry),
                      ),
                    ],
                  ),
                ),
                data: (List<RichAttachmentSystemOption> values) =>
                    values.isEmpty
                    ? const Center(child: Text(RichAttachmentStrings.noOptions))
                    : ListView.builder(
                        itemCount: values.length,
                        itemBuilder: (BuildContext context, int index) {
                          final RichAttachmentSystemOption option =
                              values[index];
                          return Semantics(
                            button: true,
                            label: option.description.isEmpty
                                ? option.label
                                : '${option.label}, ${option.description}',
                            child: ListTile(
                              title: Text(option.label),
                              subtitle: option.description.isEmpty
                                  ? null
                                  : Text(option.description),
                              onTap: () =>
                                  Navigator.of(context).pop(option.value),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(RichAttachmentStrings.close),
        ),
      ],
    );
  }
}
