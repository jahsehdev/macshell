pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "NotchCalendarState.js" as Dates

Scope {
    id: calendar
    property bool enabled: false
    property bool ioEnabled: true
    property string databasePath: ""
    property date selectedDate: new Date()
    property date visibleMonth: Dates.month(selectedDate)
    property var events: []
    property string loadedMonth: ""
    property string error: ""
    property string saveError: ""
    readonly property bool busy: query.running
    readonly property bool saving: writer.running
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/calendar.py").toString().replace(/^file:\/\//,""))
    property string requestMonth: ""
    property string queryOutput: ""
    property string writeOutput: ""
    property bool refreshPending: false
    signal created()
    function args() {return ["python3","-B",helper].concat(databasePath?["--db",databasePath]:[]);}
    function select(value) {selectedDate=Dates.date(value);visibleMonth=Dates.month(value);}
    function changeMonth(delta) {select(Dates.shift(visibleMonth,delta));}
    function today() {select(new Date());}
    function refresh() {
        if(!enabled||!ioEnabled)return;
        if(query.running){refreshPending=true;return;}
        requestMonth=Dates.key(visibleMonth);queryOutput="";refreshPending=false;
        const next=Dates.shift(visibleMonth,1),last=new Date(next.getFullYear(),next.getMonth(),0,12);
        query.command=args().concat(["events","--from",requestMonth,"--to",Dates.key(last)]);query.running=true;
    }
    function createEvent(title,start,end) {
        if(saving)return false;
        const payload=Dates.eventPayload(selectedDate,title,start,end);
        if(!payload){saveError="Enter a title and an end time after the start time.";return false;}
        if(!ioEnabled){saveError="Calendar storage is unavailable.";return false;}
        saveError="";writeOutput="";writer.command=args().concat(["new","--json",JSON.stringify(payload)]);writer.running=true;return true;
    }
    onVisibleMonthChanged: {events=[];loadedMonth="";refresh();}
    onEnabledChanged: if(enabled)refresh()
    Component.onCompleted: if(enabled)Qt.callLater(refresh)
    Process {
        id:query
        stdout:StdioCollector {onStreamFinished:calendar.queryOutput=text}
        onExited: code=>{
            if(calendar.requestMonth===Dates.key(calendar.visibleMonth)){
                try {const result=JSON.parse(calendar.queryOutput);if(code!==0||!Array.isArray(result.events))throw new Error(result.error||"Could not read calendar.");calendar.events=result.events.slice(0,1000);calendar.loadedMonth=calendar.requestMonth;calendar.error="";}
                catch(e){calendar.error="Could not load the local calendar.";calendar.events=[];}
            }
            if(calendar.refreshPending||calendar.requestMonth!==Dates.key(calendar.visibleMonth))Qt.callLater(calendar.refresh);
        }
    }
    Process {
        id:writer
        stdout:StdioCollector {onStreamFinished:calendar.writeOutput=text}
        onExited: code=>{
            try{const result=JSON.parse(calendar.writeOutput);if(code!==0||!result.event)throw new Error(result.error||"Could not save event.");calendar.saveError="";calendar.created();calendar.refresh();}
            catch(e){calendar.saveError="Could not save the event. Try again.";}
        }
    }
    Timer {interval:60000;repeat:true;running:calendar.enabled && calendar.ioEnabled;onTriggered:calendar.refresh()}
}
