<script setup lang="ts">
import {ref,computed,onUnmounted,nextTick,watch} from 'vue';
import Icon from './Icon.vue';
type Account={name:string;email:string;timezone?:string;theme?:string};
type Device={id:string;current:boolean;ip:string|null;agent:string;last_activity:number};
const props=defineProps<{user:Account;csrf:string;disabled:boolean}>();
const emit=defineEmits<{updated:[{user:Account;csrf?:string}];working:[boolean]}>();
const opened=ref(false),busy=ref(false),error=ref(''),success=ref(''),confirmClose=ref(false),token=ref(props.csrf),name=ref(''),timezone=ref('Europe/Moscow'),theme=ref('dark'),zones=ref<string[]>([]),baseline=ref('');
const current=ref(''),password=ref(''),confirmation=ref(''),devicePassword=ref(''),devices=ref<Device[]>([]),supported=ref(true),target=ref<Device|null>(null);
watch(()=>props.csrf,v=>token.value=v);
const snapshot=()=>JSON.stringify({name:name.value,timezone:timezone.value,theme:theme.value});
const dirty=computed(()=>opened.value&&((!!baseline.value&&snapshot()!==baseline.value)||!!current.value||!!password.value||!!confirmation.value||!!devicePassword.value));
async function api(url:string,method='GET',body?:unknown){const r=await fetch(url,{method,credentials:'same-origin',headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-TOKEN':token.value},...(body===undefined?{}:{body:JSON.stringify(body)})});const d=await r.json();if(!r.ok)throw Error(d.errors?Object.values(d.errors).flat().join(' '):r.status===419?'Сессия истекла. Обновите страницу.':d.message||'Не удалось выполнить запрос');return d;}
async function run(fn:()=>Promise<void>){if(busy.value)return;busy.value=true;emit('working',true);error.value='';success.value='';try{await fn()}catch(e){error.value=e instanceof Error?e.message:'Ошибка соединения'}finally{busy.value=false;emit('working',false)}}
function accept(d:{user:Account;csrf?:string}){if(d.csrf)token.value=d.csrf;emit('updated',d)}
async function loadDevices(){const d=await api('/account/sessions');devices.value=d.items;supported.value=d.supported}
function open(){if(props.disabled)return;opened.value=true;confirmClose.value=false;name.value=props.user.name;timezone.value=props.user.timezone||'Europe/Moscow';theme.value=props.user.theme||'dark';baseline.value=snapshot();target.value=null;current.value='';password.value='';confirmation.value='';devicePassword.value='';run(async()=>{const d=await api('/account');zones.value=d.timezones;await loadDevices()});nextTick(()=>document.querySelector<HTMLButtonElement>('.account-modal button')?.focus())}
function finish(){opened.value=false;confirmClose.value=false;current.value='';password.value='';confirmation.value='';devicePassword.value='';target.value=null;nextTick(()=>document.querySelector<HTMLButtonElement>('.account-button')?.focus())}
function close(){if(busy.value)return;if(dirty.value)confirmClose.value=true;else finish()}
function saveProfile(){run(async()=>{const d=await api('/account','PATCH',{name:name.value,timezone:timezone.value,theme:theme.value});accept(d);name.value=d.user.name;baseline.value=snapshot();success.value='Профиль сохранён.'})}
function changePassword(){run(async()=>{const d=await api('/account/password','PUT',{current_password:current.value,password:password.value,password_confirmation:confirmation.value});accept(d);current.value='';password.value='';confirmation.value='';success.value='Пароль изменён. Остальные сессии завершены.';await loadDevices()})}
function revoke(){if(!target.value)return;const id=target.value.id;run(async()=>{const d=await api('/account/sessions/'+id+'/revoke','POST',{current_password:devicePassword.value});accept(d);devicePassword.value='';target.value=null;success.value='Выбранная сессия завершена.';await loadDevices()})}
function date(seconds:number){return new Date(seconds*1000).toLocaleString('ru-RU',{timeZone:props.user.timezone||'Europe/Moscow',dateStyle:'short',timeStyle:'short'})}
function beforeUnload(e:BeforeUnloadEvent){if(dirty.value||busy.value){e.preventDefault();e.returnValue=''}}
window.addEventListener('beforeunload',beforeUnload);onUnmounted(()=>window.removeEventListener('beforeunload',beforeUnload));
function key(e:KeyboardEvent){if(e.key==='Escape'){e.stopPropagation();close()}if(e.key==='Tab'){const nodes=Array.from(document.querySelectorAll<HTMLElement>('.account-modal button:not(:disabled),.account-modal input:not(:disabled),.account-modal select:not(:disabled)')).filter(n=>!n.closest('fieldset:disabled')&&n.getClientRects().length);const a=nodes[0],b=nodes.at(-1);if(e.shiftKey&&document.activeElement===a){e.preventDefault();b?.focus()}else if(!e.shiftKey&&document.activeElement===b){e.preventDefault();a?.focus()}}}
</script>
<template>
 <button class="account-button" :disabled="disabled" aria-label="Профиль и устройства" title="Профиль и устройства" @click="open"><Icon name="account"/></button>
 <div v-if="opened" class="overlay account-overlay" @click.self="close" @keydown="key"><section class="modal account-modal" role="dialog" aria-modal="true" aria-labelledby="account-title">
 <div class="detail-head"><h2 id="account-title">Профиль и устройства</h2><button :disabled="busy" aria-label="Закрыть профиль" @click="close">×</button></div><p class="muted">{{user.email}}</p>
 <p v-if="error" class="error" role="alert">{{error}}</p><p v-if="success" class="save-status" role="status">{{success}}</p>
 <div v-if="confirmClose" class="extras-confirm"><p>Закрыть без сохранения изменений?</p><button @click="finish">Закрыть без сохранения</button><button @click="confirmClose=false">Продолжить редактирование</button></div>
 <fieldset :disabled="busy||confirmClose">
 <form @submit.prevent="saveProfile"><label>Имя<input v-model="name" required maxlength="120" autocomplete="name"></label><label>Часовой пояс<select v-model="timezone"><option v-if="!zones.length" :value="timezone">{{timezone}}</option><option v-for="zone in zones" :key="zone" :value="zone">{{zone}}</option></select></label><label>Тема<select v-model="theme"><option value="dark">Тёмная</option><option value="light">Светлая</option><option value="system">Как в системе</option></select></label><button class="primary">Сохранить профиль</button></form>
 <details><summary>Изменить пароль</summary><form @submit.prevent="changePassword"><label>Текущий пароль<input v-model="current" type="password" required maxlength="128" autocomplete="current-password"></label><label>Новый пароль<input v-model="password" type="password" required minlength="10" maxlength="128" autocomplete="new-password"></label><label>Повтори новый пароль<input v-model="confirmation" type="password" required minlength="10" maxlength="128" autocomplete="new-password"></label><p class="muted">Минимум 10 символов. После смены пароля остальные сессии завершатся. Текущий браузер останется в аккаунте.</p><button class="primary">Изменить пароль</button></form></details>
 <details><summary>Активные сессии · {{devices.length}}</summary><p class="muted">Список браузеров с недавней активностью. Время показано в часовом поясе аккаунта.</p><p v-if="!supported" class="muted">Список устройств недоступен при текущем способе хранения сессий.</p><button v-if="supported" type="button" @click="run(loadDevices)">Обновить список</button>
 <article v-for="d in devices" :key="d.id" class="device-row"><strong>{{d.current?'Текущий браузер':'Другой браузер'}}</strong><p>{{d.agent||'Браузер не определён'}}</p><small>{{d.ip||'IP не указан'}} · {{date(d.last_activity)}}</small><button v-if="!d.current" type="button" @click="target=d;devicePassword=''">Завершить сессию</button></article>
 <form v-if="target" class="extras-confirm" @submit.prevent="revoke"><p>Завершить выбранную сессию?</p><label>Текущий пароль<input v-model="devicePassword" type="password" required maxlength="128" autocomplete="current-password"></label><p class="muted">Другие активные сессии сохранятся. Когда они истекут, для входа может снова потребоваться пароль.</p><div class="actions"><button class="primary">Завершить</button><button type="button" @click="target=null;devicePassword=''">Отмена</button></div></form>
 </details>
 </fieldset><p v-if="busy" role="status">Сохраняем…</p>
 </section></div>
</template>
