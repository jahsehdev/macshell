const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync(require('path').join(__dirname,'..','LaunchpadState.qml'),'utf8');
let warnings=[];
const state={Theme:{pageSize:4,dissolveSingleItemFolders:false,debugDrag:true},console:{warn:(...x)=>warnings.push(x.join(' ')),info:()=>{}},pages:[[]],foldered:null,folderOpen:true,hidden:[],usage:{A:8},page:0,selected:0,pageDirection:1,searching:false,results:[],folderRemovalBusy:false,justDroppedId:'',justDroppedTimer:{restart(){}},sortMode:'alphabetical',saveSoon(){this.saved=true},refreshView(){},closeFolder(){this.folderOpen=false;this.foldered=null},computeResults(){this.results=this.pages.flat().flatMap(x=>x.kind==='folder'?x.items:[x])}};
state.root=state;
for (const name of ['saveSoon','refreshView','closeFolder','computeResults']) state[name]=state[name].bind(state);
const context=vm.createContext(state);
for(const name of ['listCopy','removeFromFolder','checkLayoutInvariants','serializeItem']) {
 const match=source.match(new RegExp('    function '+name+'\\([^]*?\\n    }'));
 assert(match,name); state[name]=vm.runInContext('('+match[0].trim()+')',context);
}
const plain=value=>JSON.parse(JSON.stringify(value));
const app=id=>({kind:'app',id,name:id,icon:''});
const folder=(...ids)=>({kind:'folder',id:'folder',name:'Utilities',items:ids.map(app)});
const label=x=>x.kind==='folder'?'F('+x.items.map(x=>x.id).join(',')+')':x.id;
function init(pages,searching=false,dissolve=false) {Object.assign(state,{pages,foldered:pages.flat().find(x=>x.kind==='folder'),folderOpen:true,hidden:[],searching,results:[],page:0,folderRemovalBusy:false}); state.Theme.dissolveSingleItemFolders=dissolve;warnings=[];}
function run(pages,id,page,index,expected,opts={}) {
 init(pages,opts.search,opts.dissolve); const original=JSON.stringify(state.pages), old=state.pages,usage=state.usage,hidden=state.hidden;
 assert.equal(state.removeFromFolder(app(id),page,index),true,warnings.join('; '));
 assert.deepStrictEqual(plain(state.pages.map(p=>p.map(label))),expected);
 assert.equal(JSON.stringify(old),original,'old layout mutated'); assert.equal(state.checkLayoutInvariants(),true);
 assert.equal(state.usage,usage); assert.equal(state.hidden,hidden); assert.equal(state.sortMode,'manual');assert.equal(state.folderRemovalBusy,false);assert.equal(state.justDroppedId,id);assert.equal(warnings.length,0);
}
state.Theme.pageSize=8;
run([[app('A'),app('B'),folder('X','Y','Z'),app('C')]],'Y',0,-1,[['A','B','F(X,Z)','C','Y']]);
run([[app('A'),app('B'),folder('X','Y'),app('C')]],'X',0,1,[['A','X','B','F(Y)','C']]);
run([[app('A'),app('B'),folder('X','Y'),app('C')]],'X',0,1,[['A','X','B','Y','C']],{dissolve:true});
run([[app('A'),folder('X')]],'X',0,-1,[['A','X']]);
run([[folder('X'),app('A'),app('B')]],'X',0,0,[['X','A','B']]);
run([[app('A'),folder('X','Y'),app('B')]],'X',10,0,[['X','A','F(Y)','B']]);
run([[app('A'),folder('X','Y'),app('B')]],'X',-5,100,[['A','F(Y)','B','X']]);
run([[app('A'),folder('X','Y'),app('B')],[app('C')]],'X',1,0,[['A','F(Y)','X','B'],['C']],{search:true});
run([[app('A')],[folder('X')]],'X',0,0,[['X','A']]);
state.Theme.pageSize=4;
run([[app('A'),folder('X','Y'),app('B'),app('C')],[app('Q')]],'X',0,2,[['A','F(Y)','X','B'],['C','Q']]);
run([[folder('X','Y'),app('A'),app('B'),app('C')],[app('Q'),app('R'),app('S'),app('T')]],'X',0,4,[['F(Y)','A','B','C'],['X','Q','R','S'],['T']]); assert.equal(state.page,1);
for (const bad of ['missing','hidden','duplicate','stale','busy']) {
 init([[app('A'),folder('X','Y')]]); if(bad==='hidden')state.hidden=['X'];if(bad==='duplicate')state.pages[0].push(app('X'));if(bad==='stale')state.pages=[[app('A')]];if(bad==='busy')state.folderRemovalBusy=true;
 const before=JSON.stringify(state.pages);assert.equal(state.removeFromFolder(app(bad==='missing'?'Z':'X'),0,0),false,bad);assert.equal(JSON.stringify(state.pages),before);assert(warnings.length,bad);
}
// Deterministic randomized checks cover insert positions, page boundaries,
// cleanup and overflow while conserving every app id exactly once.
let seed=12345;const rand=n=>{seed=(seed*1664525+1013904223)>>>0;return seed%n;};
for(let k=0;k<500;k++){
 const size=1+rand(12),n=1+rand(4),kids=1+rand(5);state.Theme.pageSize=size;
 const pages=Array.from({length:n},(_,p)=>Array.from({length:1+rand(size)},(_,i)=>app('A'+p+'-'+i)));
 const fp=rand(n),fi=rand(pages[fp].length);pages[fp][fi]=folder(...Array.from({length:kids},(_,i)=>'X'+i));
 init(pages,false,!!rand(2)); const before=state.pages.flat().flatMap(x=>x.kind==='folder'?x.items:[x]).map(x=>x.id).sort();
 assert.equal(state.removeFromFolder(app('X0'),rand(n),rand(size+3)-1),true);assert.equal(state.checkLayoutInvariants(),true);
 const after=state.pages.flat().flatMap(x=>x.kind==='folder'?x.items:[x]).map(x=>x.id).sort();assert.deepStrictEqual(plain(after),plain(before));assert.equal(warnings.length,0);
}
console.log('PASS: 11 explicit state scenarios, 5 failure guards, 500 randomized conservation/pagination cases');
