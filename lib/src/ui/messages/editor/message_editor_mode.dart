/// Controls whether the message editor presents Markdown syntax or its preview.
enum MessageEditorMode {
  /// Shows completed Markdown constructs without their inactive markers.
  livePreview,

  /// Shows the editing buffer exactly as it will be serialized.
  source,
}
