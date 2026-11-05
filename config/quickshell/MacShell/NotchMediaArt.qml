pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Effects

Rectangle {
    id: cover
    property url source: ""
    property string fallbackKind:"music"
    property color fallbackInk:"#B9BDC5"
    property real fallbackStrokeWidth:2.5
    property real fallbackSize:width*0.44
    property int imageFillMode:Image.PreserveAspectCrop
    radius: Geometry.radius(width<40?Geometry.controlRadius-Geometry.controlPadding:Geometry.contentRadius,width,height);color:"#23252B"
    NotchIcon { anchors.centerIn:parent;width:cover.fallbackSize;height:width;kind:cover.fallbackKind;ink:cover.fallbackInk;strokeWidth:cover.fallbackStrokeWidth;visible:art.status!==Image.Ready }
    Rectangle { id:mask;anchors.fill:parent;radius:cover.radius;visible:false;layer.enabled:true;color:"white" }
    Image {
        id:art;anchors.fill:parent;source:cover.source;sourceSize:Qt.size(200,200);asynchronous:true;fillMode:cover.imageFillMode
        visible:status===Image.Ready && GraphicsInfo.api!==GraphicsInfo.Software
        layer.enabled:GraphicsInfo.api!==GraphicsInfo.Software
        layer.effect:MultiEffect { maskEnabled:true;maskSource:mask;maskThresholdMin:0.5;maskSpreadAtMin:1 }
    }
    Canvas {
        id:softwareArt
        anchors.fill:parent;visible:GraphicsInfo.api===GraphicsInfo.Software && art.status===Image.Ready
        function load(){if(cover.source.toString()!=="")loadImage(cover.source);requestPaint();}
        onImageLoaded:requestPaint()
        onWidthChanged:requestPaint()
        onHeightChanged:requestPaint()
        Component.onCompleted:load()
        Connections {target:cover;function onSourceChanged(){softwareArt.load();}}
        onPaint:{
            const c=getContext("2d");c.reset();
            if(!isImageLoaded(cover.source))return;
            c.beginPath();c.roundedRect(0,0,width,height,cover.radius,cover.radius);c.clip();
            const size=cover.imageFillMode===Image.PreserveAspectFit?Math.min(width/art.implicitWidth,height/art.implicitHeight):Math.max(width/art.implicitWidth,height/art.implicitHeight);
            const w=art.implicitWidth*size,h=art.implicitHeight*size;
            c.drawImage(cover.source,(width-w)/2,(height-h)/2,w,h);
        }
    }
}
