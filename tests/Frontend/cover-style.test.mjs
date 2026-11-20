import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {parse as parseSfc,compileStyle} from '@vue/compiler-sfc';
import postcss from 'postcss';
test('compiled cover styling targets the image container rather than widening the card',()=>{
 const source=fs.readFileSync(new URL('../../resources/js/TaskCover.vue',import.meta.url),'utf8');
 const {descriptor}=parseSfc(source);const style=descriptor.styles.find(s=>s.scoped);assert.ok(style);
 const result=compileStyle({source:style.content,filename:'TaskCover.vue',id:'data-v-regression',scoped:true});assert.equal(result.errors.length,0);
 let coverRule=false;
 postcss.parse(result.code).walkRules(rule=>{
  const selector=rule.selector.replace(/\s+/g,'');
  assert.notEqual(selector,'.board-task','cover margins must never be applied to the whole card');
  if(selector==='.board-task>.task-cover'){
   coverRule=true;assert.ok(rule.nodes.some(n=>n.prop==='width'&&n.value.includes('32px')));
  }
 });assert.equal(coverRule,true,'full-width styling must target the cover child');
});
