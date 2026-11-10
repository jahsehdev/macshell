pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import "NotchGeometry.js" as Geometry

Item {
    id: page
    required property var host
    readonly property var weather: host.bar && host.bar.hub ? host.bar.hub.widgets : null
    readonly property bool ready: !!weather && weather.wxReady === true
    readonly property bool busy: !!weather && weather.wxBusy === true
    readonly property bool failed: !weather || (weather.wxError || "") !== ""
    readonly property var info: ready ? weather.wxInfo : ({t:"",k:"cloud"})
    readonly property var hours: ready ? weather.wxHourly.slice(0,6) : []
    readonly property bool interacting: locationPopup.visible
    property string locationMode: "auto"
    property string unit: "C"

    Rectangle {
        id: card
        objectName: "notchWeatherCard"
        anchors.fill: parent
        radius: Geometry.contentRadius
        color: sky.skyTop
        NotchWeatherScene {
            id:sky
            anchors.fill:parent
            kind:page.info.k;day:!page.weather || page.weather.wxDay
            ready:page.ready;radius:card.radius
            active:page.visible && page.host.available && page.host.expanded && page.host.activity==="weather" && !page.failed
            reducedMotion:page.host.reducedMotion
        }
        // Inset camera contour, with the same rounded shoulders as the reference.
        Shape {
            x:(card.width-width*scale)/2
            width:240;height:24;scale:Math.min(1,card.width/480);transformOrigin:Item.TopLeft
            ShapePath {
                fillColor: "black";strokeColor: "transparent"
                startX: 0;startY: 0
                PathLine {x:240;y:0}
                PathQuad {x:232;y:8;controlX:232;controlY:0}
                PathQuad {x:216;y:24;controlX:232;controlY:24}
                PathLine {x:24;y:24}
                PathQuad {x:8;y:8;controlX:8;controlY:24}
                PathQuad {x:0;y:0;controlX:8;controlY:0}
            }
        }
        Button {
            id: locationButton
            objectName: "notchWeatherLocation"
            x:12;y:28;width:Math.min(cityLabel.implicitWidth+38,parent.width-32);height:26;padding:0
            Accessible.name: "Weather location and units"
            background: Rectangle {
                radius:8;color:locationButton.down?"#25FFFFFF":locationButton.hovered||locationPopup.visible?"#12FFFFFF":"transparent"
                border.width:locationButton.visualFocus?1:0;border.color:"#A0FFFFFF"
            }
            contentItem: Item {
                Text {
                    id:cityLabel;x:8;width:parent.width-30;height:parent.height
                    text:page.ready?page.weather.wxCity:"Weather"
                    color:"white";elide:Text.ElideRight;verticalAlignment:Text.AlignVCenter
                    font.family:page.host.family;font.pixelSize:14;font.weight:Font.Medium
                }
                NotchIcon {anchors.right:parent.right;anchors.rightMargin:7;anchors.verticalCenter:parent.verticalCenter;width:11;height:11;kind:"chevron";strokeWidth:2.5;ink:"#DAE9FB";rotation:locationPopup.visible?-90:90}
            }
            HoverHandler {cursorShape:Qt.PointingHandCursor}
            onClicked: {
                page.locationMode=page.weather && page.weather.locMode==="city"?"city":"auto";
                page.unit=page.weather && page.weather.tempUnit==="F"?"F":"C";
                cityInput.text=page.weather ? page.weather.cityName || "" : "";
                locationPopup.open();
            }
        }
        Text {
            objectName:"notchWeatherTemperature"
            x:20;y:51;width:parent.width-206;height:70
            visible:page.ready;text:page.ready ? page.weather.wxTemp+"°" : ""
            color:"white";font.family:page.host.family;font.pixelSize:62;font.weight:Font.Light
            verticalAlignment:Text.AlignVCenter
            font.features: { "tnum": 1 }
        }
        Column {
            objectName:"notchWeatherConditions"
            x:parent.width-186;y:60;width:166;spacing:5;visible:page.ready
            Row {
                anchors.right:parent.right;spacing:8;height:30
                WeatherIcon {anchors.verticalCenter:parent.verticalCenter;size:28;kind:page.info.k;tint:"white"}
                Text {objectName:"notchWeatherConditionLabel";width:Math.min(implicitWidth,130);height:parent.height;text:page.info.t;color:"white";verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight;font.family:page.host.family;font.pixelSize:15;font.weight:Font.Medium}
            }
            Text {objectName:"notchWeatherRange";width:parent.width;text:page.ready ? "H: "+page.weather.wxHi+"°   L: "+page.weather.wxLo+"°" : "";color:"#F0F5FC";horizontalAlignment:Text.AlignRight;font.family:page.host.family;font.pixelSize:12;font.weight:Font.Normal;font.features: { "tnum": 1 }}
        }
        Row {
            objectName:"notchWeatherHours"
            x:14;y:page.failed?124:132;width:parent.width-28;height:66;visible:page.ready
            Repeater {
                model:page.hours
                Item {
                    id:hour
                    required property var modelData
                    required property int index
                    objectName:"notchWeatherHour"+index
                    width:(card.width-28)/Math.max(1,page.hours.length);height:66
                    Text {objectName:"notchWeatherHourTime";anchors.horizontalCenter:parent.horizontalCenter;y:0;height:16;text:hour.modelData.h;color:sky.darkForecast?"#DFEAF5":hour.index===0?"#193C61":"#304E6C";font.family:page.host.family;font.pixelSize:12;font.weight:hour.index===0?Font.DemiBold:Font.Medium}
                    WeatherIcon {anchors.horizontalCenter:parent.horizontalCenter;y:21;size:24;kind:hour.modelData.k;tint:sky.darkForecast?"#EAF3FC":"#2A4F76"}
                    Text {objectName:"notchWeatherHourTemperature";anchors.horizontalCenter:parent.horizontalCenter;y:46;height:20;text:hour.modelData.t+"°";color:sky.darkForecast?"#F7FAFF":"#193C61";font.family:page.host.family;font.pixelSize:15;font.weight:hour.index===0?Font.DemiBold:Font.Medium;font.features: { "tnum": 1 }}
                }
            }
        }
        Text {
            x:20;y:191;width:parent.width-40;height:15
            visible:page.ready && page.failed;text:"Saved forecast · tap location to refresh"
            color:sky.darkForecast?"#DFEAF5":"#304E6C";font.family:page.host.family;font.pixelSize:11;elide:Text.ElideRight
        }
        Column {
            anchors.centerIn:parent;anchors.verticalCenterOffset:18;width:parent.width-48;spacing:10
            visible:!page.ready
            Text {width:parent.width;text:page.busy?"Getting your forecast…":page.failed?"Weather unavailable":"Loading weather…";color:"white";horizontalAlignment:Text.AlignHCenter;font.family:page.host.family;font.pixelSize:17;font.weight:Font.DemiBold}
            Text {width:parent.width;text:page.failed&&!page.busy?"Check your connection or choose a city.":"Current conditions and the next six hours";color:"#E2EDFD";horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WordWrap;font.family:page.host.family;font.pixelSize:13}
            NotchPomodoroButton {objectName:"notchWeatherRetry";anchors.horizontalCenter:parent.horizontalCenter;visible:page.failed&&!page.busy;text:"Try Again";fill:"#30FFFFFF";family:page.host.family;reducedMotion:page.host.reducedMotion;onClicked:if(page.weather)page.weather.refresh()}
        }
    }
    NotchSettingsPopup {
        id:locationPopup;objectName:"notchWeatherSettings";host:page.host;control:locationButton
        title:"Weather";acceptText:"Apply"
        width:Math.min(344,parent?parent.width-16:344)
        height:Math.min(preferences.implicitHeight+2*contentPadding+tailHeight,Math.max(140,screenBottomLimit-desiredY-8))
        acceptable:!!page.weather && (page.locationMode==="auto" || cityInput.text.trim()!=="")
        onSaveRequested: {
            page.weather.tempUnit=page.unit;
            page.weather.locMode=page.locationMode;
            if(page.locationMode==="city")page.weather.cityName=cityInput.text.trim();
            page.weather.refreshSoon();close();
        }
        contentItem: Flickable {
            contentHeight:preferences.implicitHeight+2*locationPopup.contentPadding+locationPopup.tailHeight
            clip:true;boundsBehavior:Flickable.StopAtBounds
            transform:Scale {origin.x:locationPopup.pointerX;origin.y:0;xScale:locationPopup.elasticScaleX;yScale:locationPopup.elasticScaleY}
            ScrollBar.vertical:ScrollBar {policy:ScrollBar.AsNeeded}
            Column {
                id:preferences
                x:locationPopup.contentPadding;y:locationPopup.contentPadding+locationPopup.tailHeight
                width:parent.width-2*locationPopup.contentPadding;spacing:16
                Item {
                    width:parent.width;height:30
                    Text {anchors.verticalCenter:parent.verticalCenter;text:"Weather";color:locationPopup.foreground;font.family:page.host.family;font.pixelSize:18;font.weight:Font.DemiBold}
                    MouseArea {
                        objectName:"notchWeatherSettingsDragHandle";width:parent.width-40;height:parent.height;preventStealing:true
                        cursorShape:pressed?Qt.ClosedHandCursor:Qt.OpenHandCursor
                        onPressed:mouse=>{locationPopup.pressPosition=mapToItem(locationPopup.parent,mouse.x,mouse.y);locationPopup.dragOrigin=Qt.point(locationPopup.x,locationPopup.y);}
                        onPositionChanged:mouse=>{if(pressed)locationPopup.movePanel(mapToItem(locationPopup.parent,mouse.x,mouse.y));}
                        onReleased:locationPopup.releasePanel();onCanceled:locationPopup.releasePanel()
                    }
                    NotchPomodoroButton {
                        objectName:"notchWeatherRefresh";anchors.right:parent.right;width:30;height:30
                        symbol:"reset";iconSize:17;iconStrokeWidth:2.2;fill:"transparent";ink:locationPopup.secondary
                        enabled:!!page.weather&&!page.busy;reducedMotion:page.host.reducedMotion;family:page.host.family
                        Accessible.name:page.busy?"Refreshing weather":"Refresh weather"
                        onClicked:page.weather.refresh()
                    }
                }
                Column {
                    width:parent.width;spacing:8
                    Text {text:"Location";color:locationPopup.secondary;font.family:page.host.family;font.pixelSize:12;font.weight:Font.Medium}
                    Rectangle {
                        id:locationOptions;width:parent.width;height:112;radius:10
                        color:locationPopup.dark?"#20000000":"#08000000"
                        border.width:1;border.color:locationPopup.dark?"#10FFFFFF":"#10000000"
                        Button {
                            id:autoOption;objectName:"notchWeatherAuto";x:4;y:4;width:parent.width-8;height:52;padding:0
                            Accessible.name:"Automatic location, based on your IP address";Accessible.role:Accessible.RadioButton;Accessible.checked:page.locationMode==="auto"
                            background:Rectangle {radius:6;color:autoOption.down?"#20FFFFFF":autoOption.hovered||autoOption.visualFocus?(locationPopup.dark?"#10FFFFFF":"#08000000"):"transparent"}
                            contentItem:Item {
                                Text {x:12;y:7;text:"Automatic";color:locationPopup.foreground;font.family:page.host.family;font.pixelSize:14;font.weight:Font.Medium}
                                Text {x:12;y:28;text:"Based on your IP address";color:locationPopup.secondary;font.family:page.host.family;font.pixelSize:12}
                                NotchIcon {anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter;width:18;height:18;kind:"checkmark";strokeWidth:2.5;ink:locationPopup.foreground;visible:page.locationMode==="auto"}
                            }
                            HoverHandler {cursorShape:Qt.PointingHandCursor}
                            onClicked:page.locationMode="auto"
                        }
                        Rectangle {x:16;y:60;width:parent.width-32;height:1;color:locationPopup.dark?"#12FFFFFF":"#12000000"}
                        Button {
                            id:cityOption;objectName:"notchWeatherCityMode";x:4;y:64;width:parent.width-8;height:44;padding:0
                            Accessible.name:"Choose a city";Accessible.role:Accessible.RadioButton;Accessible.checked:page.locationMode==="city"
                            background:Rectangle {radius:6;color:cityOption.down?"#20FFFFFF":cityOption.hovered||cityOption.visualFocus?(locationPopup.dark?"#10FFFFFF":"#08000000"):"transparent"}
                            contentItem:Item {
                                Text {x:12;anchors.verticalCenter:parent.verticalCenter;text:"Choose a city";color:locationPopup.foreground;font.family:page.host.family;font.pixelSize:14;font.weight:Font.Medium}
                                NotchIcon {anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter;width:18;height:18;kind:"checkmark";strokeWidth:2.5;ink:locationPopup.foreground;visible:page.locationMode==="city"}
                            }
                            HoverHandler {cursorShape:Qt.PointingHandCursor}
                            onClicked:{page.locationMode="city";cityInput.forceActiveFocus();}
                        }
                    }
                    NotchInput {id:cityInput;objectName:"notchWeatherCity";width:parent.width;height:36;visible:page.locationMode==="city";family:page.host.family;dark:locationPopup.dark;placeholderText:"City name, e.g. Jakarta";maximumLength:100;onAccepted:if(locationPopup.acceptable)locationPopup.saveRequested()}
                }
                Item {
                    width:parent.width;height:34
                    Text {anchors.verticalCenter:parent.verticalCenter;text:"Temperature";color:locationPopup.foreground;font.family:page.host.family;font.pixelSize:14;font.weight:Font.Medium}
                    Rectangle {
                        anchors.right:parent.right;width:96;height:32;radius:10
                        color:locationPopup.dark?"#30000000":"#10000000"
                        Row {
                            x:2;y:2;spacing:2
                            NotchPomodoroButton {objectName:"notchWeatherCelsius";width:45;height:28;cornerRadius:8;text:"°C";fill:page.unit==="C"?"#F5F5F7":"transparent";ink:page.unit==="C"?"#20242B":locationPopup.secondary;family:page.host.family;reducedMotion:page.host.reducedMotion;Accessible.name:"Celsius";Accessible.selected:page.unit==="C";onClicked:page.unit="C"}
                            NotchPomodoroButton {objectName:"notchWeatherFahrenheit";width:45;height:28;cornerRadius:8;text:"°F";fill:page.unit==="F"?"#F5F5F7":"transparent";ink:page.unit==="F"?"#20242B":locationPopup.secondary;family:page.host.family;reducedMotion:page.host.reducedMotion;Accessible.name:"Fahrenheit";Accessible.selected:page.unit==="F";onClicked:page.unit="F"}
                        }
                    }
                }
                Rectangle {width:parent.width;height:1;color:locationPopup.dark?"#18FFFFFF":"#18000000"}
                Item {
                    width:parent.width;height:32
                    Text {anchors.verticalCenter:parent.verticalCenter;text:'<a href="https://open-meteo.com/">Open-Meteo</a>';color:locationPopup.secondary;linkColor:locationPopup.secondary;font.family:page.host.family;font.pixelSize:11;onLinkActivated:link=>Quickshell.execDetached(["xdg-open",link])}
                    Row {
                        anchors.right:parent.right;spacing:8
                        NotchPomodoroButton {objectName:"notchWeatherSettingsCancel";text:"Cancel";height:32;fill:"transparent";ink:locationPopup.secondary;family:page.host.family;reducedMotion:page.host.reducedMotion;onClicked:locationPopup.close()}
                        NotchPomodoroButton {objectName:"notchWeatherSettingsSave";text:"Apply";height:32;fill:locationPopup.dark?"#F5F5F7":"#242427";ink:locationPopup.dark?"#20242B":"#FFFFFF";family:page.host.family;reducedMotion:page.host.reducedMotion;enabled:locationPopup.acceptable;onClicked:locationPopup.saveRequested()}
                    }
                }
            }
        }
    }
}
