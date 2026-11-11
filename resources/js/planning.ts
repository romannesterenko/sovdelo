export type PlannedTask={status:string;planned_date?:string|null;due_date?:string|null};
export function dateInZone(now:Date,zone:string):string{return new Intl.DateTimeFormat('sv-SE',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).format(now)}
export function shiftDay(day:string,amount:number):string{const d=new Date(day+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+amount);return d.toISOString().slice(0,10)}
export function overdue(t:PlannedTask,day:string):boolean{return t.status!=='done'&&!!t.due_date&&t.due_date<day}
export function dueToday(t:PlannedTask,day:string):boolean{
 if(t.status==='done')return (t.planned_date||t.due_date)===day;
 return (!!t.planned_date&&t.planned_date<=day)||(!!t.due_date&&t.due_date<=day);
}
export function upcoming(t:PlannedTask,day:string):boolean{return t.status!=='done'&&!overdue(t,day)&&!!(t.planned_date||t.due_date)&&(t.planned_date||t.due_date||'')>day}
