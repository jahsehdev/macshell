const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,'../MacDock.qml'),'utf8');
const identityFunctions = source.slice(source.indexOf('    function internalWindow(tl)'),source.indexOf('    // points for a superellipse',source.indexOf('    function internalWindow(tl)')));
// Exercise the actual window admission path with a controlled compositor clock.
const ageFunctions = source.slice(source.indexOf('function winIdFor(tl)'),source.indexOf('    Timer { id: youngWin;'));
const admission = source.slice(source.indexOf('        var winItems = [], liveWins = [];'),source.indexOf('        var keep = [];',source.indexOf('        var winItems = [], liveWins = [];')));
function dock(options={}) {
    const window = {appId:'example.app', title:'Document'};
    let now = 1000;
    const context = vm.createContext({
        Date:{now:()=>now}, winIdList:[], winIdNext:1, tls:[window],
        showThumbs:true, windowCapture:true,
        desktopPrefs:{minimizeIntoApp:false},
        root:{minimize:options.minimized ? {isMinimized:()=>true,records:{aa:{shot:'/cache/window.png'}}} : null},
        winAddr:()=> 'aa', internalWindow:()=>false, appOf:w=>w.appId,
        keyOf:id=>id, hasPin:()=>false, lookup:()=>null, isSettingApp:id=>id === "systemsettings",
        youngWin:{running:false,start(){this.running=true;}}
    });
    vm.runInContext(ageFunctions + '\nfunction collect() {\n' + admission + '\nreturn winItems; }',context);
    return {context, collect:()=>context.collect(), advance:()=>{now+=250;}};
}
test('a window with a compositor address becomes a live-preview cell after admission',()=>{
    const d=dock();
    assert.equal(d.collect().length,0);
    d.advance();
    const result=d.collect();
    assert.equal(result.length,1);
    assert.equal(result[0].key,'win:aa');
    assert.equal(result[0].tl,d.context.tls[0]);
});
test('a minimized window is admitted with its source and fallback snapshot',()=>{
    const d=dock({minimized:true}); d.collect(); d.advance();
    const result=d.collect();
    assert.equal(result.length,1);
    assert.equal(result[0].tl,d.context.tls[0]);
    assert.equal(result[0].shot,'/cache/window.png');
});
test('show-window-previews toggle resumes previews after being re-enabled',()=>{
    const d=dock(); d.context.showThumbs=false;
    assert.equal(d.collect().length,0);
    d.context.showThumbs=true; d.collect(); d.advance();
    assert.equal(d.collect().length,1);
});
test('minimize-into-app preference controls separate minimized cells',()=>{
    const d=dock({minimized:true}); d.collect(); d.advance();
    d.context.desktopPrefs.minimizeIntoApp=true;
    assert.equal(d.collect().length,0);
    d.context.desktopPrefs.minimizeIntoApp=false;
    assert.equal(d.collect().length,1);
});
test('About is excluded from Dock apps, app windows and previews while Settings and Clock remain',()=>{
    const d=dock();
    const about={appId:'org.quickshell',title:'About This Linux'};
    const settings={appId:'org.quickshell',title:'Setting'};
    const clock={appId:'org.quickshell',title:'Clock'};
    d.context.tls=[about,settings,clock];
    d.context.ToplevelManager={toplevels:{values:d.context.tls}};
    vm.runInContext(identityFunctions,d.context);
    assert.equal(d.context.appOf(about),'');
    assert.equal(d.context.windowsFor('org.quickshell').length,0);
    assert.equal(d.context.appOf(settings),'systemsettings');
    assert.equal(d.context.appOf(clock),'macshell-clock');
    d.collect(); d.advance();
    const previews=d.collect();
    assert.equal(previews.length,1);
    assert.equal(previews[0].tl,clock);
    assert.equal(d.context.internalWindow({appId:'example.app',title:'About This Linux'}),false);
});
