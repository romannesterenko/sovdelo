import {test} from 'node:test';
import assert from 'node:assert/strict';
const {defaultBoardPreferences,readBoardPreferences,writeBoardPreferences,pruneBoardProjects,normalizeBoardPreferences}=await import(process.env.SOVDELO_BOARD_PREFERENCES_MODULE);
function storage(){const values=new Map();return {getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value),values}}
test('new account opens all-tasks working view with empty filters',()=>{assert.deepEqual(readBoardPreferences(storage(),1),defaultBoardPreferences());assert.equal(defaultBoardPreferences().view,'all')});
test('search filters and selected section survive recreation',()=>{
 const store=storage(),value={query:'Заявка клиента',statusFilter:'open',filterProject:'42',priorityFilter:'high',view:'project',project:42};
 writeBoardPreferences(store,7,value);assert.deepEqual(readBoardPreferences(store,7),value);
});
test('preferences never leak into another account or guest',()=>{
 const store=storage();writeBoardPreferences(store,1,{...defaultBoardPreferences(),query:'Личная задача'});
 assert.equal(readBoardPreferences(store,2).query,'');assert.equal(readBoardPreferences(store,0).query,'');
 writeBoardPreferences(store,0,{query:'Гость'});assert.equal(store.values.size,1);
});
test('corrupt, oversized or blocked storage does not prevent opening the board',()=>{
 const store=storage();store.setItem('sovdelo.web.board-filters.v1.1','{broken');assert.deepEqual(readBoardPreferences(store,1),defaultBoardPreferences());
 store.setItem('sovdelo.web.board-filters.v1.1','x'.repeat(5000));assert.deepEqual(readBoardPreferences(store,1),defaultBoardPreferences());
 const blocked={getItem(){throw Error('disabled')},setItem(){throw Error('disabled')}};
 assert.deepEqual(readBoardPreferences(blocked,1),defaultBoardPreferences());assert.doesNotThrow(()=>writeBoardPreferences(blocked,1,{}));
});
test('removed or archived projects cannot hide the board after reload',()=>{
 const old={...defaultBoardPreferences(),view:'project',project:12,filterProject:'12',query:'проверка'};
 assert.deepEqual(pruneBoardProjects(old,[]),{...defaultBoardPreferences(),query:'проверка'});
 assert.deepEqual(pruneBoardProjects(old,[12]),old);
});
test('stored values are bounded and whitelisted; list mode is never restored',()=>{
 const value=normalizeBoardPreferences({query:'x'.repeat(1000),statusFilter:'deleted',filterProject:'-1',priorityFilter:'urgent',view:'trash',project:'9',board:false,token:'do-not-store'});
 assert.equal(value.query.length,240);assert.equal(value.statusFilter,'all');assert.equal(value.filterProject,'all');assert.equal(value.view,'all');assert.equal(value.project,null);
 assert.ok(!('board' in value));assert.ok(!('token' in value));
 assert.doesNotThrow(()=>normalizeBoardPreferences({statusFilter:{toString:null,valueOf:null},view:{},priorityFilter:[]}));
});
test('clearing filters persists the cleared state',()=>{
 const store=storage();writeBoardPreferences(store,1,{...defaultBoardPreferences(),query:'старый поиск',priorityFilter:'high'});
 writeBoardPreferences(store,1,defaultBoardPreferences());assert.deepEqual(readBoardPreferences(store,1),defaultBoardPreferences());
});
