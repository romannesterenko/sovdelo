import 'dart:convert';

class TaskLabels {
  static const colors = {'green': 0xff43a979, 'blue': 0xff4c91d4, 'purple': 0xffa77ac7,
    'orange': 0xffd49a44, 'red': 0xffd16a6a, 'gray': 0xff929a9e};
  static const colorNames = {'green': 'Зелёный', 'blue': 'Синий', 'purple': 'Фиолетовый',
    'orange': 'Оранжевый', 'red': 'Красный', 'gray': 'Серый'};
  static List<String> keys(Object? value) {
    if (value is! List || value.length > 20 || value.any((key) => key is! String || key.isEmpty)) throw ArgumentError('Не более 20 меток на задачу');
    final result = value.cast<String>().toSet().toList()..sort();
    if (result.length != value.length) throw ArgumentError('Метки не должны повторяться');
    return result;
  }
  static List<String> read(Object? value) => keys(value == null ? [] : jsonDecode(value as String));
  static List<String> fromRemote(Object? value) {
    if (value is! List) throw ArgumentError('Некорректные метки сервера');
    return keys(value.map((label) => 'server-label-${(label as Map)['id']}').toList());
  }
  static int id(String key) {
    final match = RegExp(r'^server-label-([1-9][0-9]*)$').firstMatch(key);
    if (match == null) throw ArgumentError('Метка ещё не отправлена. Проверь каталог меток.');
    return int.parse(match.group(1)!);
  }
}
