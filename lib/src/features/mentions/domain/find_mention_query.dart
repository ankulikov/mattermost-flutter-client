import 'package:mattermost_flutter/src/features/mentions/domain/mention_query.dart';

const int _atSign = 0x40;
const int _fullwidthAtSign = 0xff20;
const int _objectReplacementCharacter = 0xfffc;

/// Finds an active mention query at a collapsed UTF-16 selection.
///
/// The parser intentionally accepts plain text and offsets rather than a
/// Flutter editing value, so it can be shared by any composer implementation.
MentionQuery? findMentionQuery({
  required String text,
  required int selectionStart,
  required int selectionEnd,
}) {
  if (selectionStart != selectionEnd ||
      selectionStart < 0 ||
      selectionStart > text.length) {
    return null;
  }
  final List<_CodePoint>? parsedPoints = _codePointsBefore(
    text,
    selectionStart,
  );
  if (parsedPoints == null) return null;
  final List<_CodePoint> points = parsedPoints;

  var triggerIndex = -1;
  for (var index = points.length - 1; index >= 0; index -= 1) {
    final _CodePoint point = points[index];
    if (_isTrigger(point.value)) {
      triggerIndex = index;
      break;
    }
    if (!_isTermCodePoint(point.value) && point.value != 0x20) return null;
  }
  if (triggerIndex < 0) return null;

  final _CodePoint trigger = points[triggerIndex];
  if (triggerIndex > 0 &&
      (!_isMentionBoundary(points[triggerIndex - 1].value) ||
          _isTrigger(points[triggerIndex - 1].value))) {
    return null;
  }
  if (triggerIndex + 1 < points.length &&
      points[triggerIndex + 1].value == _objectReplacementCharacter) {
    return null;
  }

  var previousWasSpace = false;
  for (var index = triggerIndex + 1; index < points.length; index += 1) {
    final int value = points[index].value;
    if (value == 0x20) {
      if (previousWasSpace) return null;
      previousWasSpace = true;
      continue;
    }
    if (!_isTermCodePoint(value)) return null;
    previousWasSpace = false;
  }

  final String term = text.substring(trigger.end, selectionStart);
  return MentionQuery(
    start: trigger.start,
    end: selectionStart,
    trigger: String.fromCharCode(trigger.value),
    term: term,
    key: normalizeMentionQueryKey(term),
  );
}

/// Produces the repository/cache key for a mention search term.
String normalizeMentionQueryKey(String term) {
  final StringBuffer result = StringBuffer();
  for (final int value in term.trim().toLowerCase().runes) {
    if (_isCombiningMark(value)) continue;
    result.write(_foldDiacritic(value));
  }
  return result.toString();
}

List<_CodePoint>? _codePointsBefore(String text, int end) {
  final List<_CodePoint> result = <_CodePoint>[];
  var offset = 0;
  for (final int value in text.runes) {
    if (offset == end) break;
    final int nextOffset = offset + (value > 0xffff ? 2 : 1);
    if (nextOffset > end) return null;
    result.add(_CodePoint(start: offset, end: nextOffset, value: value));
    offset = nextOffset;
  }
  return offset == end ? result : null;
}

bool _isTrigger(int value) => value == _atSign || value == _fullwidthAtSign;

bool _isMentionBoundary(int value) =>
    value == 0x20 ||
    value == 0x09 ||
    value == 0x0a ||
    value == 0x0d ||
    _isPunctuation(value);

bool _isPunctuation(int value) =>
    RegExp(r'^\p{P}$', unicode: true).hasMatch(String.fromCharCode(value));

bool _isTermCodePoint(int value) => RegExp(
  r'^[\p{L}\p{M}\p{N}._-]$',
  unicode: true,
).hasMatch(String.fromCharCode(value));

bool _isCombiningMark(int value) =>
    RegExp(r'^\p{M}$', unicode: true).hasMatch(String.fromCharCode(value));

String _foldDiacritic(int value) {
  if (value == 0xdf) return 'ss';
  final String character = String.fromCharCode(value);
  for (final MapEntry<String, String> entry in _diacriticGroups.entries) {
    if (entry.key.contains(character)) return entry.value;
  }
  return character;
}

const Map<String, String> _diacriticGroups = <String, String>{
  'àáâãäåāăąǎǟǡǻȁȃȧÀÁÂÃÄÅĀĂĄǍǞǠǺȀȂȦ': 'a',
  'çćĉċčÇĆĈĊČ': 'c',
  'ďđĎĐ': 'd',
  'èéêëēĕėęěȅȇȩÈÉÊËĒĔĖĘĚȄȆȨ': 'e',
  'ĝğġģĜĞĠĢ': 'g',
  'ĥħĤĦ': 'h',
  'ìíîïĩīĭįıǐȉȋÌÍÎÏĨĪĬĮİǏȈȊ': 'i',
  'ĵĴ': 'j',
  'ķĶ': 'k',
  'ĺļľŀłĹĻĽĿŁ': 'l',
  'ñńņňŉŋÑŃŅŇŊ': 'n',
  'òóôõöøōŏőǒǫǭȍȏȫȭȯȱÒÓÔÕÖØŌŎŐǑǪǬȌȎȪȬȮȰ': 'o',
  'ŕŗřŔŖŘ': 'r',
  'śŝşšŚŜŞŠ': 's',
  'ţťŧŢŤŦ': 't',
  'ùúûüũūŭůűųǔǖǘǚǜȕȗÙÚÛÜŨŪŬŮŰŲǓǕǗǙǛȔȖ': 'u',
  'ŵŴ': 'w',
  'ýÿŷÝŸŶ': 'y',
  'źżžŹŻŽ': 'z',
};

final class _CodePoint {
  const _CodePoint({
    required this.start,
    required this.end,
    required this.value,
  });

  final int start;
  final int end;
  final int value;
}
