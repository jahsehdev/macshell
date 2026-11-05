const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const devices=vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../NotchDeviceState.js`,'utf8').replace(/^\.pragma library\s*/,''),devices);
const sample=(bat,mac='A')=>({mac,name:'AirPods Pro',icon:'headphones',connected:true,bat});
test('unknown, absent and invalid battery readings never become an empty battery',()=>{
 for(const bat of ['',null,undefined,'  ',false,'bad',101,-1])assert.equal(devices.battery(sample(bat)),-1);
 assert.equal(devices.battery(sample('0')),0);assert.equal(devices.battery(sample('80')),80);
});
test('BlueZ device metadata identifies unnamed keyboards, mice and controllers',()=>{
 for(const [name,systemIcon,kind] of [['AirPods Pro','audio-card','earbuds'],['Galaxy Buds2','audio-card','earbuds'],['Xbox Wireless Headset','audio-headset','headphones'],['G915','input-keyboard','keyboard'],['MX Master 3','input-mouse','mouse'],['Wireless Controller','input-gaming','gamepad'],['WH-1000XM5','audio-headphones','headphones'],['Unknown','','bluetooth']])assert.equal(devices.kind({name,systemIcon}),kind);
 const source=fs.readFileSync(`${__dirname}/../UpstreamBar/MacBar.qml`,'utf8');
 const fn=source.match(/function btIconFor\(name, systemIcon\) \{[\s\S]*?\n    \}/)[0];
 const icon=vm.runInNewContext('('+fn+')');assert.equal(icon('G915','input-keyboard'),'keyboard');assert.equal(icon('MX Anywhere','input-mouse'),'mouse');assert.equal(icon('Pad','input-gaming'),'gamepad');
});
test('initial scan is quiet, connections are reported once and removed devices are forgotten',()=>{
 let s=devices.observe({},[sample(70)],false);assert.equal(s.events.length,0);
 s=devices.observe(s.history,[sample(70),sample(90,'B')],true);assert.equal(s.events.length,1);assert.equal(s.events[0].reason,'connected');
 s=devices.observe(s.history,[sample(69),sample(89,'B')],true);assert.equal(s.events.length,0);
 s=devices.observe(s.history,[],true);assert.equal(Object.keys(s.history).length,0);
 s=devices.observe(s.history,[sample(70)],true);assert.equal(s.events.length,1);
});
test('20 and 10 percent alerts are deduplicated and rearm only after recovery',()=>{
 let s=devices.observe({},[sample(30)],false);
 const next=bat=>s=devices.observe(s.history,[sample(bat)],true);
 assert.equal(next(20).events.length,1);assert.equal(next(19).events.length,0);assert.equal(next(21).events.length,0);assert.equal(next(20).events.length,0);
 assert.equal(next(10).events.length,1);assert.equal(next(9).events.length,0);assert.equal(next(11).events.length,0);assert.equal(next(10).events.length,0);
 assert.equal(next(26).events.length,0);assert.equal(next(20).events.length,1);assert.equal(next(10).events.length,1);
});
test('late battery reports can alert, while connecting with a low battery produces one card',()=>{
 let s=devices.observe({},[sample('')],false);s=devices.observe(s.history,[sample(8)],true);assert.equal(s.events.length,1);assert.equal(s.events[0].reason,'low');
 s=devices.observe({},[sample(5)],true);assert.equal(s.events.length,1);assert.equal(s.events[0].reason,'connected');s=devices.observe(s.history,[sample(4)],true);assert.equal(s.events.length,0);
});
