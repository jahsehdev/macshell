import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {EventEmitter} from 'node:events';
const root = new URL('../', import.meta.url);
class Element {
  constructor(tag){this.tag=tag;this.tagName=tag.toUpperCase();this.children=[];this.attributes={};this.events={};}
  get firstElementChild(){return this.children[0]??null;}
  setAttribute(k,v){this.attributes[k]=v;}
  getAttribute(k){return this.attributes[k];}
  addEventListener(k,v){this.events[k]=v;}
  appendChild(child){this.children.push(child);}
  prepend(child){this.children.unshift(child);}
  querySelector(selector){return this.children.find(c=>selector==='#macshell-window-controls'&&c.id==='macshell-window-controls')??this.children.map(c=>c.querySelector(selector)).find(Boolean)??null;}
}
const toolbar=new Element('header');
const navigation=new Element('div');const history=new Element('button');
navigation.appendChild(history);toolbar.appendChild(navigation);
const search=new Element('div');const account=new Element('div');
toolbar.appendChild(search);toolbar.appendChild(account);
const calls=[];let mountListener;const documentEvents={};const windowEvents={};const classes=new Set();
const context={
  document:{documentElement:{classList:{add:n=>classes.add(n),remove:n=>classes.delete(n),toggle:(n,on)=>on?classes.add(n):classes.delete(n)}},
    addEventListener:(name,fn)=>{documentEvents[name]=fn;},querySelector(){return toolbar;},createElement:tag=>new Element(tag)},
  MutationObserver:class {constructor(fn){mountListener=fn;}observe(){}},
  requestAnimationFrame:fn=>fn(),
  window:{addEventListener:(name,fn)=>{windowEvents[name]=fn;}},
  AbortSignal, setTimeout, clearTimeout,
  fetch:async(url,options)=>{calls.push({url,options});return{ok:true,json:async()=>({ok:true,systemMove:true})};}
};
const script=fs.readFileSync(new URL('web/spotify.js',root),'utf8').replace('MACSHELL_BRIDGE',JSON.stringify({endpoint:'http://127.0.0.1:43210',token:'test-token'}));
vm.runInNewContext(script,context);
await new Promise(setImmediate);
assert.equal(toolbar.children.length,4,'absolute controls plus original navigation/search/account groups');
assert.equal(navigation.children.length,1,'original history navigation group untouched');
assert.equal(navigation.children[0],history,'history button preserved');
assert.equal(navigation.attributes['data-macshell-navigation'],'');
const controls=toolbar.children[0];
assert.equal(controls.children.length,3,'three real buttons');
assert.deepEqual(controls.children.map(b=>b.attributes['aria-label']),['Close window','Minimize window','Maximize or restore window']);
mountListener();assert.equal(toolbar.children.length,4,'navigation updates do not duplicate controls');
for(const button of controls.children)button.events.click({stopPropagation(){},preventDefault(){}});
await Promise.resolve();
assert.deepEqual(calls.map(c=>c.url.split('/').at(-1)),['ready','close','minimize','maximize']);
assert.ok(calls.every(c=>c.options.method==='POST'&&c.options.credentials==='omit'));
assert.ok(classes.has('macshell-system-move'),'native drag mode only after bridge readiness');
const blank={closest:()=>null};const interactive={closest:()=>history};
const event=(target=blank,extra={})=>({target,button:0,buttons:1,pointerId:1,clientX:100,clientY:20,preventDefault(){},...extra});
const moves=()=>calls.filter(c=>c.url.endsWith('/move')).length;
toolbar.events.pointerdown(event());
documentEvents.pointermove(event(blank,{clientX:102}));assert.equal(moves(),0,'click jitter does not move');
documentEvents.pointermove(event(blank,{clientX:110}));assert.equal(moves(),1,'blank toolbar starts native move');
documentEvents.pointermove(event(blank,{clientX:130}));assert.equal(moves(),1,'one native request per gesture');
for(const target of [interactive,blank]){
  toolbar.events.pointerdown(event(target));documentEvents.pointerup(event());
  documentEvents.pointermove(event(blank,{clientX:150}));
}
assert.equal(moves(),1,'buttons and released gestures never start a move');
toolbar.events.pointerdown(event(blank,{button:2}));documentEvents.pointermove(event(blank,{clientX:150}));
assert.equal(moves(),1,'right click is preserved');
toolbar.events.pointerdown(event());documentEvents.pointermove(event(blank,{buttons:0,clientX:150}));
assert.equal(moves(),1,'a missing release event cannot leave a pending drag');
toolbar.events.pointerdown(event());windowEvents.blur();documentEvents.pointermove(event(blank,{clientX:150}));
assert.equal(moves(),1,'focus loss cancels a pending drag');
const beforeDoubleClick=calls.length;
toolbar.events.dblclick(event(interactive));assert.equal(calls.length,beforeDoubleClick);
toolbar.events.dblclick(event());assert.ok(calls.at(-1).url.endsWith('/maximize'));

// A failed startup handshake must reconnect even when React keeps the toolbar.
const retryTimers=[];let attempts=0;
const originalMountListener=mountListener;
const reconnectToolbar=new Element('header');
const reconnectContext={...context,
  document:{...context.document,querySelector:()=>reconnectToolbar},
  setTimeout:fn=>{retryTimers.push(fn);return retryTimers.length;},
  fetch:async()=>({ok:++attempts>1,json:async()=>({ok:true,systemMove:true})})};
vm.runInNewContext(script,reconnectContext);
await new Promise(setImmediate);
assert.equal(attempts,1);assert.equal(retryTimers.length,1,'failure schedules a bounded retry');
retryTimers.shift()();await new Promise(setImmediate);
assert.equal(attempts,2,'bridge readiness recovers without a toolbar remount');
assert.equal(reconnectToolbar.children.length,1,'retry never duplicates buttons');
mountListener=originalMountListener;
// Spotify can replace the React navigation subtree on a route/layout change.
const replacement=new Element('div');toolbar.children[1]=replacement;
mountListener();mountListener();
assert.equal(toolbar.children.length,4,'remount retains toolbar layout');
assert.equal(toolbar.children[0],controls,'controls survive navigation replacement');
assert.equal(replacement.attributes['data-macshell-navigation'],'','new navigation reserves the menu area');
const app=new EventEmitter();const spawned=[];
const electron=new vm.SyntheticModule(['app'],function(){this.setExport('app',app)});
const childProcess=new vm.SyntheticModule(['spawn'],function(){this.setExport('spawn',(...args)=>{spawned.push(args);return{on(){},unref(){}}})});
const sandbox=vm.createContext({process:{pid:123},setTimeout:fn=>fn()});
const hook=fs.readFileSync(new URL('web/antigravity-main.js',root),'utf8').replace('MACSHELL_HELPER',JSON.stringify('/test/window_action.py'));
const mod=new vm.SourceTextModule(hook,{context:sandbox});
// Synthetic imports must use the same VM context as the importing module.
const em=new vm.SyntheticModule(['app'],function(){this.setExport('app',app)},{context:sandbox});
const cm=new vm.SyntheticModule(['spawn'],function(){this.setExport('spawn',(...args)=>{spawned.push(args);return{on(){},unref(){}}})},{context:sandbox});
await mod.link(name=>name==='electron'?em:cm);await mod.evaluate();
const window=new EventEmitter();window.isDestroyed=()=>false;window.isVisible=()=>true;window.webContents=new EventEmitter();
window.webContents.executeJavaScript=async source=>{assert.match(source,/window-controls-container/);return true;};
app.emit('browser-window-created',{},window);window.webContents.emit('did-finish-load');
await Promise.resolve();await Promise.resolve();
assert.equal(spawned[0][1][1],'ready');
sandbox.__macshellWindowControls.minimize();
assert.equal(spawned[1][1][1],'minimize');
assert.equal(spawned[1][1].at(-1),'123');
console.log('Spotify: toolbar mounting, navigation updates, accessible buttons and all actions passed.');
console.log('Antigravity: native controls readiness and minimize routing passed.');
