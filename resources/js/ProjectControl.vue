<script setup lang="ts">
import {ref,onMounted} from 'vue';
const props=defineProps<{csrf:string}>();
const emit=defineEmits<{working:[boolean]}>();
type Agent={id:number;name:string;project_id:number;valid:boolean;expires_at:string|null};
type Project={id:number;name:string};
type Task={id:number;title:string;description:string|null;version:number;workflow:{state:string;agent_id:number|null;agent_name:string|null;report:string|null}};
type Activity={id:number;actor:string;action:string;task_id:number|null;details:Record<string,unknown>;created_at:string};
type Preview={fingerprint:string;project_name:string;project_id:number|null;total:number;existing:number;create:number;items:{title:string;existing:boolean;state:string}[]};
const projects=ref<Project[]>([]),agents=ref<Agent[]>([]),selected=ref(0),tasks=ref<Task[]>([]),activity=ref<Activity[]>([]),busy=ref(false),error=ref(''),message=ref('');
const name=ref('Помощник СовДела'),password=ref(''),secret=ref(''),expires=ref(''),revokeTarget=ref<number|null>(null),revokePassword=ref('');
const preview=ref<Preview|null>(null),page=ref(1),lastPage=ref(1),filter=ref(''),openedTask=ref<number|null>(null),note=ref('');
const stateNames:Record<string,string>={backlog:'Бэклог',todo:'К выполнению',doing:'В работе',blocked:'Заблокировано',review:'Проверка',done:'Готово'};
const actionNames:Record<string,string>={agent_created:'Выдан доступ помощнику',agent_revoked:'Доступ отозван',assigned:'Назначен исполнитель',created:'Создана задача',claim:'Взята в работу',block:'Заблокирована',resume:'Работа продолжена',submit:'Передана на проверку',comment:'Комментарий',accept:'Принята',changes:'Возвращена на доработку',ready:'Готова к работе',backlog:'Отложена',plan_imported:'Перенесён план'};
async function request(path:string,method='GET',data?:unknown){
 const r=await fetch('/project-control'+path,{method,credentials:'same-origin',headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-TOKEN':props.csrf},...(data===undefined?{}:{body:JSON.stringify(data)})});
 const d=await r.json();if(!r.ok)throw Error(d.errors?Object.values(d.errors).flat().join(' '):r.status===409?'Данные изменились. Обнови список и повтори действие.':d.message||'Не удалось выполнить действие.');return d;
}
async function run(action:()=>Promise<void>){if(busy.value)return;busy.value=true;emit('working',true);error.value='';message.value='';try{await action()}catch(e){error.value=e instanceof Error?e.message:'Ошибка соединения'}finally{busy.value=false;emit('working',false)}}
async function loadIndex(){const d=await request('');projects.value=d.projects;agents.value=d.agents;if(!selected.value&&projects.value.length)selected.value=projects.value[0]!.id;}
async function loadProject(){if(!selected.value){tasks.value=[];activity.value=[];return}const d=await request('/projects/'+selected.value+'?page='+page.value);tasks.value=d.tasks;activity.value=d.activity;lastPage.value=d.last_page;}
async function refresh(){await loadIndex();await loadProject()}
onMounted(()=>run(refresh));
function choose(){page.value=1;openedTask.value=null;note.value='';run(loadProject)}
function issue(){run(async()=>{const d=await request('/agents','POST',{project_id:selected.value,name:name.value.trim(),current_password:password.value});password.value='';secret.value=d.token;expires.value=d.expires_at;await loadIndex();message.value='Доступ создан. Сохрани токен: повторно он не показывается.'})}
function revoke(){if(!revokeTarget.value)return;const id=revokeTarget.value;run(async()=>{await request('/agents/'+id+'/revoke','POST',{current_password:revokePassword.value});revokePassword.value='';revokeTarget.value=null;await loadIndex();message.value='Доступ отозван.'})}
function inspectPlan(){run(async()=>{preview.value=await request('/plan/preview','POST',{})})}
function importPlan(){if(!preview.value)return;const fingerprint=preview.value.fingerprint;run(async()=>{const d=await request('/plan/import','POST',{fingerprint});preview.value=null;selected.value=d.project_id;page.value=1;await refresh();message.value=`Создано: ${d.created}; сохранено существующих: ${d.existing}. Обнови страницу, чтобы увидеть их на основной доске.`})}
function act(task:Task,action:string,agentId?:number|null){run(async()=>{await request('/projects/'+selected.value+'/tasks/'+task.id,'POST',{action,expected_version:task.version,note:note.value,...(action==='assign'?{agent_id:agentId}: {})});note.value='';await loadProject();message.value='Изменения сохранены.'})}
function assign(task:Task,event:Event){const value=(event.target as HTMLSelectElement).value;act(task,'assign',value?Number(value):null)}
function older(){const oldest=activity.value.at(-1)?.id;if(!oldest)return;run(async()=>{const d=await request('/projects/'+selected.value+'?page='+page.value+'&before_id='+oldest);activity.value.push(...d.activity)})}
</script>
<template>
 <details class="project-control"><summary>Проекты и помощники</summary>
  <p class="muted">Ты ставишь задачи и принимаешь результат. Помощник читает только выбранный проект, берёт задачи в работу и передаёт их на проверку с отчётом. Без самостоятельного удаления и приёмки.</p>
  <p v-if="error" class="error" role="alert">{{error}}</p><p v-if="message" class="save-status" role="status">{{message}}</p>
  <fieldset :disabled="busy">
   <div class="control-actions"><button type="button" @click="run(refresh)">Обновить</button><button type="button" @click="inspectPlan">Перенести план СовДела</button></div>
   <section v-if="preview" class="extras-confirm"><h3>Перенос в «{{preview.project_name}}»</h3><p>Всего {{preview.total}}. Новых: {{preview.create}}. Уже есть: {{preview.existing}}.</p><p>Существующие тексты, статусы и архив сохраняются. Повторный перенос не создаёт дубли.</p>
    <details><summary>Карточки плана</summary><p v-for="item in preview.items" :key="item.title">{{item.existing?'Уже есть':'Новая'}} · {{item.title}} · {{stateNames[item.state]||item.state}}</p></details>
    <div class="control-actions"><button type="button" class="primary" @click="importPlan">Перенести {{preview.create}} новых</button><button type="button" @click="preview=null">Отмена</button></div>
   </section>
   <label>Проект<select v-model.number="selected" @change="choose"><option :value="0" disabled>Выбери проект</option><option v-for="p in projects" :key="p.id" :value="p.id">{{p.name}}</option></select></label>
   <p v-if="!projects.length" class="muted">Создай проект на доске или перенеси план СовДела.</p>
   <template v-if="selected">
    <details><summary>Доступ помощника</summary>
     <form @submit.prevent="issue"><label>Имя исполнителя<input v-model="name" required maxlength="60"></label><label>Текущий пароль<input v-model="password" type="password" required maxlength="128" autocomplete="current-password"></label><p class="muted">Отдельный токен на 30 дней. Смена пароля или отзыв прекращает доступ. Токен не даёт доступ к другим проектам и обычному API устройств.</p><button class="primary">Создать доступ</button></form>
     <section v-if="secret" class="extras-confirm"><p>Токен показан один раз. Срок: {{new Date(expires).toLocaleString('ru-RU')}}.</p><label>Токен<input :value="secret" readonly autocomplete="off" spellcheck="false" aria-label="Секретный токен помощника"></label><p class="muted">Не отправляй его в чат. Сохрани в локальный конфигурационный файл по инструкции docs/project-agents.md.</p><button type="button" @click="secret=''">Скрыть токен</button></section>
     <article v-for="a in agents.filter(a=>a.project_id===selected)" :key="a.id" class="device-row"><strong>{{a.name}}</strong><p>{{a.valid?'Действует':'Недействителен'}} · Исполнитель</p><button v-if="a.valid" type="button" @click="revokeTarget=a.id;revokePassword=''">Отозвать</button></article>
     <form v-if="revokeTarget" class="extras-confirm" @submit.prevent="revoke"><label>Текущий пароль<input v-model="revokePassword" type="password" required autocomplete="current-password"></label><div class="control-actions"><button>Отозвать доступ</button><button type="button" @click="revokeTarget=null;revokePassword=''">Отмена</button></div></form>
    </details>
    <h3>Ответственность и приёмка</h3><label>Показывать<select v-model="filter"><option value="">Все состояния</option><option v-for="(label,key) in stateNames" :key="key" :value="key">{{label}}</option></select></label>
    <p class="muted">Страница {{page}} из {{lastPage}}. Фильтр применяется к текущей странице.</p>
    <div class="control-tasks"><article v-for="t in tasks.filter(t=>!filter||t.workflow.state===filter)" :key="t.id" class="control-task">
     <button type="button" class="control-title" @click="openedTask=openedTask===t.id?null:t.id;note=''">#{{t.id}} · {{t.title}}</button><p>{{stateNames[t.workflow.state]||t.workflow.state}} · {{t.workflow.agent_name||'Исполнитель не назначен'}}</p>
     <section v-if="openedTask===t.id"><p class="control-text">{{t.description||'Без описания'}}</p><label>Исполнитель<select :value="t.workflow.agent_id||''" :disabled="t.workflow.state==='done'" @change="assign(t,$event)"><option value="">Не назначен</option><option v-for="a in agents.filter(a=>a.project_id===selected&&(a.valid||a.id===t.workflow.agent_id))" :key="a.id" :value="a.id" :disabled="!a.valid">{{a.name}}{{a.valid?'':' · доступ отозван'}}</option></select></label>
      <section v-if="t.workflow.report" class="extras-confirm"><strong>Отчёт исполнителя</strong><p class="control-text">{{t.workflow.report}}</p></section>
      <label>Комментарий постановщика<textarea v-model="note" maxlength="8000" rows="3"/></label>
      <div class="control-actions"><template v-if="t.workflow.state==='review'"><button type="button" class="primary" @click="act(t,'accept')">Принять · Готово</button><button type="button" @click="act(t,'changes')">На доработку</button></template>
       <button v-else-if="t.workflow.state!=='todo'&&t.workflow.state!=='doing'" type="button" @click="act(t,'ready')">К выполнению</button><button v-if="t.workflow.state!=='done'&&t.workflow.state!=='backlog'&&t.workflow.state!=='review'" type="button" @click="act(t,'backlog')">В бэклог</button></div>
     </section>
    </article></div>
    <div class="control-actions"><button type="button" :disabled="page<=1" @click="page--;run(loadProject)">Назад</button><button type="button" :disabled="page>=lastPage" @click="page++;run(loadProject)">Далее</button></div>
    <details><summary>Журнал действий · {{activity.length}}</summary><article v-for="a in activity" :key="a.id" class="device-row"><strong>{{a.actor}} · {{actionNames[a.action]||a.action}}</strong><small>{{new Date(a.created_at).toLocaleString('ru-RU')}}{{a.task_id?' · Задача #'+a.task_id:''}}</small><p v-if="a.details.note" class="control-text">{{a.details.note}}</p><p v-if="a.details.report" class="control-text">{{a.details.report}}</p></article><button v-if="activity.length>=100" type="button" @click="older">Предыдущие записи</button><p v-if="!activity.length" class="muted">Действий помощника пока нет.</p></details>
   </template>
  </fieldset><p v-if="busy" role="status">Загружаем…</p>
 </details>
</template>
<style scoped>
.project-control{margin-top:20px}.project-control summary{cursor:pointer}.control-actions{display:flex;flex-wrap:wrap;gap:8px;margin:12px 0}.control-task{padding:14px 0;border-bottom:1px solid var(--border,#394356)}.control-title{text-align:left;max-width:100%;white-space:normal;overflow-wrap:anywhere}.control-text{white-space:pre-wrap;overflow-wrap:anywhere;max-height:280px;overflow:auto}.control-tasks{max-height:60vh;overflow:auto}.project-control fieldset{border:0;padding:0;min-width:0}.project-control input,.project-control select,.project-control textarea{box-sizing:border-box;width:100%}.project-control label{display:block;margin:12px 0}.device-row small{display:block}.project-control button{min-height:40px}
</style>
