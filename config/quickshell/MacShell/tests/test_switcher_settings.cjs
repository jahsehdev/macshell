const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const base = path.join(__dirname,'..');
const dockSource = fs.readFileSync(path.join(base,'MacDock.qml'),'utf8');
const barSource = fs.readFileSync(path.join(base,'UpstreamBar/MacBar.qml'),'utf8');
function extract(source,name) {
    const start=source.indexOf('function '+name+'(');
    assert.notEqual(start,-1);
    let open=source.indexOf('{',start), depth=1, end=open+1;
    while (depth && end<source.length) {
        if(source[end]==='{') depth++;
        else if(source[end]==='}') depth--;
        end++;
    }
    return source.slice(start,end);
}
const settingsIcon=path.join(os.homedir(),'.local/share/icons/MacTahoe/apps/scalable/preferences-system.svg');
function switcher(windows, standalone=false) {
    const root={activeTl:windows[0],swMru:[],hub:null,
        lookup:id=>({name:id==='org.quickshell'?'Quickshell':id,icon:id+'.svg'}),
        iconSrc:icon=>icon.startsWith('/')?'file://'+icon:icon};
    const context=vm.createContext({root,ToplevelManager:{toplevels:{values:windows}}});
    for (const [source,names] of [[dockSource,['internalWindow','appOf']],[barSource,['shellAppId','swIcon','swBuild']]]) {
        for(const name of names) vm.runInContext(extract(source,name),context);
    }
    root.shellAppId=context.shellAppId;
    root.swAddress=t=>t.addr || "";
    if(!standalone) root.hub={dock:{appOf:context.appOf,settingAppIcon:settingsIcon}};
    return {apps:context.swBuild(),icon:context.swIcon};
}
const shell=title=>({appId:'org.quickshell',title});
test('Settings uses its Dock identity, label and exact MacTahoe icon in Alt+Tab',()=>{
    const result=switcher([shell('Setting')]);
    assert.equal(result.apps[0].appId,'systemsettings');
    assert.equal(result.apps[0].name,'Settings');
    assert.equal(result.apps[0].icon,settingsIcon);
    assert.equal(result.icon(result.apps[0]),'file://'+settingsIcon);
    assert.equal(fs.existsSync(settingsIcon),true);
});
test('Settings windows group together without merging Clock or other Quickshell apps',()=>{
    const result=switcher([shell('Setting'),shell('Settings'),shell('Clock'),shell('Other')]);
    assert.equal(result.apps.length,3);
    assert.equal(result.apps[0].count,2);
    assert.equal(result.apps[1].appId,'macshell-clock');
    assert.equal(result.apps[2].appId,'org.quickshell');
});
test('a normal app with a Settings document title keeps its own identity',()=>{
    const result=switcher([{appId:'firefox',title:'Settings'}]);
    assert.equal(result.apps[0].appId,'firefox');
    assert.equal(result.apps[0].icon,'firefox.svg');
});
test('standalone menu bar recognizes current and legacy Settings titles',()=>{
    const result=switcher([shell('Setting'),shell('Settings'),shell('macshell Settings')],true);
    assert.equal(result.apps.length,1);
    assert.equal(result.apps[0].name,'Settings');
    assert.equal(result.apps[0].count,3);
});
