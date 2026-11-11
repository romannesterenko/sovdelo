<script setup lang="ts">
import {ref,computed,onMounted,onUnmounted,nextTick} from 'vue';
import Icon from './Icon.vue';
type Notice={id:number;task_id:number|null;kind:string;title:string;scheduled_at:string;read_at:string|null};
type Settings={notifications_enabled:boolean;deadline_notifications:boolean;notification_time:string};
const props=defineProps<{csrf:string;timezone:string;selected:{id:number;title:string;status:string}|null;disabled:boolean}>();
const emit=defineEmits<{open:[number];working:[boolean]}>();
const opened=ref(false),busy=ref(false),error=ref(''),pollError=ref(false),unread=ref(0),items=ref<Notice[]>([]),more=ref(false),confirmClose=ref(false);
const settings=ref<Settings>({notifications_enabled:true,deadline_notifications:true,notification_time:'09:00'}),settingsBase=ref('');
const local=ref(''),localBase=ref(''),reminderSent=ref(false),selectedId=ref<number|null>(null);
const dirty=computed(()=>opened.value&&((!!settingsBase.value&&JSON.stringify(settings.value)!==settingsBase.value)||local.value!==localBase.value));
let interval:ReturnType<typeof setInterval>|undefined,loading=false,alive=true;
async function api(url:string,method='GET',body?:unknown){const r=await fetch(url,{method,credentials:'same-origin',headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-TOKEN':props.csrf},...(body===undefined?{}:{body:JSON.stringify(body)})});const d=await r.json();if(!r.ok)throw Error(d.errors?Object.values(d.errors).flat().join(' '):r.status===419?'Сессия истекла. Обновите страницу.':d.message||'Не удалось выполнить запрос');return d;}
async function head(){if(loading)return;loading=true;try{const d=await api('/notifications');if(!alive)return;unread.value=d.unread;const old=opened.value?items.value.filter(n=>n.id<(d.items.at(-1)?.id??0)):[];items.value=[...d.items,...old];if(!old.length)more.value=d.has_more;pollError.value=false}catch{if(alive)pollError.value=true}finally{loading=false}}
async function run(fn:()=>Promise<void>){if(busy.value)return;busy.value=true;emit('working',true);error.value='';try{await fn()}catch(e){error.value=e instanceof Error?e.message:'Ошибка соединения'}finally{busy.value=false;emit('working',false)}}
function open(){if(props.disabled)return;opened.value=true;items.value=[];more.value=false;confirmClose.value=false;settingsBase.value='';selectedId.value=props.selected?.id??null;local.value='';localBase.value='';reminderSent.value=false;
 run(async()=>{settings.value=await api('/notifications/settings');settingsBase.value=JSON.stringify(settings.value);if(selectedId.value){const d=await api('/tasks/'+selectedId.value+'/reminder');local.value=d.local??'';localBase.value=local.value;reminderSent.value=d.sent;}await head()});nextTick(()=>document.querySelector<HTMLButtonElement>('.notification-modal button')?.focus());}
function close(){if(busy.value)return;if(dirty.value)confirmClose.value=true;else finishClose()}
function finishClose(){confirmClose.value=false;opened.value=false;nextTick(()=>document.querySelector<HTMLButtonElement>('.notification-bell')?.focus())}
function saveSettings(){run(async()=>{settings.value=await api('/notifications/settings','PUT',settings.value);settingsBase.value=JSON.stringify(settings.value);await head()})}
function saveReminder(clear=false){if(!selectedId.value)return;run(async()=>{const d=await api('/tasks/'+selectedId.value+'/reminder','PUT',{local:clear?null:local.value||null});local.value=d.local??'';localBase.value=local.value;reminderSent.value=d.sent;await head()})}
function read(n:Notice){run(async()=>{await api('/notifications/'+n.id+'/read','POST');n.read_at=new Date().toISOString();await head()})}
function readAll(){const through=items.value[0]?.id;if(!through)return;run(async()=>{await api('/notifications/read-all','POST',{through_id:through});items.value=items.value.map(n=>({...n,read_at:n.read_at||new Date().toISOString()}));await head()})}
function older(){const last=items.value.at(-1);if(!last)return;run(async()=>{const d=await api('/notifications?before='+last.id);items.value.push(...d.items);more.value=d.has_more;unread.value=d.unread})}
async function showTask(n:Notice){if(!n.task_id||dirty.value||busy.value)return;let ok=false;await run(async()=>{await api('/notifications/'+n.id+'/read','POST');await head();finishClose();ok=true});if(ok)emit('open',n.task_id)}
function date(value:string){return new Date(value).toLocaleString('ru-RU',{timeZone:props.timezone,dateStyle:'short',timeStyle:'short'})}
function beforeUnload(e:BeforeUnloadEvent){if(dirty.value||busy.value){e.preventDefault();e.returnValue=''}}
function key(e:KeyboardEvent){if(e.key==='Escape'){e.stopPropagation();close()}if(e.key==='Tab'){const nodes=Array.from(document.querySelectorAll<HTMLElement>('.notification-modal button:not(:disabled),.notification-modal input:not(:disabled)')).filter(n=>!n.closest('fieldset:disabled'));const a=nodes[0],b=nodes.at(-1);if(e.shiftKey&&document.activeElement===a){e.preventDefault();b?.focus()}else if(!e.shiftKey&&document.activeElement===b){e.preventDefault();a?.focus()}}}
function focus(){if(!document.hidden)void head()}
onMounted(()=>{void head();interval=setInterval(focus,30000);window.addEventListener('focus',focus);window.addEventListener('online',focus);document.addEventListener('visibilitychange',focus);window.addEventListener('beforeunload',beforeUnload)});
onUnmounted(()=>{alive=false;if(interval)clearInterval(interval);window.removeEventListener('focus',focus);window.removeEventListener('online',focus);document.removeEventListener('visibilitychange',focus);window.removeEventListener('beforeunload',beforeUnload)});
defineExpose({open});
</script>
<template>
 <button class="notification-bell" :disabled="disabled" :aria-label="'Уведомления, непрочитано: '+unread" @click="open"><Icon name="bell"/><span v-if="unread" class="notification-count">{{unread>99?'99+':unread}}</span><span v-if="pollError" class="notification-offline" title="Нет связи с уведомлениями">!</span></button>
 <div v-if="opened" class="overlay notification-overlay" @click.self="close" @keydown="key"><section class="modal notification-modal" role="dialog" aria-modal="true" aria-labelledby="notification-title">
 <div class="detail-head"><h2 id="notification-title">Уведомления <small>{{unread}}</small></h2><button :disabled="busy" aria-label="Закрыть уведомления" @click="close">×</button></div>
 <p v-if="error" class="error" role="alert">{{error}}</p><p v-if="pollError" class="error" role="status">Не удалось обновить уведомления. Проверь соединение.</p>
 <div v-if="confirmClose" class="extras-confirm"><p>Закрыть без сохранения настроек?</p><button @click="finishClose">Закрыть без сохранения</button><button @click="confirmClose=false">Продолжить редактирование</button></div>
 <fieldset :disabled="busy||confirmClose||!settingsBase">
 <details><summary>Настройки напоминаний</summary><form @submit.prevent="saveSettings"><label class="notification-check"><input v-model="settings.notifications_enabled" type="checkbox">Включить напоминания</label><label class="notification-check"><input v-model="settings.deadline_notifications" type="checkbox">Напоминать о дедлайнах</label><label>Время напоминания о дедлайне<input v-model="settings.notification_time" type="time" required></label><p class="muted">Часовой пояс: {{timezone}}. Одно уведомление на каждый дедлайн. После пропуска оно появится при возвращении. Отключение не удаляет историю; включение обработает пропущенные напоминания.</p><button class="primary">Сохранить настройки</button></form></details>
 <details v-if="selectedId"><summary>Напомнить о «{{selected?.title}}»</summary><form @submit.prevent="saveReminder()"><label>Дата и время · {{timezone}}<input v-model="local" type="datetime-local" max="2100-12-31T23:59" :disabled="selected?.status==='done'"></label><p v-if="reminderSent" class="muted">Это напоминание уже доставлено. Для нового выбери другое время.</p><p v-if="selected?.status==='done'" class="muted">Задача завершена. Новое напоминание можно назначить после возврата в работу.</p><div class="actions"><button class="primary" :disabled="selected?.status==='done'">Сохранить напоминание</button><button type="button" :disabled="!localBase||selected?.status==='done'" @click="saveReminder(true)">Отменить напоминание</button></div></form></details>
 <p v-else class="muted">Открой задачу на доске, чтобы назначить ей разовое напоминание.</p>
 <p class="muted">Доставка внутри сайта. Push и уведомления при закрытом приложении появятся на этапе приложений.</p>
 <div class="actions"><button :disabled="!unread||!items.length" @click="readAll">Прочитать все</button><button @click="head">Обновить</button></div>
 <div class="notification-list"><p v-if="!items.length&&!busy" class="muted">Пока нет уведомлений.</p><article v-for="n in items" :key="n.id" :class="{unread:!n.read_at}"><small>{{n.kind==='deadline'?'Срок задачи':'Напоминание'}} · {{date(n.scheduled_at)}}</small><p>{{n.title}}</p><div class="actions"><button v-if="n.task_id" :disabled="dirty" @click="showTask(n)">Открыть задачу</button><button v-if="!n.read_at" @click="read(n)">Прочитано</button></div></article></div><button v-if="more" class="wide" @click="older">Загрузить ещё</button>
 </fieldset><p v-if="busy" role="status">Сохраняем…</p>
 </section></div>
</template>
