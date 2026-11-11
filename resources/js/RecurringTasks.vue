<script setup lang="ts">
import {ref,onMounted,onUnmounted,nextTick} from 'vue';
type Series={id:number;title:string;description:string|null;priority:string;frequency:string;next_date:string;active:boolean};
const props=defineProps<{selected:{id:number;title:string;task_series_id?:number|null}|null;csrf:string;disabled:boolean;today:string}>();
const emit=defineEmits<{changed:[];working:[boolean]}>();
const opened=ref(false),busy=ref(false),error=ref(''),rows=ref<Series[]>([]),editing=ref<Series|null>(null),frequency=ref('weekly'),next=ref(''),source=ref<number|null>(null),requestKey=ref(''),confirmClose=ref(false);
const names:Record<string,string>={daily:'Ежедневно',weekly:'Еженедельно',monthly:'Ежемесячно'};
async function api(url:string,method='GET',body?:unknown){const r=await fetch(url,{method,credentials:'same-origin',headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-TOKEN':props.csrf},...(body===undefined?{}:{body:JSON.stringify(body)})});const d=await r.json();if(!r.ok)throw Error(d.errors?Object.values(d.errors).flat().join(' '):d.message||'Не удалось сохранить');return d;}
async function run(fn:()=>Promise<void>){if(busy.value)return;busy.value=true;emit('working',true);error.value='';try{await fn()}catch(e){error.value=e instanceof Error?e.message:'Ошибка соединения'}finally{busy.value=false;emit('working',false)}}
async function load(){rows.value=await api('/task-series')}
function beforeUnload(e:BeforeUnloadEvent){if(opened.value&&(source.value||editing.value||busy.value)){e.preventDefault();e.returnValue=''}}
onMounted(()=>window.addEventListener('beforeunload',beforeUnload));
onUnmounted(()=>window.removeEventListener('beforeunload',beforeUnload));
function modalKey(e:KeyboardEvent){if(e.key==='Escape'){e.stopPropagation();close()}if(e.key==='Tab'){const nodes=Array.from(document.querySelectorAll<HTMLElement>('.repeat-modal button:not(:disabled),.repeat-modal input:not(:disabled),.repeat-modal select:not(:disabled),.repeat-modal textarea:not(:disabled)')).filter(n=>!n.closest('fieldset:disabled'));const a=nodes[0],b=nodes[nodes.length-1];if(e.shiftKey&&document.activeElement===a){e.preventDefault();b?.focus()}else if(!e.shiftKey&&document.activeElement===b){e.preventDefault();a?.focus()}}}
function open(){if(props.disabled)return;confirmClose.value=false;opened.value=true;editing.value=null;source.value=null;run(load);nextTick(()=>document.querySelector<HTMLButtonElement>('.repeat-modal button')?.focus())}
function create(){requestKey.value=crypto.randomUUID();source.value=props.selected?.id??null;editing.value=null;frequency.value='weekly';next.value=props.today}
function edit(s:Series){source.value=null;editing.value={...s};frequency.value=s.frequency;next.value=s.next_date<props.today?props.today:s.next_date}
function save(){run(async()=>{if(editing.value)await api('/task-series/'+editing.value.id,'PATCH',{title:editing.value.title,description:editing.value.description,priority:editing.value.priority,frequency:frequency.value,next_date:next.value});else if(source.value)await api('/task-series','POST',{request_key:requestKey.value,task_id:source.value,frequency:frequency.value,next_date:next.value});await load();source.value=null;editing.value=null;emit('changed')})}
function close(){if(busy.value)return;if(source.value||editing.value)confirmClose.value=true;else opened.value=false}
function toggle(s:Series){run(async()=>{await api('/task-series/'+s.id,'PATCH',{active:!s.active});await load();emit('changed')})}
</script>
<template>
 <button class="repeat-button" :disabled="disabled" @click="open">↻ Повторяющиеся задачи</button>
 <div v-if="opened" class="overlay repeat-overlay" @click.self="close" @keydown="modalKey"><section class="modal repeat-modal" role="dialog" aria-modal="true" aria-labelledby="repeat-heading">
 <div class="detail-head"><h2 id="repeat-heading">Повторяющиеся задачи</h2><button :disabled="busy" aria-label="Закрыть" @click="close">×</button></div>
 <p class="muted">Отдельный шаблон для будущих задач. Архив проекта приостанавливает появление повторов; архив или корзина одного экземпляра не отключают серию. Каждый экземпляр можно менять независимо. После перерыва создаётся только последний наступивший повтор.</p>
 <p v-if="error" class="error" role="alert">{{error}}</p>
 <div v-if="confirmClose" class="extras-confirm"><p>Закрыть без сохранения серии?</p><button @click="confirmClose=false;opened=false">Закрыть без сохранения</button><button @click="confirmClose=false">Продолжить редактирование</button></div>
 <fieldset :disabled="busy||confirmClose">
 <button v-if="selected&&!source&&!editing" @click="create">Создать серию из «{{selected.title}}»</button><p v-else-if="!selected&&!source&&!editing" class="muted">Открой задачу на доске, чтобы создать из неё серию.</p>
 <form v-if="source||editing" @submit.prevent="save">
 <p v-if="source">Шаблон скопирует сохранённые название, описание, проект, приоритет, метки и чек-лист. Файлы, комментарии, крайний срок и время не копируются. Исходная задача останется отдельно.</p>
 <template v-if="editing"><label>Название будущих задач<input v-model="editing.title" required maxlength="240"></label><label>Описание<textarea v-model="editing.description" maxlength="20000"></textarea></label><label>Приоритет<select v-model="editing.priority"><option value="normal">Обычный</option><option value="high">Высокий</option></select></label></template>
 <label>Повтор<select v-model="frequency"><option v-for="(name,key) in names" :key="key" :value="key">{{name}}</option></select></label>
 <label>Следующая дата<input v-model="next" type="date" :min="today" max="2100-12-31" required></label>
 <p class="muted">Дата по часовому поясу аккаунта. Для месячной серии число сохраняется; в коротком месяце — последний день. Завершение раньше срока не сдвигает расписание.</p>
 <div class="actions"><button class="primary">Сохранить серию</button><button type="button" @click="source=null;editing=null">Отмена</button></div>
 </form>
 <div v-else class="repeat-list"><p v-if="!rows.length&&!busy" class="muted">Серий пока нет.</p><article v-for="s in rows" :key="s.id"><strong>{{s.title}}</strong><p>{{names[s.frequency]}} · следующая дата {{s.next_date}} · {{s.active?'Включена':'Приостановлена'}}</p><div class="actions"><button @click="edit(s)">Изменить будущие</button><button @click="toggle(s)">{{s.active?'Приостановить':'Продолжить'}}</button></div></article></div>
 </fieldset><p v-if="busy" role="status">Сохраняем…</p>
 </section></div>
</template>
