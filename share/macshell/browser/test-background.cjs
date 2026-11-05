const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const {webcrypto}=require('node:crypto');
function setup(){
 const state={},alarms=new Map(),notices=[],groups=[];let handle,alarm;
 const tabs=[{id:1,index:0,groupId:-1,title:'Python documentation',url:'https://docs.python.org'},{id:2,index:1,groupId:-1,title:'GitHub project',url:'https://github.com/example/repo'},{id:3,index:2,groupId:-1,title:'Hotel booking',url:'https://example.test/hotel'}];
 const browser={
  storage:{local:{async get(key){return {[key]:state[key]};},async set(value){Object.assign(state,value);},async remove(key){delete state[key];}}},
  runtime:{onMessage:{addListener(f){handle=f;}},onStartup:{addListener(){}},onInstalled:{addListener(){}},getURL:x=>'extension://'+x},
  tabs:{async query(){return tabs;},async group(x){groups.push(x);return groups.length;},async ungroup(){},async move(){},onUpdated:{addListener(){}}},
  tabGroups:{async update(){}},permissions:{async contains(){return true;}},notifications:{async create(n){notices.push(n);}},
  alarms:{create(id,a){alarms.set(id,a);},async clear(id){alarms.delete(id);},onAlarm:{addListener(f){alarm=f;}}}
 };
 let content='Price 10';
 const context=vm.createContext({browser,URL,crypto:webcrypto,console,setTimeout,clearTimeout,module:{exports:{}},AbortController,TextDecoder,fetch:async()=>new Response(content),DOMParser:class{parseFromString(){return {querySelectorAll(){return []},body:{textContent:content},querySelector(){return {textContent:content}}}}}});
 vm.runInContext(fs.readFileSync(__dirname+'/background.js','utf8'),context);
 return {state,alarms,notices,groups,handle:(...a)=>handle(...a),alarm:(...a)=>alarm(...a),content:x=>content=x};
}
test('groups related tabs while retaining every tab',async()=>{const s=setup();const r=await s.handle({action:'group'});assert.equal(r.sidebarOnly,false);assert.deepEqual(Array.from(s.groups[0].tabIds),[1,2]);assert.equal(Object.values(r.groups).flat().length,3);await s.handle({action:'undo'});assert.equal(s.state.lastGrouping,undefined);});
test('watch establishes baseline, alerts on changes, and supports pause and removal',async()=>{const s=setup();const watch=await s.handle({action:'watch',url:'https://example.test/item',minutes:1,contains:'Price'});assert.equal(watch.minutes,5);assert.equal(s.notices.length,0);s.content('Price 9');await s.alarm({name:'watch:'+watch.id});assert.equal(s.notices.length,1);await s.alarm({name:'watch:'+watch.id});assert.equal(s.notices.length,1);await s.handle({action:'pauseWatch',id:watch.id});assert.equal(s.alarms.has('watch:'+watch.id),false);await s.handle({action:'removeWatch',id:watch.id});assert.equal(s.state.watches.length,0);});
test('page actions reject arbitrary generated code',async()=>{const s=setup();await assert.rejects(s.handle({action:'savePageAction',origin:'https://example.test',mode:'eval(alert(1))'}));await s.handle({action:'savePageAction',origin:'https://example.test',mode:'focus'});assert.equal(s.state.pageActions['https://example.test'],'focus');});
