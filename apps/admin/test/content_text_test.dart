import 'package:flutter_test/flutter_test.dart';
import 'package:oceanbook_admin/features/questionbank/content_text.dart';

List<Object?> _blocks(String text, {bool allowBlanks = false}) =>
    docFromText(text, allowBlanks: allowBlanks)['blocks']! as List<Object?>;

List<Object?> _inlines(String text, {bool allowBlanks = false}) =>
    (_blocks(text, allowBlanks: allowBlanks).single as Map)['inlines']! as List<Object?>;

/// Text, to a document, back to text, back to a document: the text may be normalised but the document
/// must come back exactly.
void _expectStable(String text, {bool allowBlanks = false}) {
  final doc = docFromText(text, allowBlanks: allowBlanks);
  final again = textFromDoc(doc, allowBlanks: allowBlanks);
  expect(again, isNotNull, reason: text);
  expect(docFromText(again!, allowBlanks: allowBlanks), doc, reason: '$text -> $again');
}

void main() {
  group('docFromText', () {
    test('splits paragraphs on a blank line and keeps single newlines inside a paragraph', () {
      final blocks = _blocks('প্রথম\nলাইন\n\nদ্বিতীয়');
      expect(blocks, hasLength(2));
      expect(((blocks[0] as Map)['inlines'] as List).first, {'type': 'text', 'text': 'প্রথম\nলাইন'});
    });

    test('turns dollar-delimited segments into inline maths and double dollars into display maths', () {
      expect(_inlines(r'If $x^2=4$ then $$y$$ is'), [
        {'type': 'text', 'text': 'If '},
        {'type': 'math', 'tex': 'x^2=4', 'display': false},
        {'type': 'text', 'text': ' then '},
        {'type': 'math', 'tex': 'y', 'display': true},
        {'type': 'text', 'text': ' is'},
      ]);
    });

    test('formats text with marks that may be combined', () {
      expect(_inlines('a **b** *c* __d__ H~2~O x^2^ ***e***'), [
        {'type': 'text', 'text': 'a '},
        {'type': 'text', 'text': 'b', 'bold': true},
        {'type': 'text', 'text': ' '},
        {'type': 'text', 'text': 'c', 'italic': true},
        {'type': 'text', 'text': ' '},
        {'type': 'text', 'text': 'd', 'underline': true},
        {'type': 'text', 'text': ' H'},
        {'type': 'text', 'text': '2', 'sub': true},
        {'type': 'text', 'text': 'O x'},
        {'type': 'text', 'text': '2', 'sup': true},
        {'type': 'text', 'text': ' '},
        {'type': 'text', 'text': 'e', 'bold': true, 'italic': true},
      ]);
    });

    test('a backslash writes the next character literally', () {
      expect(_inlines(r'2 \* 3 costs \$5 and C:\\dir \| \_'), [
        {'type': 'text', 'text': r'2 * 3 costs $5 and C:\dir | _'},
      ]);
    });

    test('lists take their style from the first marker', () {
      expect(_blocks('- a\n- **b**'), [
        {
          'type': 'list',
          'style': 'bullet',
          'items': [
            [
              {'type': 'text', 'text': 'a'},
            ],
            [
              {'type': 'text', 'text': 'b', 'bold': true},
            ],
          ],
        },
      ]);
      expect(((_blocks('1. a\n2. b').single as Map))['style'], 'decimal');
      expect(((_blocks('i. a\nii. b').single as Map))['style'], 'roman');
      expect(((_blocks('ক. এক\nখ. দুই').single as Map))['style'], 'bangla');
    });

    test('a block that mixes markers stays a paragraph', () {
      expect((_blocks('- a\n1. b').single as Map)['type'], 'paragraph');
    });

    test('tables have one row per line and optional outer pipes', () {
      expect(_blocks('| a | b |\n| c | \$x\$ |').single, {
        'type': 'table',
        'rows': [
          [
            [
              {'type': 'text', 'text': 'a'},
            ],
            [
              {'type': 'text', 'text': 'b'},
            ],
          ],
          [
            [
              {'type': 'text', 'text': 'c'},
            ],
            [
              {'type': 'math', 'tex': 'x', 'display': false},
            ],
          ],
        ],
      });
      expect(((_blocks('| a | b\n| c | d').single as Map)['rows'] as List), hasLength(2));
    });
  });

  group('isValidContentText', () {
    test('rejects blank text, unpaired dollars and unbalanced marks', () {
      expect(isValidContentText('  \n '), isFalse);
      expect(isValidContentText(r'cost is $5'), isFalse);
      expect(isValidContentText('an **open mark'), isFalse);
      expect(isValidContentText(r'$ $'), isFalse);
      expect(isValidContentText(r'$a$ and $b$'), isTrue);
      expect(isValidContentText(r'cost is \$5'), isTrue);
    });

    test('rejects tables whose rows differ in length', () {
      expect(isValidContentText('| a | b |\n| c |'), isFalse);
      expect(isValidContentText('| a | b |\n| c | d |'), isTrue);
    });
  });

  group('textFromDoc', () {
    test('round-trips what docFromText produced', () {
      const text = 'আলোর বেগ\n\nহলো \$c\$ মিটার';
      expect(textFromDoc(docFromText(text)), text);
    });

    test('round-trips every kind of block exactly', () {
      const texts = [
        r'**bold** *italic* __under__ H~2~O x^2^ ***both***',
        r'$a$ and $$b$$',
        '- one\n- two',
        '1. one\n2. two\n3. three',
        'i. one\nii. two\niii. three\niv. four',
        'ক. এক\nখ. দুই',
        '| a | b |\n| c | d |',
        '| **a** | \$x\$ |\n|  | d |',
        'text\n\n- list\n\n| t |\n\nmore',
        r'2 \* 3 and C:\\dir and \| and \_',
        '\\- not a list\nsecond line',
      ];
      for (final text in texts) {
        _expectStable(text);
      }
    });

    test('keeps adjacent pieces with the same formatting apart from their neighbours', () {
      final doc = {
        'blocks': [
          {
            'type': 'paragraph',
            'inlines': [
              {'type': 'text', 'text': 'a', 'italic': true},
              {'type': 'text', 'text': 'b', 'italic': true},
              {'type': 'text', 'text': 'c', 'bold': true},
              {'type': 'text', 'text': 'd', 'italic': true},
            ],
          },
        ],
      };
      final text = textFromDoc(doc)!;
      expect(text, '*ab***c***d*');
      expect(_inlines(text), [
        {'type': 'text', 'text': 'ab', 'italic': true},
        {'type': 'text', 'text': 'c', 'bold': true},
        {'type': 'text', 'text': 'd', 'italic': true},
      ]);
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
            {'type': 'blank', 'index': 0},
          ]),
        ),
        isNull,
      );
      expect(
        textFromDoc(
          para([
            {'type': 'text', 'text': 'x', 'colour': 'red'},
          ]),
        ),
        isNull,
      );
      expect(
        textFromDoc(
          para([
            {'type': 'math', 'tex': r'a$b', 'display': false},
          ]),
        ),
        isNull,
      );
      expect(
        textFromDoc({
          'blocks': [
            {
              'type': 'list',
              'style': 'bullet',
              'items': [
                [
                  {'type': 'text', 'text': 'two\nlines'},
                ],
              ],
            },
          ],
        }),
        isNull,
      );
    });

    test('a missing optional document is an empty text', () {
      expect(textFromDoc(null), '');
    });
  });

  group('blanks', () {
    test('turn [[n]] into blank inlines only when allowed', () {
      expect(_inlines('a [[1]] b', allowBlanks: true), [
        {'type': 'text', 'text': 'a '},
        {'type': 'blank', 'index': 0},
        {'type': 'text', 'text': ' b'},
      ]);
      expect(_inlines('a [[1]] b'), [
        {'type': 'text', 'text': 'a [[1]] b'},
      ]);
    });

    test('round-trip through textFromDoc, and are refused without allowBlanks', () {
      final doc = docFromText(r'x [[1]] and $y$ [[2]]', allowBlanks: true);
      expect(textFromDoc(doc, allowBlanks: true), r'x [[1]] and $y$ [[2]]');
      expect(textFromDoc(doc), isNull);
    });

    test('text that already looks like a gap marker is escaped in a blank question', () {
      final doc = docFromText('literal [[1]]');
      expect(textFromDoc(doc), 'literal [[1]]');
      final escaped = textFromDoc(doc, allowBlanks: true)!;
      expect(docFromText(escaped, allowBlanks: true), doc);
    });

    test('blankNumbers lists the markers in order', () {
      expect(blankNumbers('[[2]] and [[1]] and [[2]]'), [2, 1, 2]);
    });
  });
}
