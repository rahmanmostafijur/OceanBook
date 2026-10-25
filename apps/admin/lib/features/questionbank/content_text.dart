/// Plain-text editing of a ContentDoc (docs/architecture/08 §3). Authors write paragraphs separated by a
/// blank line and inline maths between dollar signs (`$x^2$`). Only documents that this format can
/// reproduce exactly are editable here; anything richer (images, lists, tables, bold, blanks, display
/// maths) returns null from [textFromDoc] so the editor never silently drops content.
library;

const _mathMarker = r'$';

/// A gap for fill-in-the-blank questions, written `[[1]]`, `[[2]]`, ... (counting from one).
final _blankMarker = RegExp(r'\[\[(\d+)\]\]');

/// The gap numbers (counting from one) used in [text], in order of appearance.
List<int> blankNumbers(String text) => [for (final m in _blankMarker.allMatches(text)) int.parse(m.group(1)!)];

/// True when [text] can be turned into a document: not blank and every `$` is paired.
bool isValidContentText(String text) => text.trim().isNotEmpty && _mathMarker.allMatches(text).length.isEven;

/// Builds a v1 ContentDoc from [text]. Call [isValidContentText] first. With [allowBlanks], `[[n]]` becomes a
/// blank (index n - 1); without it the same characters stay ordinary text.
Map<String, Object?> docFromText(String text, {bool allowBlanks = false}) {
  final paragraphs = text.trim().split(RegExp(r'\n[ \t]*\n+')).map((p) => p.trim()).where((p) => p.isNotEmpty);
  return {
    'type': 'doc',
    'v': 1,
    'blocks': [
      for (final paragraph in paragraphs) {'type': 'paragraph', 'inlines': _inlines(paragraph, allowBlanks)},
    ],
  };
}

List<Map<String, Object?>> _inlines(String paragraph, bool allowBlanks) {
  final parts = paragraph.split(_mathMarker);
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty)
        if (i.isOdd) {'type': 'math', 'tex': parts[i], 'display': false} else ..._textInlines(parts[i], allowBlanks),
  ];
}

List<Map<String, Object?>> _textInlines(String text, bool allowBlanks) {
  if (!allowBlanks) {
    return [
      {'type': 'text', 'text': text},
    ];
  }
  final inlines = <Map<String, Object?>>[];
  var start = 0;
  for (final m in _blankMarker.allMatches(text)) {
    if (m.start > start) inlines.add({'type': 'text', 'text': text.substring(start, m.start)});
    inlines.add({'type': 'blank', 'index': int.parse(m.group(1)!) - 1});
    start = m.end;
  }
  if (start < text.length) inlines.add({'type': 'text', 'text': text.substring(start)});
  return inlines;
}

/// The editable text of [doc], or null when the document holds anything this format cannot express. Blanks
/// are expressible only with [allowBlanks] (and then text that already looks like a blank is not).
String? textFromDoc(Map<String, Object?>? doc, {bool allowBlanks = false}) {
  if (doc == null) return '';
  final blocks = doc['blocks'];
  if (blocks is! List || blocks.isEmpty) return null;
  final paragraphs = <String>[];
  for (final block in blocks) {
    if (block is! Map || block['type'] != 'paragraph') return null;
    final buffer = StringBuffer();
    for (final inline in (block['inlines'] as List? ?? const <Object?>[])) {
      if (inline is! Map) return null;
      switch (inline['type']) {
        case 'text':
          final text = inline['text'] as String? ?? '';
          final formatted = ['bold', 'italic', 'sub', 'sup', 'underline'].any((k) => inline[k] == true);
          if (formatted || text.contains(_mathMarker)) return null;
          if (allowBlanks && _blankMarker.hasMatch(text)) return null;
          buffer.write(text);
        case 'math':
          final tex = inline['tex'] as String? ?? '';
          if (inline['display'] == true || tex.contains(_mathMarker) || tex.isEmpty) return null;
          buffer
            ..write(_mathMarker)
            ..write(tex)
            ..write(_mathMarker);
        case 'blank':
          final index = inline['index'];
          if (!allowBlanks || index is! int) return null;
          buffer.write('[[${index + 1}]]');
        default:
          return null;
      }
    }
    paragraphs.add(buffer.toString());
  }
  return paragraphs.join('\n\n');
}
