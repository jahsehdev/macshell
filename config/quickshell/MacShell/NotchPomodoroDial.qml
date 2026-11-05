pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: dial
    required property var host
    required property var tools
    property color tint: "#C9AF91"
    readonly property real progress: Math.max(0,Math.min(1,tools.pomodoroLeft/tools.pomodoro.total))
    Canvas {
        id: face
        anchors.fill:parent
        onWidthChanged:requestPaint()
        onHeightChanged:requestPaint()
        Connections { target:dial; function onProgressChanged(){face.requestPaint();} function onTintChanged(){face.requestPaint();} }
        onPaint:{
            const c=getContext("2d"),cx=width/2,cy=height/2,r=Math.min(width,height)/2-7;
            const start=-Math.PI*0.62,sweep=Math.PI*1.74;
            c.reset();c.lineCap="round";
            for(let i=0;i<45;i++) {
                const a=start+sweep*i/44,major=i%5===0;
                c.strokeStyle=major?"#65615B":"#343331";c.lineWidth=major?2:1.2;
                c.beginPath();c.moveTo(cx+Math.cos(a)*(r-10),cy+Math.sin(a)*(r-10));
                c.lineTo(cx+Math.cos(a)*(r-(major?17:14)),cy+Math.sin(a)*(r-(major?17:14)));c.stroke();
            }
            c.lineWidth=5;c.strokeStyle="#292724";c.beginPath();c.arc(cx,cy,r,start,start+sweep);c.stroke();
            if(dial.progress>0){c.strokeStyle=dial.tint;c.beginPath();c.arc(cx,cy,r,start,start+sweep*dial.progress);c.stroke();}
            const a=start+sweep*dial.progress;c.fillStyle="#FFF6E9";c.beginPath();c.arc(cx+Math.cos(a)*r,cy+Math.sin(a)*r,3.2,0,Math.PI*2);c.fill();
        }
    }
    Button {
        id: toggle
        objectName:"notchPomodoroToggle"
        anchors.centerIn:parent;width:96;height:76
        background:Rectangle { radius:30;color:toggle.down?"#12FFFFFF":toggle.hovered?"#08FFFFFF":"transparent" }
        contentItem:Column {
            spacing:3
            Text { width:parent.width;text:dial.host.format(Math.ceil(dial.tools.pomodoroLeft/1000));horizontalAlignment:Text.AlignHCenter;color:"#F7F5F1";font.family:dial.host.family;font.pixelSize:text.length>5?22:28;font.weight:Font.Bold;font.features:({"tnum":1}) }
            NotchIcon { anchors.horizontalCenter:parent.horizontalCenter;width:20;height:20;strokeWidth:2.6;kind:dial.tools.pomodoro.state==="running"?"pomoPause":"pomoPlay";ink:dial.tint }
        }
        Accessible.name:dial.tools.pomodoro.state==="running"?"Pause Pomodoro":"Start Pomodoro"
        HoverHandler { cursorShape:Qt.PointingHandCursor }
        onClicked:dial.tools.togglePomodoro()
        NotchToolTip { control:toggle;text:toggle.Accessible.name }
    }
}
