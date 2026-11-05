const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');
const dates=vm.createContext({});vm.runInContext(fs.readFileSync(`${__dirname}/../NotchCalendarState.js`,'utf8').replace(/^\.pragma library\s*/,''),dates);
test('month cells cover leap years and leading/trailing dates without duplicates',()=>{
 for(const [month,count,days] of [['2024-02-01',35,29],['2026-08-01',42,31],['2026-02-01',28,28]]){
  const cells=dates.cells(month);assert.equal(cells.length,count);assert.equal(cells.filter(c=>c.current).length,days);assert.equal(new Set(cells.map(c=>c.key)).size,count);
 }
 assert.equal(dates.key(dates.shift('2026-12-01',1)),'2027-01-01');assert.equal(dates.key(dates.shift('2026-01-01',-1)),'2025-12-01');
 assert.equal(dates.week('2026-10-25'),43);assert.equal(dates.week('2021-01-01'),53);
});
test('agenda uses local dates and excludes the exclusive all-day end date',()=>{
 const events=[{id:'all',start:'2026-11-03',end:'2026-11-04',all_day:true},{id:'night',start:new Date(2026,10,2,23,30).toISOString(),end:new Date(2026,10,3,1).toISOString()}];
 assert.equal(dates.onDay(events,'2026-11-03').length,2);assert.equal(dates.onDay(events,'2026-11-04').length,0);assert.equal(dates.time(events[0]),'All day');assert.equal(dates.key('2026-11-03'),'2026-11-03');
});
test('example events are explicit previews, and saving validates title and time range',()=>{
 const examples=dates.examples('2026-10-25');assert.equal(examples.length,3);assert.ok(examples.every(e=>e.example));assert.equal(dates.onDay(examples,'2026-10-26').length,0);
 for(const [title,start,end] of [['','10:00','11:00'],['Test','25:00','26:00'],['Test','12:00','11:00']])assert.equal(dates.eventPayload('2026-11-03',title,start,end),null);
 const event=dates.eventPayload('2026-11-03','  Planning  ','10:00','11:00');assert.equal(event.title,'Planning');assert.equal(new Date(event.end)-new Date(event.start),3600000);
});
