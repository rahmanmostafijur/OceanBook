/// Plain-text editing of a ContentDoc (docs/architecture/08 §3). Authors write paragraphs separated by a
/// blank line and inline maths between dollar signs (`$x^2$`). Only documents that this format can
/// reproduce exactly are editable here; anything richer (images, lists, tables, bold, blanks, display
/// maths) returns null from [textFromDoc] so the editor never silently drops content.
library;

const _mathMarker = r'$';

/// True when [text] can be turned into a document: not blank and every `$` is paired.
bool isValidContentText(String text) => text.trim().isNotEmpty && _mathMarker.allMatches(text).length.isEven;

/// Builds a v1 ContentDoc from [text]. Call [isValidContentText] first.
Map<String, Object?> docFromText(String text) {
  final paragraphs = text.trim().split(RegExp(r'\n[ \t]*\n+')).map((p) => p.trim()).where((p) => p.isNotEmpty);
  return {
    'type': 'doc',
    'v': 1,
    'blocks': [
      for (final paragraph in paragraphs) {'type': 'paragraph', 'inlines': _inlines(paragraph)},
    ],
  };
}

List<Map<String, Object?>> _inlines(String paragraph) {
  final parts = paragraph.split(_mathMarker);
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty)
        if (i.isOdd) {'type': 'math', 'tex': parts[i], 'display': false} else {'type': 'text', 'text': parts[i]},
  ];
}

/// The editable text of [doc], or null when the document holds anything this format cannot express.
String? textFromDoc(Map<String, Object?>? doc) {
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
          buffer.write(text);
        case 'math':
          final tex = inline['tex'] as String? ?? '';
          if (inline['display'] == true || tex.contains(_mathMarker) || tex.isEmpty) return null;
          buffer
            ..write(_mathMarker)
            ..write(tex)
            ..write(_mathMarker);
        default:
          return null;
      }
    }
    paragraphs.add(buffer.toString());
  }
  return paragraphs.join('\n\n');
}
