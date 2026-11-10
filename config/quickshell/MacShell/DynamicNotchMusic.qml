pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls
import "Common" as GlassCommon
import "Common/LyricsFocus.js" as LyricFocus
import QtQuick.Effects
import Quickshell.Services.Mpris
import "DynamicNotchState.js" as State

Item {
    id: music
    required property var host
    readonly property var player: host.player
    readonly property var service: host.bar && host.bar.mediaService ? host.bar.mediaService : null
    readonly property var widgets: host.bar && host.bar.hub ? host.bar.hub.widgets || null : null
    readonly property real progress: player && player.length > 0 ? Math.max(0, Math.min(1, player.position / player.length)) : 0
    property bool lyricsOpen: false
    property bool keepCompact: false
    onPlayerChanged: if(!player)keepCompact=false
    property bool localVisualizer: true
    readonly property bool sideOpen: lyricsOpen
    readonly property bool narrow:host.screenWidth<620*host.uiScale
    readonly property bool visualizer: service ? service.visualizer : localVisualizer
    readonly property bool canLyrics: !!widgets && widgets.player === player
    readonly property var lyricLines: canLyrics ? widgets.lyricsLines : []
    readonly property bool lyricsSynced: canLyrics && widgets.lyricsSynced
    readonly property real lyricPosition: canLyrics && typeof widgets.lyricsPosition === "number" ? widgets.lyricsPosition : player ? player.position : 0
    readonly property int lyricIndex: State.lyricIndex(lyricLines, lyricPosition, lyricsSynced)
    readonly property string artistAlbum: player ? [player.trackArtist,player.trackAlbum].filter(v=>!!v).join(" · ") || player.identity || "Media player" : "Open a music app to start listening"
    readonly property real fullWidth: host.fullMetrics.width
    readonly property real contentInset:Geometry.inset(host.mode,true)
    readonly property real layoutWidth:narrow?440:sideOpen?740:640
    readonly property real layoutScale: Math.min(host.uiScale,fullWidth/layoutWidth)
    readonly property real lyricsExtraHeight:narrow?80:40
    readonly property var outputs: host.bar && host.bar.audioOutputs ? host.bar.audioOutputs : []
    function toggleLyrics() { host.transitionAction(function(){music.lyricsOpen=!music.lyricsOpen;}); }
    function formatTime(seconds) {
        const s=Math.max(0,Math.floor(seconds)),m=Math.floor(s/60);
        return (m<10?"0":"")+m+":"+(s%60<10?"0":"")+s%60;
    }
    function cycleRepeat() { if(player && player.loopSupported)player.loopState=player.loopState===MprisLoopState.None?MprisLoopState.Playlist:player.loopState===MprisLoopState.Playlist?MprisLoopState.Track:MprisLoopState.None; }
    objectName:"notchMusic"
    clip:true
    Binding { target:music.widgets;property:"notchLyricsWanted";value:music.lyricsOpen && music.visible && music.host.available && music.host.expanded;when:!!music.widgets;restoreMode:Binding.RestoreBindingOrValue }
    Timer {
        interval:music.lyricsOpen && music.host.expanded?250:1000;repeat:true
        running:music.visible && music.host.available && !!music.player && music.player.isPlaying && music.player.positionSupported
        onTriggered:music.player.positionChanged()
    }
    property var spectrumOwner:null
    property bool spectrumCounted:false
    readonly property bool spectrumDemand: visible && host.available && !!player && player.isPlaying && !host.reducedMotion && (!host.expanded || visualizer && !sideOpen)
    function syncSpectrum() {
        if(spectrumOwner!==service){if(spectrumOwner && spectrumCounted)spectrumOwner.spectrumClients=Math.max(0,spectrumOwner.spectrumClients-1);spectrumOwner=service;spectrumCounted=false;}
        const wanted=spectrumDemand && !!spectrumOwner;
        if(wanted!==spectrumCounted){if(spectrumOwner)spectrumOwner.spectrumClients=Math.max(0,spectrumOwner.spectrumClients+(wanted?1:-1));spectrumCounted=wanted;}
    }
    onSpectrumDemandChanged:syncSpectrum()
    onServiceChanged:syncSpectrum()
    Component.onCompleted:syncSpectrum()
    Component.onDestruction:if(spectrumOwner && spectrumCounted)spectrumOwner.spectrumClients=Math.max(0,spectrumOwner.spectrumClients-1)

    // Compact controls stay interactive without opening the expanded player.
    Item {
        id:compact
        width:Math.min(324*music.host.uiScale,music.width);height:music.host.bar?music.host.bar.barHeight:28
        anchors.centerIn:parent
        visible:!music.host.expanded
        NotchMediaArt {x:16;y:(parent.height-height)/2;width:20;height:20;source:music.player?music.player.trackArtUrl:""}
        Text {objectName:"notchMusicCompactTitle";x:43;width:Math.max(15,parent.width-177);height:parent.height;text:music.player?music.player.trackTitle||"Now Playing":"Media";color:"white";font.family:music.host.family;font.pixelSize:11;font.weight:Font.DemiBold;elide:Text.ElideRight;verticalAlignment:Text.AlignVCenter}
        Row {
            anchors.right:parent.right;anchors.rightMargin:14;anchors.verticalCenter:parent.verticalCenter;spacing:0
            Item {
                id:compactWave;objectName:"notchMusicCompactWave"
                width:20;height:20;anchors.verticalCenter:parent.verticalCenter
                readonly property bool playing:!!music.player && music.player.isPlaying
                readonly property bool responsive:visible && music.visible && music.host.available && !music.host.expanded && playing && !music.host.reducedMotion && !!music.service
                opacity:playing?1:0.35
                function level(index) {
                    if(!responsive)return 0;
                    const start=Math.floor(index*24/5),end=Math.floor((index+1)*24/5);
                    let sum=0;
                    for(let i=start;i<end;i++){const value=Number(music.service.bands[i]||0);sum+=value*value;}
                    return Math.min(1,Math.sqrt(sum/Math.max(1,end-start))*1.6);
                }
                Row {
                    anchors.centerIn:parent;spacing:2
                    Repeater {
                        model:5
                        Rectangle {
                            required property int index
                            objectName:"notchMusicCompactWaveBar"+index
                            width:2;radius:1;anchors.verticalCenter:parent.verticalCenter
                            gradient:Gradient {
                                GradientStop {position:0;color:"#FFE66B"}
                                GradientStop {position:0.5;color:"#FFB52E"}
                                GradientStop {position:1;color:"#FF7A18"}
                            }
                            height:compactWave.responsive?4+14*compactWave.level(index):[5,10,16,10,5][index]
                            Behavior on height {NumberAnimation {duration:music.host.reducedMotion?0:100;easing.type:Easing.OutCubic}}
                        }
                    }
                }
            }
            NotchMediaButton {objectName:"notchMusicCompactPrevious";host:music.host;symbol:"previous";iconSize:19;implicitWidth:26;implicitHeight:24;tooltipEnabled:false;enabled:!!music.player&&music.player.canGoPrevious;Accessible.name:"Previous track";onClicked:music.player.previous()}
            NotchMediaButton {objectName:"notchMusicCompactToggle";host:music.host;symbol:music.player&&music.player.isPlaying?"pause":"play";iconSize:18;implicitWidth:26;implicitHeight:24;tooltipEnabled:false;enabled:!!music.player&&music.player.canTogglePlaying;Accessible.name:music.player&&music.player.isPlaying?"Pause":"Play";onClicked:{music.keepCompact=true;music.player.togglePlaying();}}
            NotchMediaButton {objectName:"notchMusicCompactNext";host:music.host;symbol:"next";iconSize:19;implicitWidth:26;implicitHeight:24;tooltipEnabled:false;enabled:!!music.player&&music.player.canGoNext;Accessible.name:"Next track";onClicked:music.player.next()}
        }
    }
    Item {
        id:expanded
        x:(music.width-music.fullWidth)/2+music.contentInset*music.layoutScale
        y:(Geometry.header-6*(1-music.host.revealProgress))*music.layoutScale
        width:music.layoutWidth-2*music.contentInset;height:129+(music.lyricsOpen?music.lyricsExtraHeight:0)
        scale:music.layoutScale;transformOrigin:Item.TopLeft
        opacity:music.host.revealProgress;visible:opacity>0.01;enabled:music.host.expanded
        // Keep a separate gutter for the right-hand navigation rail.
        readonly property real playerWidth:music.sideOpen&&!music.narrow?330:width-66
        readonly property real baseBodyTop:8
        readonly property real bodyTop:baseBodyTop
        readonly property bool wideLyrics:music.lyricsOpen&&!music.narrow
        readonly property real coverSize:wideLyrics?96:80



        // Real FFT bands from the output monitor; no random activity is invented.
        Item {
            objectName:"notchMusicSpectrum";x:0;y:expanded.bodyTop+50;width:expanded.playerWidth;height:76
            visible:music.visualizer && !music.sideOpen
            Row {
                anchors.bottom:parent.bottom;spacing:4
                Repeater {
                    model:24
                    Rectangle {
                        required property int index
                        readonly property real level:music.service?Number(music.service.bands[index]||0):0
                        width:(expanded.playerWidth-23*4)/24;height:4+level*64;radius:width/2;anchors.bottom:parent.bottom
                        gradient:Gradient {GradientStop{position:0;color:"#25434D"}GradientStop{position:1;color:"#495055"}}
                        opacity:0.46
                        Behavior on height {NumberAnimation{duration:music.host.reducedMotion?0:70;easing.type:Easing.OutCubic}}
                    }
                }
            }
        }
        NotchMediaArt {objectName:"notchMusicCover";visible:!music.narrow||!music.sideOpen;x:0;y:expanded.bodyTop;width:expanded.coverSize;height:width;source:music.player?music.player.trackArtUrl:""}
        Column {
            visible:!music.narrow||!music.sideOpen
            x:expanded.coverSize+14;y:expanded.bodyTop;width:expanded.playerWidth-x;spacing:expanded.wideLyrics?6:4
            Text {objectName:"notchMusicTitle";width:parent.width;text:music.player?music.player.trackTitle||"Now Playing":"Nothing playing";color:"white";font.family:music.host.family;font.pixelSize:expanded.wideLyrics?22:20;font.weight:Font.Bold;elide:Text.ElideRight}
            Text {objectName:"notchMusicArtist";width:parent.width;text:music.artistAlbum;color:"#D0D0D5";font.family:music.host.family;font.pixelSize:expanded.wideLyrics?15:14;elide:Text.ElideRight}
        }
        Item {
            id:timeline;objectName:"notchMusicTimeline";visible:!music.narrow||!music.sideOpen;x:expanded.coverSize+14;y:expanded.bodyTop+(expanded.wideLyrics?64:50);width:expanded.playerWidth-x;height:36
            Slider {
                id:seek;objectName:"notchMusicSeek";width:parent.width;height:14;padding:0;from:0;to:1;value:music.progress
                enabled:!!music.player&&music.player.canSeek&&music.player.positionSupported&&music.player.length>0
                Accessible.name:"Playback position"
                function commit(){if(enabled&&music.player)music.player.position=value*music.player.length;}
                onMoved:if(!pressed)commit()
                onPressedChanged:if(!pressed)commit()
                background:Rectangle {y:(seek.height-height)/2;width:seek.width;height:4;radius:2;color:"#4F5053";Rectangle{width:seek.visualPosition*parent.width;height:parent.height;radius:2;color:"#E8E8EA"}}
                handle:Rectangle{x:seek.visualPosition*(seek.width-width);y:(seek.height-height)/2;width:8;height:8;radius:4;color:"white";opacity:seek.hovered||seek.pressed?1:0}
            }
            Text {x:0;y:16;text:music.formatTime(music.player?music.player.position:0);color:"#CDCDD2";font.family:music.host.family;font.pixelSize:expanded.wideLyrics?13:12;font.features:({"tnum":1})}
            Text {anchors.right:parent.right;y:16;text:music.player&&music.player.length>0?music.formatTime(music.player.length):"—";color:"#CDCDD2";font.family:music.host.family;font.pixelSize:expanded.wideLyrics?13:12;font.features:({"tnum":1})}
        }
        Row {
            id:transport;objectName:"notchMusicTransport"
            x:!music.sideOpen?(expanded.width-width)/2:expanded.playerWidth-width
            y:music.host.fullMetrics.height/music.layoutScale-Geometry.header-Geometry.padding-height;height:36;spacing:6
            NotchMediaButton {objectName:"notchMusicShuffle";host:music.host;symbol:"shuffle";iconSize:20;implicitWidth:32;implicitHeight:parent.height;active:!!music.player&&music.player.shuffle===true;enabled:!!music.player&&music.player.shuffleSupported===true;Accessible.name:active?"Turn shuffle off":"Turn shuffle on";onClicked:music.player.shuffle=!music.player.shuffle}
            NotchMediaButton {objectName:"notchMusicPrevious";host:music.host;symbol:"previous";iconSize:26;implicitWidth:36;implicitHeight:parent.height;enabled:!!music.player&&music.player.canGoPrevious;Accessible.name:"Previous track";onClicked:music.player.previous()}
            NotchMediaButton {objectName:"notchMusicPlayPause";host:music.host;symbol:music.player&&music.player.isPlaying?"pause":"play";iconSize:28;implicitWidth:40;implicitHeight:parent.height;round:true;enabled:!!music.player&&music.player.canTogglePlaying;Accessible.name:music.player&&music.player.isPlaying?"Pause":"Play";onClicked:music.player.togglePlaying()}
            NotchMediaButton {objectName:"notchMusicNext";host:music.host;symbol:"next";iconSize:26;implicitWidth:36;implicitHeight:parent.height;enabled:!!music.player&&music.player.canGoNext;Accessible.name:"Next track";onClicked:music.player.next()}
            NotchMediaButton {objectName:"notchMusicRepeat";host:music.host;symbol:music.player&&music.player.loopState===MprisLoopState.Track?"repeatOne":"repeat";iconSize:20;implicitWidth:32;implicitHeight:parent.height;active:!!music.player&&music.player.loopSupported===true&&music.player.loopState!==MprisLoopState.None;enabled:!!music.player&&music.player.loopSupported===true;Accessible.name:music.player&&music.player.loopState===MprisLoopState.Track?"Repeat one track":active?"Repeat playlist":"Repeat off";onClicked:music.cycleRepeat()}
            NotchMediaButton {id:outputButton;objectName:"notchMusicOutput";host:music.host;symbol:"output";iconSize:20;implicitWidth:32;implicitHeight:parent.height;Accessible.name:"Audio output and volume";onClicked:outputMenu.open()}
        }
        NotchMediaButton {
            objectName:"notchMusicLyrics";host:music.host
            x:(expanded.coverSize-width)/2
            y:transport.y+(transport.height-height)/2
            symbol:"lyrics";implicitWidth:26;implicitHeight:26;iconSize:17
            background:null
            filledIcon:music.lyricsOpen;active:music.lyricsOpen;enabled:music.canLyrics
            Accessible.name:music.lyricsOpen?"Hide lyrics":"Show lyrics"
            onClicked:music.toggleLyrics()
        }
        Item {
            id:lyricPane;objectName:"notchLyricsPane"
            opacity:music.lyricsOpen?1:0;visible:opacity>0.001
            scale:music.lyricsOpen?1:0.94;transformOrigin:Item.Left
            Behavior on opacity {NumberAnimation {duration:music.host.reducedMotion?0:420;easing.type:Easing.OutCubic}}
            Behavior on scale {NumberAnimation {duration:music.host.reducedMotion?0:480;easing.type:Easing.OutCubic}}
            x:music.narrow?0:expanded.playerWidth+20;y:expanded.baseBodyTop;width:expanded.width-x-58;height:music.narrow?140:160;clip:true
            // The same lyric typography and focus treatment as PlayerWidget,
            // scaled to the notch's existing text size and available space.
            readonly property real typographyScale:(music.narrow?18:20)/25
            readonly property bool effectsAvailable:GraphicsInfo.api!==GraphicsInfo.Software
            layer.enabled:effectsAvailable && opacity>0 && opacity<0.999
            layer.sourceRect:Qt.rect(-16,-16,width+32,height+32)
            layer.effect:MultiEffect {blurEnabled:true;blurMax:32;blur:Math.min(1,(1-lyricPane.opacity)*0.9)}
            Rectangle {
                id:lyricMask
                anchors.fill:lyricList
                visible:false;layer.enabled:lyricPane.effectsAvailable
                readonly property real feather:Math.min(0.20,16/Math.max(1,height))
                gradient:Gradient {
                    GradientStop {position:0;color:Qt.rgba(0,0,0,0)}
                    GradientStop {position:lyricMask.feather*0.25;color:Qt.rgba(0,0,0,0.04)}
                    GradientStop {position:lyricMask.feather*0.5;color:Qt.rgba(0,0,0,0.30)}
                    GradientStop {position:lyricMask.feather*0.75;color:Qt.rgba(0,0,0,0.72)}
                    GradientStop {position:lyricMask.feather;color:Qt.rgba(0,0,0,1)}
                    GradientStop {position:1-lyricMask.feather;color:Qt.rgba(0,0,0,1)}
                    GradientStop {position:1-lyricMask.feather*0.75;color:Qt.rgba(0,0,0,0.72)}
                    GradientStop {position:1-lyricMask.feather*0.5;color:Qt.rgba(0,0,0,0.30)}
                    GradientStop {position:1-lyricMask.feather*0.25;color:Qt.rgba(0,0,0,0.04)}
                    GradientStop {position:1;color:Qt.rgba(0,0,0,0)}
                }
            }
            ListView {
                id: lyricList
                objectName: "notchLyricsList"
                anchors.fill: parent
                model: music.lyricLines
                function followPlayback(align) {
                    if(!music.lyricsSynced)return;
                    const previousY=contentY;
                    scrollMotion.stop();
                    currentIndex=Math.max(0,music.lyricIndex);
                    forceLayout();
                    if(!currentItem)return;
                    const targetY=currentItem.y-preferredHighlightBegin;
                    // Animate the viewport explicitly. ApplyRange can leave it
                    // stationary until a lyric crosses the range boundary.
                    if(align || music.host.reducedMotion || !visible)contentY=targetY;
                    else {
                        contentY=previousY;
                        scrollMotion.from=previousY;scrollMotion.to=targetY;scrollMotion.restart();
                    }
                }
                NumberAnimation {
                    id:scrollMotion;objectName:"notchLyricsScrollMotion"
                    target:lyricList;property:"contentY";duration:650;easing.type:Easing.OutCubic
                }
                function alignPlayback(){forceLayout();followPlayback(true);}
                // A model reset may change currentIndex even when the new
                // playback index has the same value as the previous model.
                onModelChanged:Qt.callLater(alignPlayback)
                onHeightChanged:Qt.callLater(alignPlayback)
                onWidthChanged:Qt.callLater(alignPlayback)
                onVisibleChanged:if(visible)Qt.callLater(alignPlayback)
                onContentYChanged: {
                    if(!music.lyricsSynced)currentIndex=LyricFocus.indexAtFocus(lyricList);
                }
                Connections {
                    target:music
                    function onLyricIndexChanged(){lyricList.followPlayback(false);}
                    function onLyricsSyncedChanged(){Qt.callLater(lyricList.alignPlayback);}
                }
                Connections {
                    target:music.host
                    function onReducedMotionChanged(){if(music.host.reducedMotion)lyricList.followPlayback(true);}
                }
                clip: true
                interactive: !music.lyricsSynced
                boundsBehavior: Flickable.StopAtBounds
                // Playback owns the index; scrolling must never select a lyric.
                highlightRangeMode: ListView.NoHighlightRange
                highlightFollowsCurrentItem:false
                preferredHighlightBegin: Math.round(height*0.24)
                preferredHighlightEnd: preferredHighlightBegin
                cacheBuffer: 180
                header: Item { height: music.lyricsSynced ? lyricList.preferredHighlightBegin : 8 }
                footer: Item { height: music.lyricsSynced ? lyricList.height-lyricList.preferredHighlightBegin : 8 }
                layer.enabled:lyricPane.effectsAvailable && lyricPane.visible
                layer.effect:MultiEffect {maskEnabled:true;maskSource:lyricMask}
                delegate: Item {
                    id: lyricLine
                    required property var modelData
                    required property int index
                    objectName: "notchLyricLine" + index
                    readonly property int focusIndex: music.lyricsSynced ? Math.max(0,music.lyricIndex) : lyricList.currentIndex
                    readonly property int relative: index-focusIndex
                    readonly property bool active: relative===0
                    readonly property real distance: Math.abs(relative)
                    // Keep the full model for smooth timed scrolling, but draw
                    // only previous/current/next lyrics. Untimed lyrics scroll
                    // through consecutive groups of three without fake timing.
                    readonly property bool inWindow:music.lyricsSynced?distance<=1:index>=Math.max(0,lyricList.currentIndex)&&index<Math.max(0,lyricList.currentIndex)+3
                    property real blurAmount: LyricFocus.blur(relative)
                    Behavior on blurAmount {NumberAnimation {duration:music.host.reducedMotion?0:380;easing.type:Easing.OutQuint}}
                    readonly property real centerY: y - lyricList.contentY + height / 2
                    readonly property real edgeOpacity: Math.max(0, Math.min(1, centerY / 12, (lyricList.height - centerY) / 12))
                    width: ListView.view ? ListView.view.width : lyricPane.width
                    height: words.implicitHeight + 6
                    property real windowOpacity:inWindow?1:0
                    Behavior on windowOpacity {NumberAnimation {duration:music.host.reducedMotion?0:480;easing.type:Easing.OutCubic}}
                    opacity:windowOpacity*(lyricPane.effectsAvailable?1:edgeOpacity)
                    Text {
                        id: words
                        objectName:"notchLyricWords"+lyricLine.index
                        width: parent.width; anchors.verticalCenter: parent.verticalCenter
                        text: lyricLine.modelData.text || "♪"
                        textFormat:Text.PlainText
                        wrapMode: Text.Wrap
                        color: "#FAFAFC"; font.family: music.host.family
                        font.pixelSize: 25*lyricPane.typographyScale; font.weight: Font.Bold
                        opacity: LyricFocus.opacity(lyricLine.relative)
                        scale:LyricFocus.scale(lyricLine.relative)
                        transformOrigin:Item.Left
                        Behavior on opacity {NumberAnimation {duration:music.host.reducedMotion?0:480;easing.type:Easing.OutCubic}}
                        Behavior on scale {NumberAnimation {duration:music.host.reducedMotion?0:480;easing.type:Easing.OutCubic}}
                        layer.enabled:lyricPane.effectsAvailable && lyricLine.blurAmount>0.01
                        layer.sourceRect:Qt.rect(-12,-8,width+24,height+16)
                        layer.effect:MultiEffect {blurEnabled:true;blurMax:16;blur:lyricLine.blurAmount}
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: lyricLine.inWindow && music.lyricsSynced && !!music.player && music.player.canSeek && music.player.positionSupported && lyricLine.modelData.t >= 0
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        Accessible.role: Accessible.Button
                        Accessible.name: "Jump to lyric: " + (lyricLine.modelData.text || "instrumental")
                        onClicked: music.player.position = lyricLine.modelData.t
                    }
                }
            }
            Text {
                objectName: "notchLyricsEmpty"
                anchors.centerIn: parent; width: parent.width - 12
                visible: music.lyricLines.length === 0
                text: music.widgets && (music.widgets.lyricsState === "loading" || music.widgets.lyricsState === "idle") ? "Finding lyrics…" : music.widgets && music.widgets.lyricsState === "error" ? "Couldn’t load lyrics. Reopen to retry." : "No lyrics available for this track"
                color: "#C5CDDD"; font.family: music.host.family; font.pixelSize: 14; font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }

        }
    }

    NotchSettingsPopup {
        id:outputMenu;objectName:"notchMediaOutput";host:music.host;control:outputButton;title:"Audio output";subtitle:"System volume and playback device";acceptText:"Done";showCancel:false;onSaveRequested:close()
        Column {width:parent.width;spacing:8
            GlassCommon.GlassSlider {
                objectName:"notchMediaVolume";width:parent.width;from:0;to:1;stepSize:0.01
                dark:outputMenu.dark
                accentColor:music.host.bar && music.host.bar.accent?music.host.bar.accent:"#0A84FF"
                value:music.host.bar?music.host.bar.volume:0
                Accessible.name:"System volume"
                onMoved:if(music.host.bar)music.host.bar.setVolume(value)
            }
            Repeater {model:music.outputs
                NotchMediaMenuItem {menu:outputMenu;required property var modelData;objectName:"notchMediaOutput"+modelData.id;width:parent.width;text:(music.host.bar.sink&&music.host.bar.sink.id===modelData.id?"✓  ":"")+(modelData.description||modelData.name);onClicked:music.host.bar.chooseAudio(modelData)}
            }
            Text {width:parent.width;visible:music.outputs.length===0;text:"No output devices available";color:outputMenu.secondary}
        }
    }
}
