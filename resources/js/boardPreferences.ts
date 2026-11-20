export type BoardPreferences={query:string;statusFilter:'all'|'open'|'done';filterProject:string;priorityFilter:'all'|'high'|'normal';view:'all'|'today'|'inbox'|'upcoming'|'project';project:number|null};
type StorageLike={getItem(key:string):string|null;setItem(key:string,value:string):void};
export const defaultBoardPreferences=():BoardPreferences=>({query:'',statusFilter:'all',filterProject:'all',priorityFilter:'all',view:'all',project:null});
export function preferenceKey(account:number):string|null{return Number.isSafeInteger(account)&&account>0?`sovdelo.web.board-filters.v1.${account}`:null}
export function normalizeBoardPreferences(raw:unknown):BoardPreferences {
 const defaults=defaultBoardPreferences();if(!raw||typeof raw!=='object'||Array.isArray(raw))return defaults;
 const d=raw as Record<string,unknown>;
 const project=typeof d.project==='number'&&Number.isSafeInteger(d.project)&&d.project>0?d.project:null;
 const filterProject=typeof d.filterProject==='string'&&(d.filterProject==='all'||d.filterProject==='none'||(/^[1-9][0-9]{0,14}$/.test(d.filterProject)&&Number.isSafeInteger(Number(d.filterProject))))?d.filterProject:'all';
 const view=typeof d.view==='string'&&['all','today','inbox','upcoming','project'].includes(d.view)?d.view as BoardPreferences['view']:'all';
 return {query:typeof d.query==='string'?d.query.slice(0,240):'',statusFilter:typeof d.statusFilter==='string'&&['all','open','done'].includes(d.statusFilter)?d.statusFilter as BoardPreferences['statusFilter']:'all',
  filterProject,priorityFilter:typeof d.priorityFilter==='string'&&['all','high','normal'].includes(d.priorityFilter)?d.priorityFilter as BoardPreferences['priorityFilter']:'all',
  view:view==='project'&&project===null?'all':view,project:view==='project'?project:null};
}
export function pruneBoardProjects(value:BoardPreferences,ids:number[]):BoardPreferences {
 const result={...value};if(result.filterProject!=='all'&&result.filterProject!=='none'&&!ids.includes(Number(result.filterProject)))result.filterProject='all';
 if(result.view==='project'&&!ids.includes(result.project!)){result.view='all';result.project=null;}return result;
}
export function readBoardPreferences(storage:StorageLike,account:number):BoardPreferences {
 const key=preferenceKey(account);if(!key)return defaultBoardPreferences();
 try{const raw=storage.getItem(key);return raw&&raw.length<=4096?normalizeBoardPreferences(JSON.parse(raw)):defaultBoardPreferences()}catch{return defaultBoardPreferences()}
}
export function writeBoardPreferences(storage:StorageLike,account:number,value:unknown):void {
 const key=preferenceKey(account);if(!key)return;try{storage.setItem(key,JSON.stringify(normalizeBoardPreferences(value)))}catch{/* Storage can be disabled; the board remains usable. */}
}
