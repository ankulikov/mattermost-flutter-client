import 'package:flutter/material.dart';

/// Formats byte counts with the same units used by posted file attachments.
String formatAttachmentFileSize(int bytes) {
  if (bytes < 0) return '?';
  if (bytes < 1024) return '$bytes B';
  final double kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(0)} KB';
  final double megabytes = kilobytes / 1024;
  if (megabytes < 1024) return '${megabytes.toStringAsFixed(1)} MB';
  return '${(megabytes / 1024).toStringAsFixed(1)} GB';
}

/// Selects the standard attachment icon for a file extension.
IconData attachmentFileIcon(String? extension) => switch (extension
    ?.replaceFirst('.', '')
    .toLowerCase()) {
  'pdf' => Icons.picture_as_pdf_outlined,
  'doc' || 'docx' => Icons.description_outlined,
  'xls' || 'xlsx' => Icons.table_chart_outlined,
  'ppt' || 'pptx' => Icons.slideshow_outlined,
  'png' ||
  'jpg' ||
  'jpeg' ||
  'gif' ||
  'bmp' ||
  'webp' ||
  'heic' ||
  'heif' ||
  'tif' ||
  'tiff' ||
  'svg' => Icons.image_outlined,
  'zip' || 'tar' || 'gz' || '7z' => Icons.folder_zip_outlined,
  'mp3' || 'wav' || 'ogg' => Icons.audio_file_outlined,
  'mp4' || 'mov' || 'webm' => Icons.video_file_outlined,
  'html' || 'htm' || 'js' || 'dart' || 'json' || 'xml' => Icons.code_outlined,
  _ => Icons.insert_drive_file_outlined,
};
