pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "Common" as Common

Scope {
    id: root
    required property string appKind
    property var hub: null
    property alias window: win
    readonly property bool dark: hub && hub.dock ? hub.dock.darkMode : Common.IconStyle.systemDark
    readonly property color fg: dark ? "#f5f5f7" : "#232327"
    readonly property color secondary: dark ? "#a2a2af" : "#676773"
    readonly property color bg: dark ? "#202024" : "#fafafa"
    readonly property string appTitle: "MacShell " + appKind.charAt(0).toUpperCase()+appKind.slice(1)
    property var rows: []
    property var current: ({})
    property var preview: null
    property var queue: []
    property string action: ""
    property string message: ""
    property string query: ""
    property date month: new Date(new Date().getFullYear(),new Date().getMonth(),1)
    property bool weekView: false
    property string selectedDate: ""
    property bool composing: false
    property bool shareActive: false
    property string shareUrl: ""
    property string shareToken: ""
    property string shareAlbum: ""
    property string exportOperation: "copy"
    component StudioButton: Button {
        id: control
        implicitHeight: 32
        leftPadding: 13; rightPadding: 13
        contentItem: Text { text: control.text; color: control.enabled ? root.fg : root.secondary; opacity: control.enabled ? 1 : 0.5; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle {
            radius: 9
            color: control.down ? (root.dark ? "#50505b" : "#d7d7df") : control.hovered ? (root.dark ? "#42424c" : "#e5e5ed") : root.dark ? "#35353d" : "#ffffff"
            border.width: Common.DesktopPreferences.showBorders ? 1.4 : 0.7
            border.color: root.dark ? "#60606c" : "#cfcfd8"
            Behavior on color { ColorAnimation { duration: Common.DesktopPreferences.anim(75) } }
        }
    }
    component StudioField: TextField {
        id: field
        implicitHeight: 36; color: root.fg; font.pixelSize: 13
        placeholderTextColor: root.secondary; leftPadding: 12; rightPadding: 12
        background: Rectangle { radius: 9; color: root.dark ? "#2b2b32" : "white"; border.width: field.activeFocus ? 1.5 : 0.7; border.color: field.activeFocus ? "#4388ff" : root.dark ? "#4a4a56" : "#d5d5df" }
    }
    component StudioText: TextArea {
        color: root.fg; font.pixelSize: 14; padding: 12
        placeholderTextColor: root.secondary
        background: Rectangle { radius: 10; color: root.dark ? "#292930" : "white"; border.width: 0.7; border.color: root.dark ? "#454550" : "#dddde5" }
    }
    function request(action,data) { queue=queue.concat([{action:action,data:data || {}}]);pump(); }
    function pump() {
        if(worker.running || !queue.length) return;
        const job=queue[0];queue=queue.slice(1);action=job.action;
        worker.command=["python3","-B",Quickshell.shellPath("bin/studio.py"),job.action,"--json",JSON.stringify(job.data)];
        worker.running=true;
    }
    function fileUrl(path) { return "file://" + String(path).split("/").map(encodeURIComponent).join("/"); }
    function dateString(d) { return Qt.formatDate(d,"yyyy-MM-dd"); }
    function refresh() {
        if(appKind==="calendar") {
            const start = weekView ? new Date(month.getFullYear(),month.getMonth(),month.getDate()-((month.getDay()+6)%7)) : new Date(month.getFullYear(),month.getMonth(),1);
            const end = weekView ? new Date(start.getFullYear(),start.getMonth(),start.getDate()+6) : new Date(month.getFullYear(),month.getMonth()+1,0);
            request("calendar.list",{from:dateString(start),to:dateString(end)});
        }
        else request(appKind+".list",{query:query});
    }
    function open() { win.visible=true;win.raise();win.requestActivate();refresh(); }
    function select(row) {
        current=row;composing=false;
        if(appKind==="calendar") { titleInput.text=row.title || "";startInput.text=row.start || "";endInput.text=row.end || "";notesInput.text=row.notes || "";allDay.checked=!!row.allDay;recurrence.currentIndex=["","FREQ=DAILY","FREQ=WEEKLY","FREQ=MONTHLY"].indexOf(row.rrule || ""); }
        if(appKind==="mail") { subjectInput.text=row.subject || "";toInput.text=row.recipient || "";bodyInput.text=row.body || "";composing=row.folder==="Drafts"; }
    }
    Process {
        id:worker
        stdout:StdioCollector {
            onStreamFinished: {
                try {
                    const r=JSON.parse(text);
                    if(r.error) { root.message=r.error;return; }
                    if(root.action.endsWith(".list")) root.rows=r.events || r.messages || r.photos || [];
                    else if(root.action==="calendar.parse") {
                        root.preview=r.preview; if(root.preview) {
                            titleInput.text=root.preview.title;startInput.text=root.preview.start;endInput.text=root.preview.end;notesInput.text="";root.current=({});allDay.checked=!!root.preview.allDay;recurrence.currentIndex=0;
                            root.message=(root.preview.ambiguities || []).join(" · ");
                        }
                    } else {
                        if(root.action==="mail.draft" && r.id) root.current=Object.assign({},root.current,{id:r.id,folder:"Drafts"});
                        if((root.action==="calendar.new" || root.action==="calendar.save") && r.event) {root.current=r.event;root.preview=null;}
                        root.message=r.exported ? "Exported: "+r.exported : r.imported!==undefined ? "Imported "+r.imported+" items" : "Saved";root.refresh(); }
                } catch(e) {root.message="Could not read the local data response.";}
            }
        }
        onExited:Qt.callLater(root.pump)
    }
    // The server exists only during explicit sharing, and is owned by the shell.
    Process {
        id:shareServer
        command:["python3","-B","-u",Quickshell.shellPath("bin/album_lan.py"),"--album",root.shareAlbum,"--token",root.shareToken].concat(allowUploads.checked ? ["--allow-upload"] : [])
        stdout:SplitParser { onRead:data=>{try{const r=JSON.parse(data);root.shareUrl=r.url || "";root.message=r.error || "Album sharing is active on your LAN. Use this host's LAN address.";}catch(e){}} }
        onExited:{root.shareActive=false;root.shareUrl="";}
    }
    FileDialog {
        id:importDialog
        nameFilters:root.appKind==="mail" ? ["Email archives (*.eml *.mbox *.mbx)"] : root.appKind==="calendar" ? ["Calendar (*.ics)"] : ["Images (*.png *.jpg *.jpeg *.webp *.bmp *.tiff)"]
        onAccepted:root.request(root.appKind+".import",{path:selectedFile.toString()})
    }
    FolderDialog { id:folderDialog;onAccepted:root.request("photos.import",{path:selectedFolder.toString()}) }
    FileDialog {
        id:exportDialog;fileMode:FileDialog.SaveFile
        nameFilters:root.appKind==="calendar" ? ["Calendar (*.ics)"] : ["PNG image (*.png)","JPEG image (*.jpg)"]
        onAccepted:root.request(root.appKind+".export",{path:selectedFile.toString(),id:root.current.id,operation:root.exportOperation})
    }
    ApplicationWindow {
        id:win;title:root.appTitle;width:1000;height:650;minimumWidth:740;minimumHeight:500
        visible:false;color:"transparent";flags:Qt.Window | Qt.FramelessWindowHint
        background: null
        palette.window: root.bg
        palette.windowText: root.fg
        palette.text: root.fg
        palette.buttonText: root.fg
        palette.base: root.dark ? "#292930" : "#ffffff"
        palette.alternateBase: root.dark ? "#35353d" : "#ededf0"
        palette.button: root.dark ? "#35353d" : "#ffffff"
        palette.mid: root.dark ? "#60606c" : "#cfcfd8"
        palette.dark: root.dark ? "#60606c" : "#cfcfd8"
        palette.light: root.dark ? "#42424c" : "#e5e5ed"
        palette.highlight: Common.ThemeColors.accentFor("shell")
        palette.highlightedText: "white"
        palette.placeholderText: root.secondary
        palette.disabled.text: root.secondary
        palette.disabled.windowText: root.secondary
        Rectangle {
            anchors.fill:parent;radius:16;color:root.bg
            border.width:Common.DesktopPreferences.showBorders ? 2 : 1
            border.color:root.dark ? "#555565" : "#c8c8d0"
            ColumnLayout {
                anchors.fill:parent;anchors.margins:1;spacing:0
                Rectangle {
                    Layout.fillWidth:true;Layout.preferredHeight:52;radius:15;color:root.dark ? "#2c2c32" : "#ededf0"
                    MouseArea { anchors.fill:parent;onPressed:win.startSystemMove();onDoubleClicked:win.visibility=win.visibility===Window.Maximized ? Window.Windowed : Window.Maximized }
                    RowLayout {
                        anchors.fill:parent;anchors.leftMargin:16;anchors.rightMargin:16;spacing:12
                        WindowControls {
                            dark:root.dark
                            onCloseClicked:win.close()
                            onMinimizeClicked: {
                                if (root.hub && root.hub.dock && root.hub.dock.minimize)
                                    root.hub.dock.minimize.minimizeFocused();
                                else win.showMinimized();
                            }
                            onZoomClicked:win.visibility=win.visibility===Window.Maximized ? Window.Windowed : Window.Maximized
                        }
                        Label { text:root.appTitle;color:root.fg;font.pixelSize:16;font.bold:true;Layout.fillWidth:true }
                        BusyIndicator { running:worker.running;Layout.preferredWidth:22;Layout.preferredHeight:22 }
                        StudioButton { text:"Refresh";onClicked:root.refresh() }
                        StudioButton { text:"Import";onClicked:importDialog.open() }
                        StudioButton { text:"Library";visible:root.appKind==="photos";onClicked:root.current=({}) }
                        StudioButton { text:"Folder";visible:root.appKind==="photos";onClicked:folderDialog.open() }
                        StudioButton { text:"Export ICS";visible:root.appKind==="calendar";onClicked:exportDialog.open() }
                        StudioButton { text:root.appKind==="mail" ? "New draft" : "New event";visible:root.appKind!=="photos";onClicked:{root.current=({});root.preview=null;allDay.checked=false;recurrence.currentIndex=0;titleInput.text="";startInput.text=new Date().toISOString();endInput.text=new Date(Date.now()+3600000).toISOString();notesInput.text="";subjectInput.text="";toInput.text="";bodyInput.text="";root.composing=true;} }
                    }
                }
                // Calendar month navigation and actual day cells.
                ColumnLayout {
                    visible:root.appKind==="calendar";Layout.fillWidth:true;Layout.margins:12;spacing:5
                    RowLayout {
                        Layout.fillWidth:true
                        StudioButton {text:"‹";onClicked:{root.month=root.weekView ? new Date(root.month.getFullYear(),root.month.getMonth(),root.month.getDate()-7) : new Date(root.month.getFullYear(),root.month.getMonth()-1,1);root.refresh();}}
                        Label { text:root.weekView ? "Week of "+Qt.formatDate(root.month,"d MMMM yyyy") : Qt.formatDate(root.month,"MMMM yyyy");color:root.fg;font.pixelSize:19;Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter }
                        Basic.ComboBox {model:["Month","Week"];onActivated:{root.weekView=currentIndex===1;root.month=new Date();root.selectedDate="";root.refresh();}}
                        StudioButton {text:"Today";onClicked:{root.month=root.weekView ? new Date() : new Date(new Date().getFullYear(),new Date().getMonth(),1);root.selectedDate="";root.refresh();}}
                        StudioButton {text:"›";onClicked:{root.month=root.weekView ? new Date(root.month.getFullYear(),root.month.getMonth(),root.month.getDate()+7) : new Date(root.month.getFullYear(),root.month.getMonth()+1,1);root.refresh();}}
                    }
                    GridLayout {
                        columns:7;Layout.fillWidth:true;rowSpacing:2;columnSpacing:2
                        Repeater {model:["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];Label{required property string modelData;text:modelData;color:root.secondary;Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter}}
                        Repeater {
                            model:root.weekView ? 7 : 42
                            delegate:Rectangle {
                                required property int index
                                readonly property date day:root.weekView ? new Date(root.month.getFullYear(),root.month.getMonth(),root.month.getDate()-((root.month.getDay()+6)%7)+index) : new Date(root.month.getFullYear(),root.month.getMonth(),1-((new Date(root.month.getFullYear(),root.month.getMonth(),1).getDay()+6)%7)+index)
                                readonly property string iso:root.dateString(day)
                                readonly property int count:root.rows.filter(e=>String(e.start).slice(0,10)===iso).length
                                Layout.fillWidth:true;Layout.preferredHeight:29;radius:7
                                color:root.selectedDate===iso ? "#3478f6" : root.dateString(new Date())===iso ? "#303478f6" : "transparent"
                                Label {anchors.centerIn:parent;text:parent.day.getDate()+(parent.count ? " •" : "");color:root.selectedDate===parent.iso ? "white" : parent.day.getMonth()===root.month.getMonth() ? root.fg : root.secondary}
                                MouseArea {anchors.fill:parent;onClicked:root.selectedDate=root.selectedDate===parent.iso ? "" : parent.iso}
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth:true
                        StudioField {id:sentence;Layout.fillWidth:true;placeholderText:"Describe an event, e.g. Meeting tomorrow at 10am for 1 hour";onAccepted:root.request("calendar.parse",{text:text})}
                        StudioButton {text:"Preview";onClicked:root.request("calendar.parse",{text:sentence.text})}
                    }
                }
                SplitView {
                    Layout.fillWidth:true;Layout.fillHeight:true
                    ScrollView {
                        SplitView.preferredWidth:300;SplitView.minimumWidth:230
                        ListView {
                            id:itemList;clip:true;spacing:4;boundsBehavior:Flickable.DragAndOvershootBounds
                            PullToRefresh { target:itemList;parent:itemList.parent;anchors.horizontalCenter:parent.horizontalCenter;busy:worker.running;onRefreshRequested:root.refresh() }
                            model:root.appKind==="calendar" && root.selectedDate ? root.rows.filter(e=>String(e.start).slice(0,10)===root.selectedDate) : root.rows
                            delegate:ItemDelegate {
                                required property var modelData;width:itemList.width;height:root.appKind==="photos" ? 100 : 68
                                highlighted:root.current.id===modelData.id
                                background:Rectangle {radius:10;color:root.current.id===modelData.id ? (root.dark ? "#304773" : "#e0eaff") : "transparent"}
                                contentItem:RowLayout {
                                    Image {visible:root.appKind==="photos";Layout.preferredWidth:90;Layout.fillHeight:true;source:root.appKind==="photos" ? root.fileUrl(modelData.path) : "";sourceSize:Qt.size(180,180);asynchronous:true;fillMode:Image.PreserveAspectFit}
                                    ColumnLayout {Layout.fillWidth:true
                                        Label {text:modelData.title || modelData.subject || "Untitled";color:root.fg;elide:Text.ElideRight;Layout.fillWidth:true;font.bold:true}
                                        Label {text:root.appKind==="calendar" ? Qt.formatDateTime(new Date(modelData.start),"ddd d MMM HH:mm") : root.appKind==="mail" ? modelData.folder+" · "+modelData.sender : modelData.album;color:root.secondary;elide:Text.ElideRight;Layout.fillWidth:true;font.pixelSize:11}
                                    }
                                }
                                onClicked:root.select(modelData)
                            }
                            Label {anchors.centerIn:parent;visible:itemList.count===0;text:root.appKind==="calendar" ? "No events. Add one above." : root.appKind==="mail" ? "Import EML/MBOX or create a draft." : "Import a photo or select a folder.";color:root.secondary;width:parent.width-24;wrapMode:Text.WordWrap;horizontalAlignment:Text.AlignHCenter}
                        }
                    }
                    ScrollView {
                        id:editorScroll
                        SplitView.fillWidth:true;clip:true;contentWidth:availableWidth
                        ColumnLayout {
                            width:editorScroll.availableWidth-32;x:16;y:14;spacing:12
                            ColumnLayout {
                                visible:root.appKind==="calendar";Layout.fillWidth:true
                                Label {text:"Event details · Review before saving";color:root.fg;font.bold:true}
                                StudioField {id:titleInput;Layout.fillWidth:true;placeholderText:"Event title"}
                                StudioField {id:startInput;Layout.fillWidth:true;placeholderText:"Start · ISO date/time with offset"}
                                StudioField {id:endInput;Layout.fillWidth:true;placeholderText:"End · ISO date/time with offset"}
                                RowLayout {CheckBox {id:allDay;text:"All day"} Basic.ComboBox {id:recurrence;model:["Once","Daily","Weekly","Monthly"]}}
                                StudioText {id:notesInput;Layout.fillWidth:true;placeholderText:"Notes";wrapMode:TextEdit.Wrap;Layout.preferredHeight:80}
                                RowLayout {
                                    StudioButton {text:root.current.id ? "Save changes" : "Create event";enabled:titleInput.text.trim()!=="";onClicked:root.request(root.current.id ? "calendar.save" : "calendar.new",{id:root.current.id,title:titleInput.text,start:startInput.text,end:endInput.text,notes:notesInput.text,allDay:allDay.checked,rrule:["","FREQ=DAILY","FREQ=WEEKLY","FREQ=MONTHLY"][Math.max(0,recurrence.currentIndex)],reminders:root.preview ? root.preview.reminders : root.current.reminders || [0]})}
                                    StudioButton {text:"Delete event";visible:!!root.current.id;onClicked:deleteConfirmation.open()}
                                }
                            }
                            ColumnLayout {
                                visible:root.appKind==="mail";Layout.fillWidth:true
                                Label {text:root.composing ? "Local draft" : root.current.sender || "Mail · Offline library";color:root.secondary;Layout.fillWidth:true;wrapMode:Text.WordWrap}
                                StudioField {id:toInput;Layout.fillWidth:true;placeholderText:"To";readOnly:!root.composing}
                                StudioField {id:subjectInput;Layout.fillWidth:true;placeholderText:"Subject";readOnly:!root.composing}
                                StudioText {id:bodyInput;Layout.fillWidth:true;Layout.preferredHeight:290;wrapMode:TextEdit.Wrap;selectByMouse:true;readOnly:!root.composing;textFormat:TextEdit.PlainText;placeholderText:"Email content"}
                                RowLayout {
                                    StudioButton {text:"Save draft";visible:root.composing;onClicked:root.request("mail.draft",{id:root.current.folder==="Drafts" ? root.current.id : "",subject:subjectInput.text,recipient:toInput.text,body:bodyInput.text})}
                                    StudioButton {text:"Draft reply with Luma";enabled:!!root.current.id && !!root.hub;onClicked:root.hub.luma.open("Write a reply draft to this email:\n"+String(root.current.body || "").slice(0,2800))}
                                    StudioButton {text:"Delete";visible:!!root.current.id;onClicked:deleteConfirmation.open()}
                                }
                                Label {text:"Reads local archives and saves drafts. Live sending/sync requires an account connector; no message is sent from this view.";color:root.secondary;wrapMode:Text.WordWrap;Layout.fillWidth:true}
                            }
                            GridView {
                                id:photoGrid
                                visible:root.appKind==="photos" && !root.current.id
                                Layout.fillWidth:true;Layout.preferredHeight:Math.max(300,win.height-120)
                                cellWidth:Math.max(150,width/3);cellHeight:165;clip:true;model:root.rows
                                delegate:Item {
                                    required property var modelData
                                    width:photoGrid.cellWidth;height:photoGrid.cellHeight
                                    Rectangle {anchors.fill:parent;anchors.margins:5;radius:12;color:root.dark ? "#303039" : "#ededf3"
                                        Image {anchors.fill:parent;anchors.margins:8;source:root.fileUrl(modelData.path);sourceSize:Qt.size(360,280);fillMode:Image.PreserveAspectFit;asynchronous:true}
                                    }
                                    MouseArea {anchors.fill:parent;onClicked:root.select(modelData)}
                                }
                            }
                            ColumnLayout {
                                visible:root.appKind==="photos" && !!root.current.id;Layout.fillWidth:true
                                Image {Layout.fillWidth:true;Layout.preferredHeight:330;source:root.current.path ? root.fileUrl(root.current.path) : "";sourceSize:Qt.size(1600,1000);fillMode:Image.PreserveAspectFit;asynchronous:true}
                                StudioField {id:albumName;Layout.fillWidth:true;placeholderText:"Album name";text:root.current.album || "Library"}
                                RowLayout {
                                    StudioButton {text:"Set album";enabled:!!root.current.id;onClicked:root.request("photos.album",{id:root.current.id,album:albumName.text})}
                                    Basic.ComboBox {id:editOperation;model:["Copy original","Rotate 90°","Square crop"]}
                                    StudioButton {text:"Export copy";enabled:!!root.current.id;onClicked:{root.exportOperation=["copy","rotate","square"][editOperation.currentIndex];exportDialog.open();}}
                                }
                                CheckBox {id:allowUploads;text:"Allow LAN participants to upload photos";enabled:!root.shareActive}
                                RowLayout {
                                    StudioButton {text:root.shareActive ? "Stop LAN sharing" : "Share album on LAN";enabled:!!root.current.id || root.shareActive;onClicked:{
                                        if(root.shareActive){shareServer.running=false;root.shareActive=false;}
                                        else{root.shareAlbum=albumName.text;root.shareToken="";root.shareActive=true;shareServer.running=true;}
                                    }}
                                    Label {text:root.shareUrl;color:root.secondary;Layout.fillWidth:true;wrapMode:Text.WrapAnywhere}
                                }
                                Label {text:"Edits export a new file. Generative Clean Up, Extend and Spatial Reframing require additional local models and are not enabled yet.";color:root.secondary;wrapMode:Text.WordWrap;Layout.fillWidth:true}
                            }
                        }
                    }
                }
                Label {Layout.fillWidth:true;Layout.margins:10;text:root.message;color:root.secondary;wrapMode:Text.WordWrap;visible:text!==""}
            }
        }
        Basic.Dialog {id:deleteConfirmation;title:"Delete selected item?";modal:true;anchors.centerIn:parent;standardButtons:Dialog.Ok | Dialog.Cancel;onAccepted:{root.request(root.appKind+".delete",{id:root.current.id});root.current=({});}}
        Shortcut {sequence:"Escape";onActivated:win.close()}
        Shortcut {sequence:"StandardKey.Refresh";onActivated:root.refresh()}
    }
}
