import test from 'node:test';
import assert from 'node:assert/strict';
const {cardAnchor,backgroundAnchor}=await import(process.env.SOVDELO_KANBAN_MODULE);
test('drop on upper half of filled column inserts before hovered card',()=>assert.equal(cardAnchor([10,20,30],99,20,100,80,110),20));
test('drop on lower half inserts before next card',()=>assert.equal(cardAnchor([10,20,30],99,20,100,80,170),30));
test('drop below last card appends',()=>assert.equal(cardAnchor([10,20,30],99,30,100,80,170),null));
test('reorder excludes dragged card from anchor candidates',()=>assert.equal(cardAnchor([10,20,30],20,10,100,80,170),30));
test('placeholder keeps insertion anchor while empty background appends',()=>{assert.equal(backgroundAnchor(true,20),20);assert.equal(backgroundAnchor(false,20),null)});
test('drop into empty column has no anchor',()=>{assert.equal(cardAnchor([],99,20,0,80,40),null);assert.equal(backgroundAnchor(false,null),null)});
