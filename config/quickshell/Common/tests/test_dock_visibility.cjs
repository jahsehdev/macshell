const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const visibility = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../DockVisibility.js'),'utf8').replace(/^\.pragma library\s*/,''),visibility);
const monitor = {id:0,name:'DP-1',x:0,y:0,width:1280,height:800,scale:1,reserved:[0,28,0,0],activeWorkspace:{id:1},specialWorkspace:{id:0}};
const client = {monitor:0,mapped:true,hidden:false,workspace:{id:1},floating:true,fullscreen:0,fullscreenClient:0,at:[200,100],size:[800,500]};
const busy = (c,m=monitor) => visibility.busyMonitors([m],[{...client,...c}])[m.name] === true;
test('a normal floating window leaves the Dock visible in Smart mode',()=>assert.equal(busy({}),false));
test('tiled windows still trigger Smart hide',()=>assert.equal(busy({floating:false}),true));
test('floating fullscreen and native maximize windows trigger Smart hide',()=>{
    assert.equal(busy({fullscreen:2}),true);
    assert.equal(busy({fullscreen:1}),true);
});
test('independent Zoom recognizes client maximize without compositor fullscreen',()=>{
    assert.equal(busy({fullscreen:0,fullscreenClient:1}),true);
    assert.equal(busy({fullscreen:0,fullscreen_client:1}),true);
});
test('Fill is recognized from geometry with both fullscreen flags cleared',()=>{
    assert.equal(busy({at:[0,28],size:[1280,772]}),true);
    assert.equal(busy({at:[3,31],size:[1274,766]}),true);
});
test('hidden, minimized, unmapped and inactive-workspace windows do not hide this Dock',()=>{
    assert.equal(busy({fullscreen:2,hidden:true}),false);
    assert.equal(busy({fullscreen:2,mapped:false}),false);
    assert.equal(busy({fullscreen:2,workspace:{id:2}}),false);
    assert.equal(busy({fullscreen:2,workspace:{id:-99,name:'special:minimized'}}),false);
});
test('monitor assignment is respected',()=>assert.equal(busy({fullscreen:2,monitor:1}),false));
test('Fill uses logical dimensions on scaled and rotated displays',()=>{
    const scaled={...monitor,x:1280,width:2560,height:1600,scale:2};
    assert.equal(busy({at:[1280,28],size:[1280,772]},scaled),true);
    assert.equal(busy({at:[1280,28],size:[1200,700]},scaled),false);
    const rotated={...monitor,width:1600,height:2560,scale:2,transform:1};
    assert.equal(busy({at:[0,28],size:[1280,772]},rotated),true);
});
test('a visible special workspace follows the same detection',()=>{
    assert.equal(busy({fullscreen:2,workspace:{id:-10}}, {...monitor,specialWorkspace:{id:-10}}),true);
});
