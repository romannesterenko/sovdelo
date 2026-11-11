export function cardAnchor(ids:number[],dragging:number,hover:number,top:number,height:number,y:number):number|null {
 const rows=ids.filter(id=>id!==dragging),i=rows.indexOf(hover);
 if(i<0)return null;
 return y<top+height/2?hover:(rows[i+1]??null);
}
export function backgroundAnchor(onSlot:boolean,previous:number|null):number|null {return onSlot?previous:null}
