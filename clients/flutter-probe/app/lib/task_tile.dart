import 'package:flutter/material.dart';
import 'task_labels.dart';
import 'task_presentation.dart';

class TaskTile extends StatelessWidget {
  final Map<String,Object?> task;
  final List<Map<String,Object?>> labels;
  final String? projectName;
  final VoidCallback? onOpen,onToggle;
  const TaskTile({super.key,required this.task,required this.labels,this.projectName,this.onOpen,this.onToggle});
  @override
  Widget build(BuildContext context) {
    final done=task['status']=='done', pending=TaskPresentation.pending(task), keys=TaskLabels.read(task['labels_json']);
    final status=TaskPresentation.statuses[task['status']]??'';
    Widget info(IconData icon,String text,{Color? color})=>Row(mainAxisSize:MainAxisSize.min,children:[
      Icon(icon,size:14,color:color??Theme.of(context).colorScheme.onSurfaceVariant),const SizedBox(width:4),
      Text(text,style:Theme.of(context).textTheme.labelSmall?.copyWith(color:color)),
    ]);
    return Card(margin:const EdgeInsets.only(bottom:8),clipBehavior:Clip.antiAlias,child:InkWell(onTap:onOpen,
      child:Padding(padding:const EdgeInsets.fromLTRB(8,10,14,10),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        IconButton(tooltip:done?'Вернуть в работу':'Отметить выполненной',onPressed:onToggle,
          icon:Icon(done?Icons.check_circle:Icons.radio_button_unchecked,color:done?const Color(0xff56c89b):null)),
        const SizedBox(width:4),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Expanded(child:Text(task['title'] as String,maxLines:2,overflow:TextOverflow.ellipsis,
              style:Theme.of(context).textTheme.titleSmall?.copyWith(decoration:done?TextDecoration.lineThrough:null))),
            if(task['priority']=='high')const Padding(padding:EdgeInsets.only(left:8),child:Icon(Icons.flag,size:17,color:Color(0xffe3a057))),
            if(task['blocked']==1)const Padding(padding:EdgeInsets.only(left:8),child:Icon(Icons.warning_amber_rounded,size:18,color:Color(0xffe3a057)))
            else if(pending>0)const Padding(padding:EdgeInsets.only(left:8),child:Icon(Icons.cloud_upload_outlined,size:17)),
          ]),
          const SizedBox(height:6),
          Wrap(spacing:12,runSpacing:6,children:[
            info(Icons.circle_outlined,status),
            if(projectName!=null)ConstrainedBox(constraints:const BoxConstraints(maxWidth:180),child:Text(projectName!,maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.labelSmall)),
            if(task['due_date']!=null)info(Icons.event_outlined,TaskPresentation.due(task['due_date']),color:TaskPresentation.overdue(task,DateTime.now())?const Color(0xffeb8d8d):null),
            if(TaskPresentation.checklist(task)!='0/0')info(Icons.checklist,TaskPresentation.checklist(task)),
            if(TaskPresentation.count(task,'comments_count')>0)info(Icons.chat_bubble_outline,'${TaskPresentation.count(task,'comments_count')}'),
            if(TaskPresentation.count(task,'attachments_count')>0)info(Icons.attach_file,'${TaskPresentation.count(task,'attachments_count')}'),
          ]),
          if(keys.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Wrap(spacing:6,runSpacing:4,children:[
            for(final key in keys.take(3))Builder(builder:(_){
              final found=labels.where((label)=>label['local_id']==key);final label=found.isEmpty?null:found.first;
              return Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),decoration:BoxDecoration(
                color:Color(TaskLabels.colors[label?['color']]??0xff929a9e).withAlpha(45),borderRadius:BorderRadius.circular(6)),
                child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:150),child:Text(label?['name'] as String? ?? 'Метка',maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.labelSmall)));
            }),
            if(keys.length>3)Text('+${keys.length-3}',style:Theme.of(context).textTheme.labelSmall),
          ])),
        ])),
      ])),
    ));
  }
}
