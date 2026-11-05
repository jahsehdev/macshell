const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const logic = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../NotchToolsState.js`, 'utf8').replace(/^\.pragma library\s*/, ''), logic);

test('an overdue focus phase finishes once and preserves the next break across restart', () => {
    const now = Date.now(), s = logic.defaults(now);
    s.pomodoro = {mode:'focus',state:'running',total:60000,left:60000,endAt:now-1,completed:3};
    const restored = logic.restore(JSON.parse(JSON.stringify(s)), now);
    const done = logic.tick(restored, now, false);
    assert.equal(done.pomodoro.state, 'finished');
    assert.equal(done.pomodoro.completed, 4);
    assert.equal(logic.nextMode(done), 'long');
    assert.equal(logic.tick(done, now+1000, false), done);
});
test('water history rolls over on the local day and reminders stop at the configured goal', () => {
    const now = new Date(2026,10,2,12).getTime(), s = logic.defaults(now);
    s.water.entries = [{at:now-86400000,ml:500},{at:now,ml:250}];
    assert.equal(logic.waterTotal(s, now), 250);
    assert.equal(logic.waterHours(s, now)[12], 250);
    s.water.lastReminder = now-7200000;
    const reminded = logic.tick(s, now+3600001, true);
    assert.equal(reminded.water.lastReminder, now+3600001);
    assert.equal(logic.tick(reminded,now+3601000,true),reminded);
    reminded.water.entries.push({at:now,ml:1250});
    assert.equal(logic.tick(reminded,now+7200001,true),reminded);
});
test('disabled reminders stay silent and old records are bounded on restore', () => {
    const now = Date.now(), s = logic.defaults(now);
    s.settings.remind = false; s.water.lastReminder = 0;
    assert.equal(logic.tick(s,now,true),s);
    s.water.entries = [{at:now-31*86400000,ml:100},{at:now,ml:250},{at:now+86400000,ml:200}];
    assert.equal(logic.restore(s,now).water.entries.length,1);
});
test('restore validates menus, settings and task text without changing their completion dates', () => {
    const now = Date.now();
    const s = logic.restore({menus:['unknown'],page:'unknown',settings:{focus:-10,goal:99999},tasks:[{id:'a',text:'  first  ',done:true,doneAt:now-86400000},{id:'b',text:'today',done:true,doneAt:now}]},now);
    assert.equal(s.page,'music');
    assert.equal(s.settings.focus,1);
    assert.equal(s.settings.goal,10000);
    assert.equal(s.tasks[0].text,'first');
    assert.equal(logic.doneToday(s,now),1);
});
test('legacy Bluetooth and charging pages migrate to regular pages while retaining user records', () => {
    const now=Date.now(), prior=logic.defaults(now);
    prior.version=2;prior.menus=['music','pomodoro','water','shelf','todo','bluetooth','charging'];
    prior.page='bluetooth';
    prior.tasks=[{id:'one',text:'Keep this task',createdAt:now,done:false,doneAt:0}];
    prior.water.entries=[{at:now,ml:250}];
    const restored=logic.restore(prior,now);
    assert.equal(restored.menus.length,8);
    assert.equal(restored.page,'music');
    assert.equal(restored.tasks[0].text,'Keep this task');
    assert.equal(logic.waterTotal(restored,now),250);
    assert.ok(!restored.menus.includes('bluetooth') && !restored.menus.includes('charging'));
});
test('legacy running sessions migrate without inventing daily completions', () => {
    const now=Date.now(),s=logic.defaults(now);
    s.pomodoro={mode:'focus',state:'running',total:120000,left:120000,endAt:now+60000,completed:12};
    delete s.focus;delete s.settings.quick;delete s.settings.custom;
    const restored=logic.restore(s,now);
    assert.equal(restored.pomodoro.endAt,now+60000);
    assert.equal(restored.pomodoro.completed,12);assert.equal(logic.sessionsToday(restored,now),0);
    assert.equal(restored.settings.quick,5);assert.equal(restored.settings.custom,30);
});
test('work and custom completions count once on the actual deadline day while quick timers stay independent', () => {
    const now=new Date(2026,10,3,0,5).getTime(),s=logic.defaults(now);
    s.pomodoro.mode='custom';s.pomodoro.state='running';s.pomodoro.endAt=now-10*60000;
    s.pomodoro.total=1800000;s.pomodoro.targetId='task';
    const done=logic.tick(s,now,false);
    assert.equal(done.pomodoro.completed,1);assert.equal(done.pomodoro.sessions.length,1);
    assert.equal(logic.sessionsToday(done,now),0);assert.equal(logic.sessionsToday(done,now-10*60000),1);
    assert.equal(done.pomodoro.sessions[0].targetId,'task');assert.equal(logic.tick(done,now+100,false),done);
    assert.equal(logic.nextMode(done),'short');
    const quick=logic.defaults(now);quick.pomodoro.mode='quick';quick.pomodoro.state='running';quick.pomodoro.endAt=now-1;
    const q=logic.tick(quick,now,false);assert.equal(q.pomodoro.completed,0);assert.equal(q.pomodoro.sessions.length,0);assert.equal(logic.nextMode(q),'quick');
});
test('preset restoration validates durations, targets and rotation contexts', () => {
    const now=Date.now(),s=logic.defaults(now);s.settings.quick=0;s.settings.custom=999;
    s.pomodoro.mode='custom';s.pomodoro.targetsOpen=true;s.pomodoro.targetId='missing';
    s.pomodoro.sessions=[{at:now-91*86400000,mode:'focus'},{at:now,mode:'quick'},{at:now,mode:'focus',minutes:25}];
    s.menus=['music','pomodoro'];s.focus={contexts:['shelf','music','music'],rotate:true,seconds:1};
    const restored=logic.restore(s,now);
    assert.equal(restored.pomodoro.mode,'custom');assert.equal(restored.pomodoro.targetsOpen,true);assert.equal(restored.pomodoro.targetId,'');
    assert.equal(restored.settings.quick,1);assert.equal(restored.settings.custom,180);
    assert.equal(restored.pomodoro.sessions.length,1);assert.equal(restored.focus.contexts.join(','),'music');assert.equal(restored.focus.seconds,3);
});


test('timer completion sound preference persists without resetting legacy durations or a running deadline', () => {
    const now=Date.now(),prior=logic.defaults(now);
    prior.settings.focus=2;prior.pomodoro.total=120000;prior.pomodoro.left=120000;prior.pomodoro.state='running';prior.pomodoro.endAt=now+120000;
    delete prior.settings.pomodoroSound;
    const migrated=logic.restore(prior,now);
    assert.equal(migrated.settings.pomodoroSound,true);assert.equal(migrated.settings.focus,2);
    assert.equal(migrated.pomodoro.endAt,prior.pomodoro.endAt);
    migrated.settings.pomodoroSound=false;
    assert.equal(logic.restore(JSON.parse(JSON.stringify(migrated)),now).settings.pomodoroSound,false);
});


test('calendar and weather are enabled once on migration while v5 opt-outs and user records survive',()=>{
 const now=Date.now(),old=logic.defaults(now);old.version=2;old.menus=['music','todo'];old.page='todo';old.tasks=[{id:'one',text:'Keep me',createdAt:now}];old.focus.contexts=['todo'];
 const next=logic.restore(old,now);assert.equal(next.menus.join(','),'music,todo,calendar,weather,stats');assert.equal(next.page,'todo');assert.equal(next.tasks[0].text,'Keep me');assert.equal(next.focus.contexts.join(','),'todo');
 next.menus=['music','todo'];const restored=logic.restore(next,now);assert.equal(restored.menus.join(','),'music,todo');assert.equal(restored.version,5);
});

test('weather migration preserves v3 calendar opt-outs, timer deadlines and focus selection',()=>{
 const now=Date.now(),old=logic.defaults(now);old.version=3;old.menus=['music','pomodoro'];old.page='pomodoro';old.focus.contexts=['pomodoro'];old.pomodoro.state='running';old.pomodoro.endAt=now+120000;
 const migrated=logic.restore(old,now);assert.equal(migrated.menus.join(','),'music,pomodoro,weather,stats');assert.equal(migrated.pomodoro.endAt,old.pomodoro.endAt);assert.equal(migrated.page,'pomodoro');assert.equal(migrated.focus.contexts.join(','),'pomodoro');
 migrated.menus=['music','pomodoro'];assert.equal(logic.restore(migrated,now).menus.join(','),'music,pomodoro');
});

test('system stats migrates once while preserving page, data and earlier opt-outs',()=>{
 const now=Date.now(),old=logic.defaults(now);old.version=4;old.menus=['music','todo'];old.page='todo';old.focus.contexts=['todo'];old.tasks=[{id:'keep',text:'Preserved',createdAt:now}];
 old.stats={view:'detail',primary:'temperature',secondary:'temperature'};const next=logic.restore(old,now);
 assert.equal(next.menus.join(','),'music,todo,stats');assert.equal(next.page,'todo');assert.equal(next.tasks[0].text,'Preserved');assert.equal(next.focus.contexts.join(','),'todo');
 assert.equal(next.stats.view,'detail');assert.equal(next.stats.primary,'temperature');assert.equal(next.stats.secondary,'network');
 next.menus=['music','todo'];assert.equal(logic.restore(next,now).menus.join(','),'music,todo');
 assert.equal(logic.restore({version:5,stats:{primary:'invalid',secondary:'cpu'}},now).stats.primary,'cpu');
});
