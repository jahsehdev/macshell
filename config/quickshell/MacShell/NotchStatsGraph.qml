pragma ComponentBehavior: Bound
import QtQuick
import "NotchStatsState.js" as Data

Item {
    id:graph
    required property string metricId
    property var history:[]
    property real nowMs:Date.now()
    property bool fresh:true
    property string family:"sans-serif"
    readonly property color ink:Data.ink(metricId)
    readonly property color uploadInk:"#F2AAB9"
    readonly property var range:Data.graphRange(history,metricId)
    opacity:fresh?1:0.55
    onHistoryChanged:plot.requestPaint()
    onMetricIdChanged:plot.requestPaint()
    onNowMsChanged:plot.requestPaint()
    Canvas {
        id:plot;anchors.fill:parent
        onWidthChanged:requestPaint();onHeightChanged:requestPaint()
        onPaint:{
            const c=getContext("2d"),w=width,h=height;
            c.reset();if(w<=6||h<=6)return;
            c.lineCap="round";c.lineJoin="round";
            const start=graph.nowMs-60000,range=graph.range,span=Math.max(1,range.max-range.min);
            function drawSeries(key,ink,fill){
                let segments=[],segment=[],lastAt=0;
                for(const point of graph.history){
                    const v=point[key];
                    if(point.at<start)continue;
                    if(!Data.finite(v)||lastAt>0&&point.at-lastAt>2500){if(segment.length)segments.push(segment);segment=[];}
                    if(Data.finite(v))segment.push({x:3+Math.max(0,Math.min(1,(point.at-start)/60000))*(w-6),y:h-3-(v-range.min)/span*(h-6)});
                    lastAt=point.at;
                }
                if(segment.length)segments.push(segment);
                for(const points of segments){
                    function line(){
                        c.beginPath();c.moveTo(points[0].x,points[0].y);
                        for(let i=1;i<points.length;i++)c.lineTo(points[i].x,points[i].y);
                    }
                    if(fill&&points.length>1){
                        line();c.lineTo(points[points.length-1].x,h);c.lineTo(points[0].x,h);c.closePath();
                        const wash=c.createLinearGradient(0,0,0,h);
                        wash.addColorStop(0,Qt.rgba(ink.r,ink.g,ink.b,0.16));wash.addColorStop(1,Qt.rgba(ink.r,ink.g,ink.b,0));
                        c.fillStyle=wash;c.fill();
                    }
                    if(points.length>1){line();c.lineWidth=4;c.strokeStyle="#50000000";c.stroke();line();c.lineWidth=2.1;c.strokeStyle=ink;c.stroke();}
                    const p=points[points.length-1];c.fillStyle=ink;c.beginPath();c.arc(p.x,p.y,2.5,0,Math.PI*2);c.fill();
                }
            }
            drawSeries(graph.metricId,graph.ink,true);
            if(graph.metricId==="network")drawSeries("upload",graph.uploadInk,false);
        }
    }
    Text {
        anchors.centerIn:parent;visible:graph.range.count<2
        text:graph.range.count?"Collecting history…":"No readings yet"
        color:"#C5CAD5";font.family:graph.family;font.pixelSize:12
    }
}
