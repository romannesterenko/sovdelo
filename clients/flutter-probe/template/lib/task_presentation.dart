import 'dart:convert';
import 'checklists.dart';
import 'task_labels.dart';

class TaskPresentation {
  static const statuses={'todo':'К выполнению','doing':'В работе','done':'Готово'};
  static int pending(Map<String,Object?> task)=>(task['pending'] as int? ?? 0)+
      (task['pending_comments'] as int? ?? 0)+(task['pending_attachments'] as int? ?? 0);
  static int count(Map<String,Object?> task,String field) {
    if(task['remote_json']==null)return 0;
    return (jsonDecode(task['remote_json'] as String) as Map)[field] as int? ?? 0;
  }
  static String checklist(Map<String,Object?> task)=>Checklists.summary(task['checklist_json']);
  static bool matches(Map<String,Object?> task,{String query='',String status='',int project=-1,String label='',bool queued=false}) {
    final search=query.trim().toLowerCase();
    if(search.isNotEmpty&&!('${task['title']} ${task['description']??''}'.toLowerCase().contains(search)))return false;
    if(status.isNotEmpty&&task['status']!=status)return false;
    if(project==0&&task['project_id']!=null)return false;
    if(project>0&&task['project_id']!=project)return false;
    if(label.isNotEmpty&&!TaskLabels.read(task['labels_json']).contains(label))return false;
    if(queued&&pending(task)==0)return false;
    return true;
  }
  static String due(Object? value) {
    if(value==null)return '';
    final date=DateTime.tryParse(value.toString());
    return date==null?value.toString():'${date.day.toString().padLeft(2,'0')}.${date.month.toString().padLeft(2,'0')}.${date.year}';
  }
  static bool overdue(Map<String,Object?> task,DateTime now) {
    final date=DateTime.tryParse(task['due_date']?.toString()??'');
    return task['status']!='done'&&date!=null&&date.isBefore(DateTime(now.year,now.month,now.day));
  }
}
