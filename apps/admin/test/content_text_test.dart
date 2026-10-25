import 'package:flutter_test/flutter_test.dart';
import 'package:oceanbook_admin/features/questionbank/content_text.dart';

void main() {
  group('docFromText', () {
    test('splits paragraphs on a blank line and keeps single newlines inside a paragraph', () {
      final doc = docFromText('প্রথম\nলাইন\n\nদ্বিতীয়');
      final blocks = doc['blocks']! as List;
      expect(blocks, hasLength(2));
      expect(((blocks[0] as Map)['inlines'] as List).first, {'type': 'text', 'text': 'প্রথম\nলাইন'});
    });

    test('turns dollar-delimited segments into inline maths', () {
      final doc = docFromText(r'If $x^2=4$ then x is');
      final inlines = ((doc['blocks']! as List).single as Map)['inlines']! as List;
      expect(inlines, [
        {'type': 'text', 'text': 'If '},
        {'type': 'math', 'tex': 'x^2=4', 'display': false},
        {'type': 'text', 'text': ' then x is'},
      ]);
    });
  });

  group('isValidContentText', () {
    test('rejects blank text and unpaired dollar signs', () {
      expect(isValidContentText('  \n '), isFalse);
      expect(isValidContentText(r'cost is $5'), isFalse);
      expect(isValidContentText(r'$a$ and $b$'), isTrue);
    });
  });

  group('textFromDoc', () {
    test('round-trips what docFromText produced', () {
      const text = 'আলোর বেগ\n\nহলো \$c\$ মিটার';
      expect(textFromDoc(docFromText(text)), text);
    });

    test('returns null for content the format cannot reproduce', () {
      Map<String, Object?> para(List<Map<String, Object?>> inlines) => {
        'blocks': [
          {'type': 'paragraph', 'inlines': inlines},
        ],
      };
      expect(
        textFromDoc({
          'blocks': [
            {'type': 'image', 'asset_id': 'a', 'alt': 'x'},
          ],
        }),
        isNull,
      );
      expect(
        textFromDoc(
          para([
            {'type': 'text', 'text': 'bold', 'bold': true},
          ]),
        ),
        isNull,
      );
      expect(
        textFromDoc(
          para([
            {'type': 'math', 'tex': 'x', 'display': true},
          ]),
        ),
        isNull,
      );
      expect(
        textFromDoc(
          para([
            {'type': 'blank', 'index': 0},
          ]),
        ),
        isNull,
      );
      expect(
        textFromDoc(
          para([
            {'type': 'text', 'text': r'costs $5'},
          ]),
        ),
        isNull,
      );
    });

    test('a missing optional document is an empty text', () {
      expect(textFromDoc(null), '');
    });
  });

  group('blanks', () {
    test('turn [[n]] into blank inlines only when allowed', () {
      final inlines = ((docFromText('a [[1]] b', allowBlanks: true)['blocks']! as List).single as Map)['inlines']!;
      expect(inlines, [
        {'type': 'text', 'text': 'a '},
        {'type': 'blank', 'index': 0},
        {'type': 'text', 'text': ' b'},
      ]);
      final plain = ((docFromText('a [[1]] b')['blocks']! as List).single as Map)['inlines']!;
      expect(plain, [
        {'type': 'text', 'text': 'a [[1]] b'},
      ]);
    });

    test('round-trip through textFromDoc, and are refused without allowBlanks', () {
      final doc = docFromText(r'x [[1]] and $y$ [[2]]', allowBlanks: true);
      expect(textFromDoc(doc, allowBlanks: true), r'x [[1]] and $y$ [[2]]');
      expect(textFromDoc(doc), isNull);
    });

    test('text that already looks like a gap marker is not editable as a blank question', () {
      final doc = docFromText('literal [[1]]');
      expect(textFromDoc(doc), 'literal [[1]]');
      expect(textFromDoc(doc, allowBlanks: true), isNull);
    });

    test('blankNumbers lists the markers in order', () {
      expect(blankNumbers('[[2]] and [[1]] and [[2]]'), [2, 1, 2]);
    });
  });
}
