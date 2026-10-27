const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const base=path.join(__dirname,'..');
const source=fs.readFileSync(path.join(base,'UpstreamBar/MacBar.qml'),'utf8');
function method(name) {
    const start=source.indexOf('function '+name+'('); assert.notEqual(start,-1);
    let i=source.indexOf('{',start)+1,depth=1;
    while(depth && i<source.length) { if(source[i]==='{') depth++; if(source[i]==='}') depth--; i++; }
    return source.slice(start,i);
}
function shell(mode,windows) {
    const root={switcherMode:mode,activeTl:windows[0],swMru:[],hub:null,
        shellAppId:t=>t.appId,swAddress:t=>t.addr,lookup:id=>({name:id,icon:id})};
    const context=vm.createContext({root,ToplevelManager:{toplevels:{values:windows}}});
    for(const name of ['swBuild','swReconcile']) vm.runInContext(method(name),context);
    root.swBuild=context.swBuild; root.swCancel=()=>{root.swOpen=false;};
    return {root,context,build:context.swBuild,reconcile:context.swReconcile};
}
const windows=[{appId:'firefox',addr:'aa',title:'Reading'}, {appId:'firefox',addr:'bb',title:'Video'}, {appId:'editor',addr:'cc',title:'Source'}];
test('icon mode groups application windows and preserves MRU order',()=>{
    const s=shell('icons',windows); s.root.swMru=[windows[2],windows[1]];
    const entries=s.build(); assert.equal(entries.length,2);
    assert.equal(entries[0].appId,'firefox'); assert.equal(entries[0].count,2);
});
test('preview mode presents each window with its own capture handle, address and title',()=>{
    const entries=shell('windows',windows).build(); assert.equal(entries.length,3);
    for(let i=0;i<3;i++) {
        assert.equal(entries[i].win,windows[i]); assert.equal(entries[i].addr,windows[i].addr);
        assert.equal(entries[i].title,windows[i].title);
    }
});
test('closing a selected window reconciles to an existing window',()=>{
    const s=shell('windows',windows); s.root.swApps=s.build(); s.root.swIndex=1; s.root.swOpen=true;
    s.context.ToplevelManager.toplevels.values=[windows[0],windows[2]]; s.reconcile();
    assert.equal(s.root.swApps.length,2); assert.equal(s.root.swApps[s.root.swIndex].win,windows[2]);
});
test('reconciliation preserves the selected window despite changes in focus order',()=>{
    const s=shell('windows',windows); s.root.swApps=s.build(); s.root.swIndex=2; s.root.swOpen=true;
    s.root.activeTl=windows[2]; s.reconcile(); assert.equal(s.root.swApps[s.root.swIndex].win,windows[2]);
});
test('closing the final window dismisses the switcher',()=>{
    const s=shell('windows',windows); s.root.swApps=s.build(); s.root.swIndex=1;s.root.swOpen=true;
    s.context.ToplevelManager.toplevels.values=[];s.reconcile(); assert.equal(s.root.swOpen,false);
});
const layout=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(base,'Common/SwitcherLayout.js'),'utf8').replace(/^\.pragma library\s*/,''),layout);
test('preview grids fit small, normal and scaled logical screens with many windows',()=>{
    for(const [w,h] of [[640,480],[1280,800],[1920,1080]]) for(const n of [1,3,8,30]) {
        const p=layout.layout(n,w,h,true);assert.ok(p.width<=w-60);
        assert.ok(p.cellWidth>0 && p.cellHeight>0);
        assert.ok(p.viewHeight<h-40); assert.ok(p.contentHeight>=p.viewHeight);
        assert.ok(p.columns<=4 && p.columns>=1);
        if(n===30) assert.ok(p.contentHeight>p.viewHeight);
    }
});
test('old preferences default to icon mode and unknown values are normalized',()=>{
    assert.equal(layout.mode(undefined),'icons');assert.equal(layout.mode('bad'),'icons');assert.equal(layout.mode('windows'),'windows');
});

test('display mode is persisted, loaded with validation and reset to icons',()=>{
    const root={switcherMode:'windows',settingKeys:['switcherMode'],settingsReady:true};
    let saved='';
    const context=vm.createContext({root,SwitcherLayout:layout,settingKeys:root.settingKeys,store:{setText:text=>{saved=text;}}});
    vm.runInContext(method('saveSettings')+'\n'+method('applySettings'),context);
    context.saveSettings(); assert.equal(JSON.parse(saved).switcherMode,'windows');
    root.switcherMode='icons';context.applySettings(JSON.parse(saved),root.settingKeys);
    assert.equal(root.switcherMode,'windows');
    context.applySettings({switcherMode:'unknown'},root.settingKeys);
    assert.equal(root.switcherMode,'icons');
    assert.match(method('resetSettings'),/switcherMode = "icons"/);
});
