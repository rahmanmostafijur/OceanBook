/// Plain-text editing of a ContentDoc (docs/architecture/08 §3). Authors write text with a few markers and
/// the editor turns it into the closed document model, and back, without losing anything:
///
/// * a blank line starts a new paragraph;
/// * `**bold**`, `*italic*`, `__underline__`, `~subscript~` and `^superscript^` (they may be combined);
/// * `$x^2$` is inline maths and `$$x^2$$` display maths;
/// * lines starting with `- `, `1. `, `i. ` or `ক. ` make a bullet, numbered, roman or Bangla-lettered list;
/// * lines starting with `|` make a table, cells separated by `|`;
/// * `[[1]]`, `[[2]]` are gaps in fill-in-the-blank questions (only with `allowBlanks`);
/// * a backslash writes the next character literally (`\*`, `\$`, `\\`).
///
/// Only documents this format can reproduce exactly are editable: [textFromDoc] returns null for anything
/// else (images, line breaks inside list items or table cells, unknown fields), so the editor never
/// silently drops content.
library;

final _blankMarker = RegExp(r'\[\[(\d+)\]\]');
final _blockSplit = RegExp(r'\n[ \t]*\n+');

const _escaped = r'\*~^$|_';
const _banglaLetters = 'কখগঘঙচছজঝঞটঠডঢণতথদধনপফবভমযরলশষসহ';
const _romanPairs = [(10, 'x'), (9, 'ix'), (5, 'v'), (4, 'iv'), (1, 'i')];
const _textKeys = {'type', 'text', 'bold', 'italic', 'underline', 'sub', 'sup'};
const _mathKeys = {'type', 'tex', 'display'};
const _blankKeys = {'type', 'index'};
const _flagMarks = [('bold', '**'), ('italic', '*'), ('underline', '__'), ('sub', '~'), ('sup', '^')];

final _listMarkers = {
  'bullet': RegExp(r'^- '),
  'decimal': RegExp(r'^\d+\. '),
  'roman': RegExp(r'^[ivxl]+\. '),
  'bangla': RegExp(r'^[ক-হ]\. '),
};

/// The gap numbers (counting from one) used in [text], in order of appearance.
List<int> blankNumbers(String text) => [for (final m in _blankMarker.allMatches(text)) int.parse(m.group(1)!)];

/// True when [text] is not blank and can be turned into a document: marks and `$` are paired and table
/// rows have the same number of cells.
bool isValidContentText(String text, {bool allowBlanks = false}) => _parse(text, allowBlanks) != null;

/// Builds a v1 ContentDoc from [text]. Call [isValidContentText] first.
Map<String, Object?> docFromText(String text, {bool allowBlanks = false}) {
  final doc = _parse(text, allowBlanks);
  if (doc == null) throw ArgumentError.value(text, 'text', 'not valid content text');
  return doc;
}

Map<String, Object?>? _parse(String text, bool allowBlanks) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final blocks = <Map<String, Object?>>[];
  for (final raw in trimmed.split(_blockSplit)) {
    final block = raw.trim();
    if (block.isEmpty) continue;
    final parsed = _parseBlock(block, allowBlanks);
    if (parsed == null) return null;
    blocks.add(parsed);
  }
  return {'type': 'doc', 'v': 1, 'blocks': blocks};
}

Map<String, Object?>? _parseBlock(String block, bool allowBlanks) {
  final lines = [for (final l in block.split('\n')) l.trim()];
  if (lines.every((l) => l.startsWith('|'))) return _parseTable(lines, allowBlanks);
  final style = _listMarkers.entries.where((e) => e.value.hasMatch(lines.first)).map((e) => e.key).firstOrNull;
  if (style != null && lines.every(_listMarkers[style]!.hasMatch)) {
    final items = <List<Map<String, Object?>>>[];
    for (final line in lines) {
      final inlines = _parseInlines(line.replaceFirst(_listMarkers[style]!, ''), allowBlanks);
      if (inlines == null) return null;
      items.add(inlines);
    }
    return {'type': 'list', 'style': style, 'items': items};
  }
  final inlines = _parseInlines(block, allowBlanks);
  return inlines == null ? null : {'type': 'paragraph', 'inlines': inlines};
}

Map<String, Object?>? _parseTable(List<String> lines, bool allowBlanks) {
  final rows = <List<List<Map<String, Object?>>>>[];
  for (final line in lines) {
    final cells = _splitCells(line.substring(1));
    if (cells.length > 1 && cells.last.trim().isEmpty) cells.removeLast(); // the closing |
    final row = <List<Map<String, Object?>>>[];
    for (final cell in cells) {
      final inlines = _parseInlines(cell.trim(), allowBlanks);
      if (inlines == null) return null;
      row.add(inlines);
    }
    rows.add(row);
  }
  if (rows.map((r) => r.length).toSet().length != 1) return null;
  return {'type': 'table', 'rows': rows};
}

List<String> _splitCells(String line) {
  final cells = <String>[];
  final cell = StringBuffer();
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == r'\' && i + 1 < line.length) {
      cell
        ..write(c)
        ..write(line[++i]);
    } else if (c == '|') {
      cells.add(cell.toString());
      cell.clear();
    } else {
      cell.write(c);
    }
  }
  return cells..add(cell.toString());
}

/// Index of the delimiter that closes maths opened before [start], or -1.
int _mathEnd(String s, int start, {required bool display}) {
  for (var j = start; j < s.length; j++) {
    if (s[j] == r'\') {
      j++;
    } else if (display ? s.startsWith(r'$$', j) : s[j] == r'$') {
      return j;
    }
  }
  return -1;
}

List<Map<String, Object?>>? _parseInlines(String s, bool allowBlanks) {
  final out = <Map<String, Object?>>[];
  final buffer = StringBuffer();
  final on = {for (final (flag, _) in _flagMarks) flag: false};
  void flush() {
    if (buffer.isEmpty) return;
    out.add({
      'type': 'text',
      'text': buffer.toString(),
      for (final e in on.entries)
        if (e.value) e.key: true,
    });
    buffer.clear();
  }

  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == r'\') {
      final next = i + 1 < s.length ? s[i + 1] : ' ';
      if (next.trim().isEmpty) {
        buffer.write(c);
        i++;
      } else {
        buffer.write(next);
        i += 2;
      }
      continue;
    }
    if (c == r'$') {
      final display = s.startsWith(r'$$', i);
      final width = display ? 2 : 1;
      final end = _mathEnd(s, i + width, display: display);
      final tex = end < 0 ? '' : s.substring(i + width, end).trim();
      if (tex.isEmpty) return null;
      flush();
      out.add({'type': 'math', 'tex': tex, 'display': display});
      i = end + width;
      continue;
    }
    final mark = _flagMarks.where((m) => s.startsWith(m.$2, i)).firstOrNull;
    if (mark != null) {
      flush();
      on[mark.$1] = !on[mark.$1]!;
      i += mark.$2.length;
      continue;
    }
    if (allowBlanks && c == '[') {
      final m = _blankMarker.matchAsPrefix(s, i);
      if (m != null) {
        final number = int.parse(m.group(1)!);
        if (number < 1) return null;
        flush();
        out.add({'type': 'blank', 'index': number - 1});
        i = m.end;
        continue;
      }
    }
    buffer.write(c);
    i++;
  }
  if (on.values.any((v) => v)) return null;
  flush();
  return out;
}

/// The editable text of [doc], or null when the document holds anything this format cannot express. A
/// missing document is the empty text.
String? textFromDoc(Map<String, Object?>? doc, {bool allowBlanks = false}) {
  if (doc == null) return '';
  final blocks = doc['blocks'];
  if (blocks is! List || blocks.isEmpty) return null;
  final parts = <String>[];
  for (final block in blocks) {
    final text = block is Map ? _blockText(block, allowBlanks) : null;
    if (text == null) return null;
    parts.add(text);
  }
  return parts.join('\n\n');
}

String? _blockText(Map<dynamic, dynamic> block, bool allowBlanks) {
  switch (block['type']) {
    case 'paragraph':
      final text = _inlinesText(block['inlines'], allowBlanks, multiline: true);
      return text == null ? null : _escapeLineStarts(text);
    case 'list':
      final style = block['style'] ?? 'bullet';
      final items = block['items'];
      if (style is! String || !_listMarkers.containsKey(style) || items is! List || items.isEmpty) return null;
      final lines = <String>[];
      for (final (i, item) in items.indexed) {
        final marker = _markerFor(style, i);
        final text = _inlinesText(item, allowBlanks, multiline: false);
        if (marker == null || text == null) return null;
        lines.add('$marker$text');
      }
      return lines.join('\n');
    case 'table':
      final rows = block['rows'];
      if (rows is! List || rows.isEmpty) return null;
      final lines = <String>[];
      for (final row in rows) {
        if (row is! List || row.isEmpty) return null;
        final cells = [for (final cell in row) _inlinesText(cell, allowBlanks, multiline: false)];
        if (cells.contains(null)) return null;
        lines.add('| ${cells.join(' | ')} |');
      }
      return lines.join('\n');
    default:
      return null;
  }
}

String? _markerFor(String style, int index) {
  switch (style) {
    case 'bullet':
      return '- ';
    case 'decimal':
      return '${index + 1}. ';
    case 'roman':
      final roman = _roman(index + 1);
      return roman == null ? null : '$roman. ';
    default:
      return index < _banglaLetters.length ? '${_banglaLetters[index]}. ' : null;
  }
}

/// Lower-case roman numeral up to 49 (the parser reads `i`, `v`, `x` and `l`).
String? _roman(int n) {
  if (n >= 50) return null;
  final buffer = StringBuffer();
  var rest = n;
  while (rest >= 40) {
    buffer.write('xl');
    rest -= 40;
  }
  for (final (value, symbol) in _romanPairs) {
    while (rest >= value) {
      buffer.write(symbol);
      rest -= value;
    }
  }
  return buffer.toString();
}

/// A line that would read as a list marker or table row is written with a backslash in front.
String _escapeLineStarts(String text) => text
    .split('\n')
    .map((line) {
      final trimmed = line.trimLeft();
      final marked = _listMarkers.values.any((m) => m.hasMatch(trimmed)) || trimmed.startsWith('|');
      return marked ? '${line.substring(0, line.length - trimmed.length)}\\$trimmed' : line;
    })
    .join('\n');

String _escape(String text, bool allowBlanks) {
  final buffer = StringBuffer();
  for (final unit in text.runes) {
    final c = String.fromCharCode(unit);
    if (_escaped.contains(c) || (allowBlanks && c == '[')) buffer.write(r'\');
    buffer.write(c);
  }
  return buffer.toString();
}

String? _inlinesText(Object? inlines, bool allowBlanks, {required bool multiline}) {
  if (inlines is! List) return null;
  final buffer = StringBuffer();
  for (final inline in _mergeText(inlines)) {
    if (inline is! Map) return null;
    switch (inline['type']) {
      case 'text':
        if (inline.keys.any((k) => !_textKeys.contains(k))) return null;
        final text = inline['text'];
        if (text is! String || (!multiline && text.contains('\n'))) return null;
        if (text.isEmpty) continue;
        final marks = [
          for (final (flag, mark) in _flagMarks)
            if (inline[flag] == true) mark,
        ];
        buffer
          ..writeAll(marks)
          ..write(_escape(text, allowBlanks))
          ..writeAll(marks.reversed);
      case 'math':
        final tex = inline['tex'];
        if (inline.keys.any((k) => !_mathKeys.contains(k))) return null;
        if (tex is! String || tex.trim().isEmpty || tex != tex.trim() || !_texIsSafe(tex)) return null;
        final delimiter = inline['display'] == true ? r'$$' : r'$';
        buffer.write('$delimiter$tex$delimiter');
      case 'blank':
        final index = inline['index'];
        if (!allowBlanks || index is! int || inline.keys.any((k) => !_blankKeys.contains(k))) return null;
        buffer.write('[[${index + 1}]]');
      default:
        return null;
    }
  }
  return buffer.toString();
}

/// Joins neighbouring text pieces with the same formatting so their marks never touch.
List<Object?> _mergeText(List<Object?> inlines) {
  final merged = <Object?>[];
  for (final inline in inlines) {
    final last = merged.isEmpty ? null : merged.last;
    if (inline is Map &&
        last is Map &&
        inline['type'] == 'text' &&
        last['type'] == 'text' &&
        inline['text'] is String &&
        last['text'] is String &&
        _sameFlags(inline, last)) {
      merged[merged.length - 1] = {...last, 'text': '${last['text']}${inline['text']}'};
    } else {
      merged.add(inline);
    }
  }
  return merged;
}

bool _sameFlags(Map<dynamic, dynamic> a, Map<dynamic, dynamic> b) =>
    _flagMarks.every((m) => (a[m.$1] == true) == (b[m.$1] == true));

/// TeX that can sit between dollar signs: every `$` is escaped and it does not end in a lone backslash.
bool _texIsSafe(String tex) {
  for (var i = 0; i < tex.length; i++) {
    if (tex[i] == r'\') {
      if (i + 1 >= tex.length) return false;
      i++;
    } else if (tex[i] == r'$') {
      return false;
    }
  }
  return true;
}
