import 'package:meta/meta.dart';

/// Client mirror of the backend's LocalizedText (12 §4.1): short labels such as subject or category
/// names stored as `{"bn": "...", "en": "..."}`. Resolution order matches the server:
/// requested locale -> bn -> en -> first available.
@immutable
class LocalizedText {
  const LocalizedText(this.values);

  factory LocalizedText.fromJson(Object? json) {
    if (json is String) return LocalizedText({'bn': json}); // server already resolved it
    if (json is Map) return LocalizedText({for (final e in json.entries) '${e.key}': '${e.value}'});
    return const LocalizedText({});
  }

  final Map<String, String> values;

  String resolve(String locale) =>
      values[locale] ?? values['bn'] ?? values['en'] ?? (values.isEmpty ? '' : values.values.first);

  bool has(String locale) => values.containsKey(locale);

  @override
  bool operator ==(Object other) => other is LocalizedText && _mapEquals(other.values, values);

  @override
  int get hashCode => Object.hashAllUnordered(values.entries.map((e) => Object.hash(e.key, e.value)));
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
