import 'dart:convert';

class Checklists {
  static List<Map<String, dynamic>> normalize(Object? value) {
    if (value is! List || value.length > 100) throw ArgumentError('Не более 100 пунктов чек-листа');
    return value.map((item) {
      if (item is! Map || item.keys.any((key) => !['text', 'done'].contains(key)) ||
          item['text'] is! String || item['done'] is! bool) {
        throw ArgumentError('Пункт должен содержать текст и отметку выполнения');
      }
      final text = (item['text'] as String).trim();
      if (text.isEmpty || text.length > 500) throw ArgumentError('Пункт: от 1 до 500 символов');
      return <String, dynamic>{'text': text, 'done': item['done']};
    }).toList();
  }

  // Older API validation allowed numeric booleans. Canonicalize cached/server data.
  static List<Map<String, dynamic>> fromRemote(Object? value) {
    if (value is! List) return normalize(value);
    return normalize(value.map((item) {
      if (item is! Map) return item;
      final copy = Map<String, dynamic>.from(item);
      final done = copy['done'];
      if (done == 1 || done == '1') copy['done'] = true;
      if (done == 0 || done == '0') copy['done'] = false;
      return copy;
    }).toList());
  }

  static List<Map<String, dynamic>> read(Object? encoded) =>
      normalize(encoded == null ? [] : jsonDecode(encoded as String));

  static String summary(Object? encoded) {
    final items = read(encoded);
    return '${items.where((i) => i['done'] == true).length}/${items.length}';
  }
}
