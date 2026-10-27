const { test } = require('node:test');
const assert = require('node:assert/strict');
const P = require('../DesktopPreferences.js');
test('requested defaults and a fixed maximum of three recent apps', () => {
    const p = P.normalize({recentLimit: 100});
    assert.equal(p.minimizeEffect,'genie'); assert.equal(p.titlebarAction,'fill'); assert.equal(p.recentLimit,3);
});
test('invalid external preferences fall back without truthy string switches', () => {
    const p=P.normalize({position:'top',stageManager:'true',stageWindows:'single',minimizeEffect:'fade'});
    assert.equal(p.position,'bottom'); assert.equal(p.stageManager,false); assert.equal(p.stageWindows,'all');
    assert.equal(p.minimizeEffect,'genie');
});
test('all supported choices survive normalization', () => {
    const p=P.normalize({position:'left',minimizeEffect:'scale',titlebarAction:'minimize',stageManager:true,stageWindows:'one',wallpaperClick:'always'});
    assert.equal(p.position,'left'); assert.equal(p.minimizeEffect,'scale'); assert.equal(p.stageManager,true); assert.equal(p.wallpaperClick,'always');
});
test('recent apps are ordered, unique and bounded', () => {
    assert.deepEqual(P.recent(['a','b','c'],'b'),['b','a','c']);
    assert.equal(P.recent(Array.from({length:25},(_,i)=>String(i)),'new').length,20);
});
