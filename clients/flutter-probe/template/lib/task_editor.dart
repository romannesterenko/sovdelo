import 'package:flutter/material.dart';
import 'checklists.dart';
import 'task_labels.dart';
import 'task_draft.dart';

class TaskEditor extends StatefulWidget {
  final Map<String, Object?> task;
  final List<Map<String, Object?>> projects;
  final List<Map<String, Object?>> labels;
  final bool fullScreen;
  final Future<void> Function(Map<String,Object?>)? onSave;
  const TaskEditor({super.key, required this.task, required this.projects, this.labels = const [], this.fullScreen=false,this.onSave});
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final form = GlobalKey<FormState>();
  bool saving=false;String saveError='';
  late final title = TextEditingController(text: widget.task['title'] as String);
  late final description = TextEditingController(text: widget.task['description'] as String? ?? '');
  late final due = TextEditingController(text: widget.task['due_date'] as String? ?? '');
  late String priority = widget.task['priority'] as String? ?? 'normal';
  late int? project = widget.task['project_id'] as int?;
  late final checklist = Checklists.read(widget.task['checklist_json']).map((item) => _ChecklistDraft(item['text'] as String, item['done'] as bool)).toList();
  late final selectedLabels = TaskLabels.read(widget.task['labels_json']).toSet();
  final removedControllers = <TextEditingController>[];

  String? dateError(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.year >= 1 && parsed.year <= 9999 && parsed.toIso8601String().substring(0, 10) == value
        ? null : 'Дата в формате ГГГГ-ММ-ДД';
  }

  Future<void> chooseDate() async {
    final current = DateTime.tryParse(due.text) ?? DateTime.now();
    final initial = current.year >= 1900 && current.year <= 2100 ? current : DateTime.now();
    final result = await showDatePicker(context: context, initialDate: initial,
        firstDate: DateTime(1900), lastDate: DateTime(2100, 12, 31));
    if (result != null && mounted) due.text = result.toIso8601String().substring(0, 10);
  }

  Future<void> save() async {
    if(saving)return;
    if (!(form.currentState?.validate() ?? false)) return;
    final fields=TaskDraft.changed(widget.task,<String,Object?>{
      'title': title.text.trim(),
      'description': description.text.isEmpty ? null : description.text,
      'due_date': due.text.isEmpty ? null : due.text,
      'priority': priority, 'project_id': project,
      'label_keys': TaskLabels.keys(selectedLabels.toList()),
      'checklist': Checklists.normalize([for (final item in checklist) {'text': item.text.text, 'done': item.done}]),
    });
    setState((){saving=true;saveError='';});
    try{
      if(fields.isNotEmpty)await widget.onSave?.call(fields);
      if(mounted)Navigator.pop(context,fields);
    }catch(error){
      if(mounted)setState(()=>saveError=error is DraftConflict?error.message:error is ArgumentError?error.message.toString():'Не удалось сохранить. Твой текст остаётся в редакторе.');
    }finally{if(mounted)setState(()=>saving=false);}
  }

  @override
  void dispose() {
    title.dispose(); description.dispose(); due.dispose();
    for (final item in checklist) { item.text.dispose(); }
    for (final controller in removedControllers) { controller.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unavailable = project != null && !widget.projects.any((p) => p['id'] == project);
    final dialog = AlertDialog(
      title: const Text('Редактирование задачи'),
      content: SizedBox(width: 640, child: SingleChildScrollView(child: Form(key: form, child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if(saveError.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:12),child:Text(saveError,style:const TextStyle(color:Color(0xffeb8d8d)))),
          TextFormField(controller: title, maxLength: 240, decoration: const InputDecoration(labelText: 'Название'),
            validator: (value) => value == null || value.trim().isEmpty ? 'Введи название' : null),
          const SizedBox(height: 12),
          TextFormField(controller: description, maxLength: 20000, minLines: 4, maxLines: 10,
            decoration: const InputDecoration(labelText: 'Описание')),
          const SizedBox(height: 12),
          const Text('Проект'),
          DropdownButton<int?>(value: project, isExpanded: true, hint: const Text('Без проекта'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Без проекта')),
              for (final p in widget.projects) DropdownMenuItem<int?>(value: p['id'] as int, child: Text(p['name'] as String)),
              if (unavailable) DropdownMenuItem<int?>(value: project, enabled: false, child: Text('Проект #$project · недоступен')),
            ], onChanged: (value) => setState(() => project = value)),
          const SizedBox(height: 12),
          const Text('Метки'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final label in widget.labels) FilterChip(
              label: Text(label['name'] as String),
              avatar: Icon(Icons.label, size: 18, color: Color(TaskLabels.colors[label['color']] ?? 0xff929a9e)),
              selected: selectedLabels.contains(label['local_id']),
              onSelected: selectedLabels.length >= 20 && !selectedLabels.contains(label['local_id']) ? null : (value) => setState(() {
                if (value) { selectedLabels.add(label['local_id'] as String); } else { selectedLabels.remove(label['local_id']); }
              })),
            for (final key in selectedLabels.where((key) => !widget.labels.any((label) => label['local_id'] == key)).toList())
              InputChip(label: const Text('Недоступная метка'), onDeleted: () => setState(() => selectedLabels.remove(key))),
          ]),
          const Text('До 20 меток. Новую можно создать кнопкой «Метки» на экране аккаунта.'),
          const SizedBox(height: 12),
          const Text('Приоритет'),
          DropdownButton<String>(value: priority, isExpanded: true,
            items: const [DropdownMenuItem(value: 'normal', child: Text('Обычный')),
              DropdownMenuItem(value: 'high', child: Text('Высокий'))],
            onChanged: (value) { if (value != null) setState(() => priority = value); }),
          TextFormField(controller: due, validator: dateError,
            decoration: InputDecoration(labelText: 'Срок · ГГГГ-ММ-ДД',
              suffixIcon: IconButton(onPressed: chooseDate, icon: const Icon(Icons.calendar_today_outlined)))),
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => due.clear(), child: const Text('Убрать срок'))),
          const Divider(height: 32),
          Text('Чек-лист · выполнено ${checklist.where((item) => item.done).length}/${checklist.length}',
            style: Theme.of(context).textTheme.titleMedium),
          for (final item in checklist)
            Row(key: item.key, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(value: item.done, onChanged: (value) => setState(() => item.done = value ?? false)),
              Expanded(child: TextFormField(controller: item.text, maxLength: 500, minLines: 1, maxLines: 3,
                decoration: const InputDecoration(hintText: 'Пункт чек-листа'),
                validator: (value) => value == null || value.trim().isEmpty ? 'Введи текст или удали пункт' : null)),
              IconButton(tooltip: 'Удалить пункт', icon: const Icon(Icons.delete_outline), onPressed: () => setState(() {
                checklist.remove(item); removedControllers.add(item.text);
              })),
            ]),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: checklist.length >= 100 ? null : () => setState(() => checklist.add(_ChecklistDraft('', false))),
            icon: const Icon(Icons.add), label: const Text('Добавить пункт'))),
          const Text('До 100 пунктов, по 500 символов. Изменения применятся после «Сохранить».'),
          const SizedBox(height: 16),
          const Text('Правки сохранятся на устройстве. При наличии сети приложение попробует отправить их на сайт.'),
        ],
      )))),
      actions: [TextButton(onPressed: saving?null:() => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: saving?null:save, child: const Text('Сохранить'))],
    );
    if(!widget.fullScreen)return PopScope(canPop:!saving,child:dialog);
    return PopScope(canPop:!saving,child:Scaffold(appBar:AppBar(title:const Text('Редактирование'),actions:[
      TextButton(onPressed:saving?null:save,child:const Text('Сохранить')),
    ]),body:Padding(padding:const EdgeInsets.all(16),child:dialog.content!)));
  }
}

class _ChecklistDraft {
  final key = UniqueKey();
  final TextEditingController text;
  bool done;
  _ChecklistDraft(String value, this.done) : text = TextEditingController(text: value);
}
