import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/reader_core.dart';

class _FakeFactory implements ReaderEngineFactory {
  _FakeFactory(this.format);

  final ContentFormat format;

  @override
  bool supports(ReaderSource source) => source.format == format && source.protection == ProtectionScheme.none;

  @override
  ReaderEngine create() => throw UnimplementedError('engines arrive in Phase 4');
}

ReaderSource _source(ContentFormat format, {ProtectionScheme protection = ProtectionScheme.none}) => ReaderSource(
  editionId: 'e1',
  format: format,
  uri: Uri.parse('https://cdn.test/e1'),
  expiresAt: DateTime.utc(2030),
  protection: protection,
);

void main() {
  test('locators round-trip through their wire form for every format', () {
    const locators = <Locator>[
      StructuredLocator(editionId: 'e1', progression: 0.25, chapterId: 'c1', sectionId: 's2', offset: 120),
      EpubLocator(editionId: 'e1', progression: 0.5, href: 'ch02.xhtml', cfi: '/6/4!/4/2'),
      PdfLocator(editionId: 'e1', progression: 1, page: 212),
    ];
    for (final locator in locators) {
      expect(Locator.fromJson(locator.toJson()), locator);
    }
  });

  test('unknown or invalid wire data is ignored instead of crashing', () {
    expect(Locator.fromJson({'format': 'audio', 'edition_id': 'e1', 'progression': 0.1}), isNull);
    expect(Locator.fromJson({'format': 'pdf', 'edition_id': 'e1', 'progression': 1.5, 'page': 1}), isNull);
    expect(Locator.fromJson({'format': 'pdf', 'progression': 0.2, 'page': 1}), isNull);
  });

  test('the registry picks a supporting engine and refuses DRM it cannot open', () {
    final registry = ReaderEngineRegistry([_FakeFactory(ContentFormat.epub)]);
    expect(() => registry.engineFor(_source(ContentFormat.epub)), throwsUnimplementedError);
    expect(
      () => registry.engineFor(_source(ContentFormat.epub, protection: ProtectionScheme.lcp)),
      throwsA(isA<UnsupportedSourceException>()),
    );
    expect(() => registry.engineFor(_source(ContentFormat.pdf)), throwsA(isA<UnsupportedSourceException>()));
  });

  test('reader settings default to generous Bangla line height and copy immutably', () {
    const settings = ReaderSettings();
    expect(settings.lineHeight, 1.6);
    final dark = settings.copyWith(theme: ReaderTheme.dark);
    expect((dark.theme, settings.theme), (ReaderTheme.dark, ReaderTheme.light));
  });

  test('reader_core stays free of rendering dependencies (12 §10 import rule)', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.readAsStringSync().contains(RegExp("import 'package:(flutter|epub|pdf|readium)"))) file.path,
    ];
    expect(offenders, isEmpty);
  });
}
