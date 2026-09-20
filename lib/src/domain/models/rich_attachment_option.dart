/// One display-safe value returned for a system-backed attachment select.
final class RichAttachmentSystemOption {
  const RichAttachmentSystemOption({
    required this.value,
    required this.label,
    this.description = '',
  });

  /// Mattermost user or channel ID sent back as `selected_option`.
  final String value;
  final String label;
  final String description;
}
