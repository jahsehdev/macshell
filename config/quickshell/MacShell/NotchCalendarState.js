.pragma library
function date(value) {
    if (value instanceof Date) return new Date(value.getTime());
    if (/^\d{4}-\d{2}-\d{2}$/.test(String(value))) { var a=value.split('-'); return new Date(Number(a[0]),Number(a[1])-1,Number(a[2]),12); }
    return new Date(value);
}
function key(value) { var d=date(value);return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'); }
function month(value) { var d=date(value);return new Date(d.getFullYear(),d.getMonth(),1,12); }
function shift(value,amount) { var d=month(value);return new Date(d.getFullYear(),d.getMonth()+amount,1,12); }
function cells(value) {
    var d=month(value),lead=d.getDay(),days=new Date(d.getFullYear(),d.getMonth()+1,0).getDate(),result=[];
    var count=Math.ceil((lead+days)/7)*7;
    for(var i=0;i<count;i++){var day=new Date(d.getFullYear(),d.getMonth(),i-lead+1,12);result.push({key:key(day),day:day.getDate(),current:day.getMonth()===d.getMonth()});}
    return result;
}
function week(value) {
    var d=date(value),utc=new Date(Date.UTC(d.getFullYear(),d.getMonth(),d.getDate()));
    utc.setUTCDate(utc.getUTCDate()+4-(utc.getUTCDay()||7));
    return Math.ceil((((utc-new Date(Date.UTC(utc.getUTCFullYear(),0,1)))/86400000)+1)/7);
}
function onDay(events,value) {
    var d=date(value),start=new Date(d.getFullYear(),d.getMonth(),d.getDate()).getTime(),end=new Date(d.getFullYear(),d.getMonth(),d.getDate()+1).getTime();
    return (events||[]).filter(function(e){if(e.all_day){var target=key(value),first=String(e.start).slice(0,10),last=String(e.end).slice(0,10);return first<=target&&(last>target||first===last&&first===target);}var a=date(e.start).getTime(),b=date(e.end).getTime();return isFinite(a)&&isFinite(b)&&a<end&&(b>start||a===b&&a>=start);}).sort(function(a,b){return Number(!!b.all_day)-Number(!!a.all_day)||date(a.start)-date(b.start);});
}
function clock(value) {var d=date(value);return String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0');}
function time(event) {return event.all_day?'All day':clock(event.start)+' – '+clock(event.end);}
function examples(value) {
    var day=key(value);
    return [{id:'example-launch',title:'Launch review',start:day+'T10:00:00',end:day+'T11:00:00',color:'#8B83FF',example:true},
        {id:'example-lunch',title:'Lunch with Sam',start:day+'T12:30:00',end:day+'T13:45:00',color:'#FF9663',example:true},
        {id:'example-design',title:'Design sync',start:day+'T15:00:00',end:day+'T15:45:00',color:'#8B83FF',example:true}];
}
function validTime(value){return /^([01]\d|2[0-3]):[0-5]\d$/.test(value);}
function eventPayload(day,title,start,end) {
    if(!title.trim()||!validTime(start)||!validTime(end)||end<=start)return null;
    var d=date(day),a=start.split(':'),b=end.split(':');
    var first=new Date(d.getFullYear(),d.getMonth(),d.getDate(),Number(a[0]),Number(a[1]));
    var last=new Date(d.getFullYear(),d.getMonth(),d.getDate(),Number(b[0]),Number(b[1]));
    return {title:title.trim().slice(0,300),start:first.toISOString(),end:last.toISOString(),reminders:[]};
}
