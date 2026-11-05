const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm');
const stats=vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../NotchStatsState.js`,'utf8').replace(/^\.pragma library\s*/,''),stats);
test('unknown readings remain unknown while real zero is valid',()=>{
 const at=Date.now(),s=stats.clean({at,cpu:0,ram:null,gpu:-1,temperature:55,network:0,upload:NaN},at);
 assert.equal(s.cpu,0);assert.equal(s.ram,null);assert.equal(s.gpu,null);assert.equal(s.upload,null);
 assert.equal(stats.metric(s,[],'cpu').value,'0');assert.equal(stats.metric(s,[],'gpu').value,'—');
 assert.equal(stats.clean({at:at+300000},at),null);
});
test('history is bounded to sixty seconds and does not duplicate or reorder frames',()=>{
 let frames=[],at=Date.now();for(let i=0;i<100;i++)frames=stats.history(frames,{at:at+i*1000,cpu:i,upload:0});
 assert.equal(frames.length,61);assert.equal(frames[0].at,at+39000);
 assert.equal(stats.history(frames,{at:at+99000,cpu:1}),frames);
 assert.equal(stats.history(frames,{at:at+98500,cpu:1}),frames);
 const restarted=stats.history(frames,{at:at+300000,cpu:5});assert.equal(restarted.length,1);
});
test('network uses byte rates, SI units and a shared graph scale for upload and download',()=>{
 assert.equal(stats.rate(27500000).value,'28');assert.equal(stats.rate(5500000).unit,'MB/s');
 const m=stats.metric({network:27000000,upload:5500000},[{network:54000000,upload:5500000}],'network');
 assert.equal(m.ratio,.5);assert.match(m.caption,/↑ 5\.5 MB\/s/);
 const range=stats.graphRange([{network:10,upload:20000}],'network');assert.ok(range.max>=20000);assert.equal(range.count,1);
});
test('temperature status follows exposed thresholds and does not invent a normal threshold',()=>{
 const base={temperature:54,temperatureMax:80,temperatureCritical:100};
 assert.equal(stats.metric(base,[],'temperature').caption,'Normal');
 assert.equal(stats.metric({...base,temperature:85},[],'temperature').caption,'Warm');
 assert.equal(stats.metric({...base,temperature:101},[],'temperature').caption,'Hot');
 assert.equal(stats.metric({temperature:54,temperatureLabel:'Package'},[],'temperature').caption,'Package');
 assert.equal(stats.metric({},[],'battery').value,'—');
});
