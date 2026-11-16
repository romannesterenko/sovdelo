import 'dart:convert';
import 'checklists.dart';
import 'task_labels.dart';

class DraftConflict implements Exception {
  final String message;
  const DraftConflict([this.message='Пока редактор был открыт, эти поля изменились. Твой текст остался в редакторе. Скопируй нужное и открой задачу заново.']);
  @override
  String toString()=>message;
}
class TaskDraft {
  static Object? rowValue(Map<String,Object?> row,String key) {
    if(key=='checklist')return jsonEncode(Checklists.read(row['checklist_json']));
    if(key=='label_keys')return jsonEncode(TaskLabels.read(row['labels_json']));
    final value=row[key];return key=='description'&&value==''?null:value;
  }
  static Object? value(String key,Object? value) {
    if(key=='checklist')return jsonEncode(Checklists.normalize(value));
    if(key=='label_keys')return jsonEncode(TaskLabels.keys(value));
    if(key=='title'&&value is String)return value.trim();
    return key=='description'&&value==''?null:value;
  }
  static Map<String,Object?> changed(Map<String,Object?> before,Map<String,Object?> fields)=>{
    for(final field in fields.entries)if(rowValue(before,field.key)!=value(field.key,field.value))field.key:field.value,
  };
}
