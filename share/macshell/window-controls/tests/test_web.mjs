import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {EventEmitter} from 'node:events';
const root = new URL('../', import.meta.url);
class Element {
  constructor(tag){this.tag=tag;this.children=[];this.attributes={};this.events={};}
  setAttribute(k,v){this.attributes[k]=v;}
  addEventListener(k,v){this.events[k]=v;}
  appendChild(child){this.children.push(child);}
  prepend(child){this.children.unshift(child);}
  querySelector(selector){return selector==='#macshell-window-controls'?this.children.find(c=>c.id==='macshell-window-controls'):null;}
}
const toolbar=new Element('header');const calls=[];let mountListener;
const context={
  document:{documentElement:{classList:{add(){},remove(){}}},querySelector(){return toolbar;},createElement:tag=>new Element(tag)},
  MutationObserver:class {constructor(fn){mountListener=fn;}observe(){}},
  requestAnimationFrame:fn=>fn(),
  window:{addEventListener(){}},
  fetch:async(url,options)=>{calls.push({url,options});return{ok:true,json:async()=>({ok:true})};}
};
const script=fs.readFileSync(new URL('web/spotify.js',root),'utf8').replace('MACSHELL_BRIDGE',JSON.stringify({endpoint:'http://127.0.0.1:43210',token:'test-token'}));
vm.runInNewContext(script,context);
await Promise.resolve();await Promise.resolve();
assert.equal(toolbar.children.length,1,'one group in the existing toolbar');
assert.equal(toolbar.children[0].children.length,3,'three real buttons');
assert.deepEqual(toolbar.children[0].children.map(b=>b.attributes['aria-label']),['Close window','Minimize window','Maximize or restore window']);
mountListener();assert.equal(toolbar.children.length,1,'navigation updates do not duplicate controls');
for(const button of toolbar.children[0].children)button.events.click({stopPropagation(){}});
await Promise.resolve();
assert.deepEqual(calls.map(c=>c.url.split('/').at(-1)),['ready','close','minimize','maximize']);
assert.ok(calls.every(c=>c.options.method==='POST'&&c.options.credentials==='omit'));
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
