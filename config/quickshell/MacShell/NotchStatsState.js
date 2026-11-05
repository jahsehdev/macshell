.pragma library

var ids=["cpu","ram","gpu","disk","battery","network","temperature"];
function name(id){return ({cpu:"CPU",ram:"RAM",gpu:"GPU",disk:"Storage",battery:"Battery",network:"Network",temperature:"Temperature"})[id]||id;}
function ink(id){return ({cpu:"#A0A3FF",ram:"#78D7AE",gpu:"#E28DBE",disk:"#F2C76E",battery:"#7DCD83",network:"#76D6F5",temperature:"#FF9A50"})[id]||"#FFFFFF";}
function icon(id){return ({cpu:"statsCpu",ram:"statsRam",gpu:"statsGpu",disk:"statsDisk",battery:"statsBattery",network:"statsNetwork",temperature:"statsTemp"})[id]||"stats";}
function finite(value){return typeof value==="number" && isFinite(value);}
function bounded(value,low,high){return finite(value)&&value>=low&&value<=high?value:null;}
function text(value){return typeof value==="string"?value.slice(0,160):"";}
function clean(raw,now){
    if(!raw||typeof raw!=="object"||!finite(raw.at)||raw.at<=0||Math.abs(raw.at-now)>120000)return null;
    var out={at:raw.at};
    ids.forEach(function(id){out[id]=bounded(raw[id],id==="temperature"?-50:0,id==="temperature"?200:id==="network"?1e15:100);});
    ["upload","ramUsed","ramTotal","diskUsed","diskTotal"].forEach(function(k){out[k]=bounded(raw[k],0,1e18);});
    ["temperatureMax","temperatureCritical"].forEach(function(k){out[k]=bounded(raw[k],0,200);});
    ["cpuStatus","batteryStatus","gpuName","gpuStatus","temperatureLabel"].forEach(function(k){out[k]=text(raw[k]);});
    out.interfaces=Array.isArray(raw.interfaces)?raw.interfaces.filter(function(v){return typeof v==="string";}).slice(0,16).map(text):[];
    return out;
}
function history(prior,sample){
    var previous=prior.length?prior[prior.length-1].at:0;
    if(sample.at<=previous && previous-sample.at<2000)return prior;
    var kept=sample.at<previous?[]:prior.filter(function(p){return p.at>=sample.at-60000;});
    var point={at:sample.at,upload:sample.upload};ids.forEach(function(id){point[id]=sample[id];});
    return kept.concat([point]).slice(-61);
}
function rate(value){
    if(!finite(value))return {value:"—",unit:""};
    var units=["B/s","KB/s","MB/s","GB/s"],n=value,i=0;
    while(n>=1000 && i<units.length-1){n/=1000;i++;}
    return {value:n<10&&i>0?n.toFixed(1):String(Math.round(n)),unit:units[i]};
}
function memory(used,total){
    return finite(used)&&finite(total)&&total>0&&used<=total?(used/1073741824).toFixed(1)+" / "+(total/1073741824).toFixed(1)+" GiB":"";
}
function metric(snapshot,points,id){
    var s=snapshot||{},value=s[id],ok=finite(value),display=id==="network"?rate(value):{value:ok?String(Math.round(value)):"—",unit:ok?(id==="temperature"?"°C":"%"):""};
    var caption="Waiting for data",ratio=ok?value/100:0,secondary=0;
    if(snapshot){
        if(id==="cpu")caption=ok?"Processor usage":s.cpuStatus||"CPU unavailable";
        else if(id==="ram")caption=ok?memory(s.ramUsed,s.ramTotal)||"Physical memory":"RAM unavailable";
        else if(id==="disk")caption=ok?memory(s.diskUsed,s.diskTotal)||"Root volume /":"Storage unavailable";
        else if(id==="gpu")caption=ok?s.gpuName||"Graphics usage":s.gpuStatus||"GPU unavailable";
        else if(id==="battery")caption=s.batteryStatus||"No battery detected";
        else if(id==="network"){
            var up=rate(s.upload);caption=finite(s.upload)?"↑ "+up.value+" "+up.unit:"Sampling traffic…";
            var peak=1000000;points.forEach(function(p){peak=Math.max(peak,finite(p.network)?p.network:0,finite(p.upload)?p.upload:0);});
            ratio=ok?value/peak:0;secondary=finite(s.upload)?s.upload/peak:0;
        }else if(id==="temperature"){
            caption=!ok?"CPU sensor unavailable":finite(s.temperatureCritical)&&value>=s.temperatureCritical?"Hot":finite(s.temperatureMax)&&value>=s.temperatureMax?"Warm":finite(s.temperatureCritical)||finite(s.temperatureMax)?"Normal":s.temperatureLabel||"CPU sensor";
            ratio=ok?value/(s.temperatureCritical||100):0;
        }
    }
    return {value:display.value,unit:display.unit,short:display.value+(id==="network"?(display.unit?" "+display.unit:""):id==="temperature"?(ok?"°":""):ok?"%":""),available:ok,caption:caption,ratio:Math.max(0,Math.min(1,ratio)),secondary:Math.max(0,Math.min(1,secondary)),ink:ink(id),symbol:icon(id),name:name(id)};
}
function graphRange(points,id){
    var values=[],count=0;points.forEach(function(p){if(finite(p[id]))values.push(p[id]);if(id==="network"&&finite(p.upload))values.push(p.upload);if(finite(p[id])||id==="network"&&finite(p.upload))count++;});
    if(!values.length)return {min:0,max:1,count:0};
    var high=Math.max.apply(null,values),low=Math.min.apply(null,values);
    return id==="temperature"?{min:Math.max(-50,low-5),max:high+5,count:count}:{min:0,max:Math.max(id==="network"?1024:20,high*1.15),count:count};
}
