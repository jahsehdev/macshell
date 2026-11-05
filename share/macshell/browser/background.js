/* Local classification and scheduled checks. No remote AI or generated code execution. */
const TOPICS = [
  ["Development", /github|gitlab|stackoverflow|developer|documentation|programming|coding|javascript|python|qml/i],
  ["Shopping", /shop|store|cart|product|price|buy|tokopedia|shopee/i],
  ["Travel", /flight|hotel|travel|booking|trip|ticket|wisata/i],
  ["Media", /youtube|music|spotify|video|podcast/i],
  ["Research", /paper|arxiv|research|scholar|wikipedia|science/i]
];
function topicFor(tab) {
  const content = `${tab.title || ""} ${tab.url || ""}`;
  const topic = TOPICS.find(([, regex]) => regex.test(content));
  if (topic) return topic[0];
  try { return new URL(tab.url).hostname.replace(/^www\./, ""); } catch { return "Other"; }
}
async function tabTopics() {
  const tabs = await browser.tabs.query({currentWindow: true});
  const groups = {};
  for (const tab of tabs) (groups[topicFor(tab)] ||= []).push({id: tab.id, title: tab.title, url: tab.url});
  return groups;
}
async function groupTabs() {
  const groups = await tabTopics();
  if (!browser.tabs.group || !browser.tabGroups) return {groups, sidebarOnly: true};
  const before = (await browser.tabs.query({currentWindow:true})).map(t => ({id:t.id,index:t.index,groupId:t.groupId}));
  const created = [];
  for (const [title, tabs] of Object.entries(groups)) {
    if (tabs.length < 2) continue;
    const id = await browser.tabs.group({tabIds:tabs.map(t=>t.id)});
    await browser.tabGroups.update(id,{title}); created.push(id);
  }
  await browser.storage.local.set({lastGrouping:{before,created}});
  return {groups, sidebarOnly:false};
}
async function undoGrouping() {
  const {lastGrouping} = await browser.storage.local.get('lastGrouping');
  if (!lastGrouping) return;
  for (const tab of lastGrouping.before) {
    try {
      if (tab.groupId >= 0) await browser.tabs.group({groupId:tab.groupId,tabIds:[tab.id]});
      else await browser.tabs.ungroup([tab.id]);
      await browser.tabs.move(tab.id,{index:tab.index});
    } catch { /* A tab or its original group may have closed since grouping. */ }
  }
  await browser.storage.local.remove('lastGrouping');
}
async function boundedPage(url) {
  const controller = new AbortController();
  const timer = setTimeout(()=>controller.abort(),20000);
  try {
    const response = await fetch(url,{credentials:'omit',cache:'no-store',redirect:'error',signal:controller.signal});
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const reader=response.body.getReader(); const decoder=new TextDecoder(); let size=0,text='';
    while(true) { const {done,value}=await reader.read(); if(done)break;size+=value.byteLength;if(size>1024*1024){await reader.cancel();throw new Error('Page exceeds 1 MB watch limit');} text+=decoder.decode(value,{stream:true}); }
    return text;
  } finally {clearTimeout(timer);}
}
async function checkWatch(watch) {
  const text=await boundedPage(watch.url);
  const doc=new DOMParser().parseFromString(text,'text/html');
  doc.querySelectorAll('script,style,noscript').forEach(n=>n.remove());
  const element=watch.selector ? doc.querySelector(watch.selector) : doc.body;
  if(!element)throw new Error('Selected page element was not found');
  const value=element.textContent.replace(/\s+/g,' ').trim().slice(0,100000);
  const changed=watch.previous!==undefined && watch.previous!==value;
  watch.previous=value;watch.checked=Date.now();watch.error='';
  if(changed && (!watch.contains || value.toLowerCase().includes(watch.contains.toLowerCase())))
    await browser.notifications.create({type:'basic',title:'MacShell Notify Me',message:`Page changed: ${watch.title}`,iconUrl:browser.runtime.getURL('icon.svg')});
  return watch;
}
async function watches() {return (await browser.storage.local.get('watches')).watches || [];}
let watchBusy=false;
browser.alarms.onAlarm.addListener(async alarm=>{
  if(!alarm.name.startsWith('watch:') || watchBusy)return;
  watchBusy=true;
  try {
    const items=await watches(),watch=items.find(w=>`watch:${w.id}`===alarm.name);
    if(!watch || watch.paused)return;
    try {await checkWatch(watch);} catch(error){watch.error=String(error.message);watch.checked=Date.now();}
    await browser.storage.local.set({watches:items});
  } finally {watchBusy=false;}
});
async function restoreAlarms() {
  for(const watch of await watches()) if(!watch.paused)browser.alarms.create(`watch:${watch.id}`,{periodInMinutes:watch.minutes,delayInMinutes:1});
}
browser.runtime.onStartup.addListener(restoreAlarms);
browser.runtime.onInstalled.addListener(restoreAlarms);
restoreAlarms();
browser.runtime.onMessage.addListener(async message=>{
  if(message.action==='topics')return tabTopics();
  if(message.action==='group')return groupTabs();
  if(message.action==='undo')return undoGrouping();
  if(message.action==='watches')return watches();
  if(message.action==='watch'){
    const url=new URL(message.url);if(!['http:','https:'].includes(url.protocol))throw new Error('Choose an HTTP(S) page');
    const watch={id:crypto.randomUUID(),url:url.href,title:message.title || url.hostname,selector:message.selector || '',contains:message.contains || '',minutes:Math.max(5,Number(message.minutes)||30),paused:false};
    await checkWatch(watch);
    const items=await watches();items.push(watch);await browser.storage.local.set({watches:items});
    browser.alarms.create(`watch:${watch.id}`,{periodInMinutes:watch.minutes});return watch;
  }
  if(message.action==='removeWatch'){
    await browser.alarms.clear(`watch:${message.id}`);await browser.storage.local.set({watches:(await watches()).filter(w=>w.id!==message.id)});return;
  }
  if(message.action==='pauseWatch'){
    const items=await watches(),watch=items.find(w=>w.id===message.id);if(!watch)return;
    watch.paused=!watch.paused;
    if(watch.paused)await browser.alarms.clear(`watch:${watch.id}`);else browser.alarms.create(`watch:${watch.id}`,{periodInMinutes:watch.minutes});
    await browser.storage.local.set({watches:items});return;
  }
  if(message.action==='savePageAction'){
    if(!['readable','large-text','focus','reset'].includes(message.mode))throw new Error('Unsupported page action');
    const {pageActions={}}=await browser.storage.local.get('pageActions');pageActions[message.origin]=message.mode;await browser.storage.local.set({pageActions});return;
  }
});
browser.tabs.onUpdated.addListener(async (id,change,tab)=>{
  if(change.status!=='complete' || !tab.url?.startsWith('http'))return;
  const origin=new URL(tab.url).origin;
  const {pageActions={}}=await browser.storage.local.get('pageActions');const mode=pageActions[origin];
  if(mode && await browser.permissions.contains({origins:[origin+'/*']})){
    try {await browser.tabs.executeScript(id,{file:'page-action.js'});await browser.tabs.sendMessage(id,{macshellPageAction:mode});}catch{}
  }
});
if(typeof module!=='undefined')module.exports={topicFor};
