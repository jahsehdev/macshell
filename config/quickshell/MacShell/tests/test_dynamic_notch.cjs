const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const state = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../DynamicNotchState.js`, 'utf8').replace(/^\.pragma library\s*/, ''), state);

test('only real fullscreen on a visible workspace hides the notch', () => {
    const monitor = {id: 0, activeWorkspace: {id: 1}, specialWorkspace: {id: 0}};
    const client = {monitor: 0, workspace: {id: 1}, mapped: true, hidden: false, fullscreen: 2};
    assert.equal(state.fullscreen([client], monitor), true);
    for (const override of [{fullscreen: 0}, {fullscreen: 1}, {workspace: {id: 2}}, {monitor: 1}, {hidden: true}, {mapped: false}])
        assert.equal(state.fullscreen([{...client, ...override}], monitor), false);
    assert.equal(state.fullscreen([{...client, workspace: {id: -99}}], {...monitor, specialWorkspace: {id: -99}}), true);
});

test('hardware feedback returns to the chosen activity and ended activities disappear', () => {
    const items = state.activities(true, true, true, true);
    assert.equal(state.selectActivity(items, 'music', 'brightness', false), 'brightness');
    assert.equal(state.selectActivity(items, 'music', '', false), 'music');
    assert.equal(state.selectActivity(items, 'music', '', true), 'timer');
    assert.equal(state.selectActivity(state.activities(true, true, false, false), 'music', '', false), 'recording');
    assert.equal(state.selectActivity([], 'music', '', false), 'idle');
});

test('both modes and sizes remain inside a narrow display', () => {
    for (const mode of ['attached', 'floating']) for (const scale of [0.85, 1, 1.2]) {
        const d = state.dimensions(mode, true, true, 48, 320, scale);
        assert.ok(d.width <= 296);
        assert.ok(d.height > 160);
        assert.equal(d.top, mode === 'attached' ? 0 : 7);
    }
});

test('lyric highlighting follows playback and backward seeks, with no invented timing', () => {
    const lines = [{t: 10}, {t: 20}, {t: 30}];
    assert.equal(state.lyricIndex(lines, 0, true), -1);
    assert.equal(state.lyricIndex(lines, 10, true), 0);
    assert.equal(state.lyricIndex(lines, 24, true), 1);
    assert.equal(state.lyricIndex(lines, 100, true), 2);
    assert.equal(state.lyricIndex(lines, 12, true), 0);
    assert.equal(state.lyricIndex(lines, 24, false), -1);
    assert.equal(state.lyricIndex([], 24, true), -1);
});

test('media keeps only a medium expanded layout and a small collapsed layout', () => {
    for (const mode of ['attached','floating']) for(const side of [false,true]) {
        const medium=state.dimensions(mode,true,true,28,1280,1,true,side,'','');
        assert.equal(medium.width,side?740:640);assert.equal(medium.height,160);
        const narrow=state.dimensions(mode,true,true,28,420,1,true,side,'','');
        assert.equal(narrow.width,396);assert.equal(narrow.height,144);
        const compact=state.dimensions(mode,false,true,28,1280,1,true,side);
        assert.equal(compact.width,324);
    }
});

test('only expanded lyrics add vertical room, preserving medium and collapsed layouts', () => {
    for(const mode of ['attached','floating']) {
        const normal=state.dimensions(mode,true,true,28,1280,1,true,true,'','',false);
        const lyrics=state.dimensions(mode,true,true,28,1280,1,true,true,'','',true);
        assert.equal(lyrics.height,200);assert.equal(lyrics.height,normal.height+40);assert.equal(lyrics.width,normal.width);
        const collapsed=state.dimensions(mode,false,true,28,1280,1,true,true,'','',true);
        assert.equal(collapsed.height,mode==='attached'?28:40);
    }
});


test('recording has dedicated compact, live and finalized result sizes', () => {
    for(const mode of ['attached','floating'])for(const stage of ['live','saving','result','error']) {
        const result=stage==='result';
        const full=state.dimensions(mode,true,true,28,1280,1,false,false,'recording','',false,stage);
        assert.equal(full.width,result?580:520);assert.equal(full.height,result?184:stage==='error'?160:120);
        const small=state.dimensions(mode,false,true,28,1280,1,false,false,'recording','',false,stage);
        assert.equal(small.width,324);
        const narrow=state.dimensions(mode,true,true,28,420,1,false,false,'recording','',false,stage);
        assert.equal(narrow.width,396);assert.ok(narrow.height<=184);
    }
});


test('downloads use compact and balanced detail sizes on both notch shapes', () => {
    for(const mode of ['attached','floating']) {
        const full=state.dimensions(mode,true,true,28,1280,1,false,false,'downloads');
        assert.equal(full.width,520);assert.equal(full.height,120);
        const compact=state.dimensions(mode,false,true,28,1280,1,false,false,'downloads');
        assert.equal(compact.width,324);
        const narrow=state.dimensions(mode,true,true,28,420,1,false,false,'downloads');
        assert.equal(narrow.width,396);assert.ok(narrow.height<120);
    }
});


test('Pomodoro switches from ruler setup to a short countdown without changing other tool sizes', () => {
    for(const mode of ['attached','floating']) for(const scale of [.85,1,1.2]) {
        for(const [layout,width,height] of [['setup',520,216],['active',480,96],['decision',640,216]]) {
            const d=state.dimensions(mode,true,true,28,1280,scale,false,false,'pomodoro',layout);
            assert.equal(d.width,width*scale);assert.equal(d.height,height*scale);
            const narrow=state.dimensions(mode,true,true,28,320,scale,false,false,'pomodoro',layout);
            assert.ok(narrow.width<=296);assert.ok(narrow.height<=height*scale);
        }
        assert.equal(state.dimensions(mode,true,true,28,1280,scale,false,false,'water').height,232*scale);
    }
});


test('Bluetooth gets a battery glance and balanced detail card without resizing charging',()=>{
 for(const mode of ['attached','floating'])for(const scale of [.85,1,1.2]){
  const full=state.dimensions(mode,true,true,28,1280,scale,false,false,'bluetooth');assert.equal(full.width,520*scale);assert.equal(full.height,136*scale);
  const glance=state.dimensions(mode,false,true,28,1280,scale,false,false,'bluetooth');assert.equal(glance.width,324*scale);
  const narrow=state.dimensions(mode,true,true,28,320,scale,false,false,'bluetooth');assert.ok(narrow.width<=296);assert.ok(narrow.height<=136*scale);
  const charging=state.dimensions(mode,true,true,28,1280,scale,false,false,'charging');assert.equal(charging.width,440*scale);assert.equal(charging.height,104*scale);
 }
});


test('calendar expands inside the notch with all layouts contained on narrow screens',()=>{
 for(const mode of ['attached','floating'])for(const scale of [.85,1,1.2])for(const expanded of [false,true]){
  const d=state.dimensions(mode,true,true,28,1280,scale,false,false,'calendar','',false,'',expanded);
  assert.equal(d.width,(expanded?760:560)*scale);assert.equal(d.height,(expanded?340:256)*scale);
  const narrow=state.dimensions(mode,true,true,28,320,scale,false,false,'calendar','',false,'',expanded);assert.ok(narrow.width<=296);assert.ok(narrow.height<=d.height);
 }
});

test('weather card remains contained at every supported scale and position',()=>{
 for(const mode of ['attached','floating'])for(const scale of [.85,1,1.2])for(const width of [320,420,1280]) {
  const d=state.dimensions(mode,true,true,28,width,scale,false,false,'weather');
  assert.ok(d.width<=width-24);assert.equal(d.height,256*d.scale);
  if(width===1280)assert.equal(d.width,560*scale);
 }
});

test('system statistics has the same contained geometry in both views and both positions',()=>{
 for(const mode of ['attached','floating'])for(const scale of [.85,1,1.2])for(const width of [320,420,1280]){
  const d=state.dimensions(mode,true,true,28,width,scale,false,false,'stats');
  assert.ok(d.width<=width-24);assert.equal(d.height,256*d.scale);
  if(width===1280)assert.equal(d.width,560*scale);
 }
});
