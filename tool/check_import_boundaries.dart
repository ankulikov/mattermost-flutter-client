import 'dart:convert';
import 'dart:io';

const _targetRoots = ['lib/src/data/', 'lib/src/domain/', 'lib/src/ui/'];

void main() {
  final allowlist = _readAllowlist();
  final violations = <String>[];

  for (final file
      in Directory('lib/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.dart') && !file.path.endsWith('.g.dart'),
          )) {
    final path = _normalize(file.path);
    if (!_targetRoots.any(path.startsWith) || _isLegacy(path, allowlist)) {
      continue;
    }

    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final match = RegExp(
        r"^(?:import|export) '([^']+)'",
      ).firstMatch(lines[index]);
      if (match == null) {
        continue;
      }

      final import = match.group(1)!;
      final rule = _violatedRule(path, import);
      if (rule != null && !_isException(path, import, allowlist)) {
        violations.add('$path:${index + 1}: $rule: $import');
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln(violations.join('\n'));
    exitCode = 1;
  }
}

_Allowlist _readAllowlist() {
  final source = File('tool/import_boundary_allowlist.json').readAsStringSync();
  final json = jsonDecode(source) as Map<String, dynamic>;
  final prefixes = (json['legacySourcePrefixes'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map((entry) => entry['prefix']! as String)
      .toSet();
  final exceptions = (json['exceptions'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(
        (entry) => (
          source: entry['source']! as String,
          import: entry['import']! as String,
        ),
      )
      .toSet();

  for (final prefix in prefixes) {
    if (_targetRoots.any(prefix.startsWith)) {
      throw FormatException('Target layers cannot be allowlisted: $prefix');
    }
  }
  for (final exception in exceptions) {
    if (exception.source.contains('*') || exception.import.contains('*')) {
      throw FormatException('Allowlist exceptions must be exact paths');
    }
  }

  return _Allowlist(prefixes, exceptions);
}

bool _isLegacy(String path, _Allowlist allowlist) =>
    allowlist.legacySourcePrefixes.any(path.startsWith);

bool _isException(String path, String import, _Allowlist allowlist) =>
    allowlist.exceptions.contains((source: path, import: import));

String? _violatedRule(String path, String import) {
  if (path.startsWith('lib/src/domain/')) {
    if (import.startsWith('package:flutter/') ||
        import.startsWith('package:flutter_riverpod/') ||
        import.startsWith('package:dio/') ||
        import.startsWith('package:drift/') ||
        import.contains('/src/data/') ||
        import.contains('/src/ui/') ||
        import.contains('/dto/')) {
      return 'domain must not depend on framework, data, UI, or DTOs';
    }
  }

  if (path.startsWith('lib/src/data/') && import.contains('/src/ui/')) {
    return 'data must not import UI';
  }

  if (path.startsWith('lib/src/ui/core/') &&
      (import.contains('/src/domain/') ||
          import.contains('/src/data/') ||
          import.contains('/src/features/') ||
          import.contains('/src/app/di/'))) {
    return 'ui/core must remain independent of product layers';
  }

  if (path.startsWith('lib/src/ui/') &&
      !path.startsWith('lib/src/ui/core/') &&
      (import.startsWith('package:dio/') ||
          import.contains('/src/data/api/') ||
          import.contains('/src/data/database/') ||
          import.contains('/src/data/cache/') ||
          import.contains('/src/data/storage/') ||
          import.contains('/src/data/repositories/') ||
          import.contains('/src/data/mappers/') ||
          import.contains('/src/data/platform/') ||
          import.contains('/src/data/realtime/') ||
          import.contains('/dto/'))) {
    return 'UI may depend only on domain and public data providers';
  }

  return null;
}

String _normalize(String path) => path.replaceAll('\\', '/');

class _Allowlist {
  const _Allowlist(this.legacySourcePrefixes, this.exceptions);

  final Set<String> legacySourcePrefixes;
  final Set<({String source, String import})> exceptions;
}
