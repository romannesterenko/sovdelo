import 'package:flutter/material.dart';

class TaskEditor extends StatefulWidget {
  final Map<String, Object?> task;
  final List<Map<String, Object?>> projects;
  const TaskEditor({super.key, required this.task, required this.projects});
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.task['title'] as String);
  late final description = TextEditingController(text: widget.task['description'] as String? ?? '');
  late final due = TextEditingController(text: widget.task['due_date'] as String? ?? '');
  late String priority = widget.task['priority'] as String? ?? 'normal';
  late int? project = widget.task['project_id'] as int?;

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

  void save() {
    if (!(form.currentState?.validate() ?? false)) return;
    Navigator.pop(context, <String, Object?>{
      'title': title.text.trim(),
      'description': description.text.isEmpty ? null : description.text,
      'due_date': due.text.isEmpty ? null : due.text,
      'priority': priority, 'project_id': project,
    });
  }

  @override
  void dispose() { title.dispose(); description.dispose(); due.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final unavailable = project != null && !widget.projects.any((p) => p['id'] == project);
    return AlertDialog(
      title: const Text('Редактирование задачи'),
      content: SizedBox(width: 640, child: SingleChildScrollView(child: Form(key: form, child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
          const Text('Приоритет'),
          DropdownButton<String>(value: priority, isExpanded: true,
            items: const [DropdownMenuItem(value: 'normal', child: Text('Обычный')),
              DropdownMenuItem(value: 'high', child: Text('Высокий'))],
            onChanged: (value) { if (value != null) setState(() => priority = value); }),
          TextFormField(controller: due, validator: dateError,
            decoration: InputDecoration(labelText: 'Срок · ГГГГ-ММ-ДД',
              suffixIcon: IconButton(onPressed: chooseDate, icon: const Icon(Icons.calendar_today_outlined)))),
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => due.clear(), child: const Text('Убрать срок'))),
          const Text('Правки сохранятся на устройстве. При наличии сети приложение попробует отправить их на сайт.'),
        ],
      )))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: save, child: const Text('Сохранить'))],
    );
  }
}
