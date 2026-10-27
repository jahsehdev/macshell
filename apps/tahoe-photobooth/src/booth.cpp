#include "booth.h"
#include "nautilussavedialog.h"
#include "cameradiscovery.h"
#include "effects.h"
#include <QAudioDevice>
#include <QAudioBuffer>
#include <QMediaFormat>
#include <QDateTime>
#include <QClipboard>
#include <QGuiApplication>
#include <QMimeData>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QSaveFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDesktopServices>
#include <QPainter>
#include <QProcess>
#include <QUuid>
#include <cmath>

static QString configHome() {
    return qEnvironmentVariable("XDG_CONFIG_HOME", QDir::homePath()+"/.config");
}

Booth::Booth(QString library, bool demo, bool useCamera, QObject *parent)
    : QObject(parent), m_library(library.isEmpty() ? QStandardPaths::writableLocation(QStandardPaths::PicturesLocation)+"/Photo Booth" : library),
      m_demo(demo), m_useCamera(useCamera), m_preferences("MacShell", "PhotoBooth") {
    m_exportDialog=new NautilusSaveDialog(this);
    connect(m_exportDialog,&NautilusSaveDialog::failed,this,&Booth::exportFailed);
    connect(m_exportDialog,&NautilusSaveDialog::fileSelected,this,[this](const QUrl &source,const QUrl &destination) {
        if(!exportMedia(source,destination)) emit exportFailed(m_status);
    });
    m_flash=m_preferences.value("flash",true).toBool();
    m_mirrored=m_preferences.value("mirrored",true).toBool();
    m_microphone=m_preferences.value("microphone",true).toBool();
    m_effect=std::clamp(m_preferences.value("effect",4).toInt(),0,8);
    m_strength=std::clamp(m_preferences.value("strength",0.5).toDouble(),0.0,1.0);
    QDir().mkpath(m_library+"/.thumbnails");
    m_themeDebounce.setSingleShot(true); m_themeDebounce.setInterval(80);
    connect(&m_themeDebounce,&QTimer::timeout,this,&Booth::readTheme);
    m_galleryDebounce.setSingleShot(true); m_galleryDebounce.setInterval(150);
    connect(&m_galleryDebounce,&QTimer::timeout,this,&Booth::refreshGallery);
    connect(&m_watcher,&QFileSystemWatcher::directoryChanged,this,[this](const QString &path) {
        if(path==m_library) m_galleryDebounce.start(); else m_themeDebounce.start();
    });
    connect(&m_watcher,&QFileSystemWatcher::fileChanged,this,[this] { m_themeDebounce.start(); });
    for(const QString &dir : {configHome()+"/macbar",configHome()+"/macdock",m_library}) if(QDir(dir).exists()) m_watcher.addPath(dir);
    readTheme(); refreshGallery();
    if(useCamera && !demo) {
        connect(&m_devices,&QMediaDevices::videoInputsChanged,this,&Booth::scanDevices);
        connect(&m_devices,&QMediaDevices::audioInputsChanged,this,&Booth::scanDevices);
        m_cameraPoll.setInterval(1000);
        connect(&m_cameraPoll,&QTimer::timeout,this,[this] {
            if(!busy() && !hasFrame() && !QDir("/sys/devices/virtual/video4linux").entryList(QDir::Dirs|QDir::NoDotAndDotDot).isEmpty())
                CameraDiscovery::refreshVideoInputs();
        });
        m_cameraPoll.start();
    }
    connect(&m_sink,&QVideoSink::videoFrameChanged,this,[this](const QVideoFrame &frame) {
        if(m_previewClock.isValid() && m_previewClock.elapsed()<32) return;
        if(frame.isValid()) { feedImage(frame.toImage()); m_previewClock.restart(); }
    });
    connect(&m_camera,&QCamera::errorOccurred,this,[this](QCamera::Error,const QString &error) {
        m_frame={}; m_processed={}; cancel();
        if(m_recording) stopRecording();
        setStatus("Camera unavailable: "+error); emit frameChanged();
    });
    m_cameraSession.setCamera(&m_camera); m_cameraSession.setVideoSink(&m_sink);
    m_recordSession.setVideoFrameInput(&m_videoInput); m_recordSession.setRecorder(&m_recorder);
    m_recorder.setQuality(QMediaRecorder::HighQuality);
    m_recorder.setVideoFrameRate(30);
    connect(&m_videoInput,&QVideoFrameInput::readyToSendVideoFrame,this,[this] { m_ready=true; });
    connect(&m_recorder,&QMediaRecorder::durationChanged,this,[this] { emit stateChanged(); });
    connect(&m_recorder,&QMediaRecorder::errorOccurred,this,[this](QMediaRecorder::Error,const QString &message) {
        m_recordFailed=true; m_frameTimer.stop(); m_demoAudioTimer.stop(); m_recording=false; m_finalizing=false; m_ready=false;
        setStatus("Recording failed: "+message);
        if(m_recorder.recorderState()!=QMediaRecorder::StoppedState) m_recorder.stop();
        if(m_closePending) emit closeReady();
    });
    connect(&m_recorder,&QMediaRecorder::recorderStateChanged,this,[this](QMediaRecorder::RecorderState state) {
        if(state!=QMediaRecorder::StoppedState) return;
        m_frameTimer.stop(); m_demoAudioTimer.stop(); m_ready=false;
        bool wasRecording=m_recording || m_finalizing;
        m_recording=false; m_finalizing=false;
        m_recordSession.setAudioInput(nullptr); m_recordSession.setAudioBufferInput(nullptr);
        if(wasRecording && !m_recordFailed && QFileInfo(m_videoPath).size()>0) {
            refreshGallery(); setStatus("Video saved"); emit saved(QUrl::fromLocalFile(m_videoPath));
        } else emit stateChanged();
        if(m_closePending) emit closeReady();
    });
    m_frameTimer.setInterval(33);
    connect(&m_frameTimer,&QTimer::timeout,this,&Booth::sendRecordingFrame);
    m_countTimer.setInterval(1000);
    connect(&m_countTimer,&QTimer::timeout,this,[this] {
        if(--m_countdown<=0) {
            m_countTimer.stop();
            if(m_mode==2) startRecording(); else takeShot();
        }
        emit stateChanged();
    });
    if(demo) {
        m_demoAudioFormat.setSampleRate(48000); m_demoAudioFormat.setChannelCount(1); m_demoAudioFormat.setSampleFormat(QAudioFormat::Int16);
        connect(&m_demoAudio,&QAudioBufferInput::readyToSendAudioBuffer,this,[this] { m_demoAudioReady=true; });
        m_demoAudioTimer.setInterval(20);
        connect(&m_demoAudioTimer,&QTimer::timeout,this,[this] {
            if(!m_recording || !m_demoAudioReady) return;
            QByteArray bytes(960*int(sizeof(qint16)),Qt::Uninitialized);
            auto *samples=reinterpret_cast<qint16 *>(bytes.data());
            for(int i=0;i<960;++i) samples[i]=qint16(700*std::sin(2*3.141592653589793*220*(m_demoSamples+i)/48000.0));
            QAudioBuffer buffer(bytes,m_demoAudioFormat,m_demoSamples*1000000/48000);
            m_demoSamples+=960; m_demoAudioReady=false;
            if(!m_demoAudio.sendAudioBuffer(buffer)) { m_demoSamples-=960; m_demoAudioReady=true; }
        });
        m_demoTimer.setInterval(33);
        connect(&m_demoTimer,&QTimer::timeout,this,[this] {
            QImage image(960,640,QImage::Format_RGB32);
            QPainter p(&image); QLinearGradient gradient(0,0,960,640);
            gradient.setColorAt(0,QColor("#4d708d")); gradient.setColorAt(0.5,QColor("#d9b9a6")); gradient.setColorAt(1,QColor("#547d69"));
            p.fillRect(image.rect(),gradient);
            p.setPen(Qt::NoPen); p.setBrush(QColor("#e7ccc0")); p.drawEllipse(QPointF(480+std::sin(QDateTime::currentMSecsSinceEpoch()/800.0)*80,300),125,160);
            p.setPen(Qt::white); p.setFont(QFont("sans-serif",22)); p.drawText(image.rect().adjusted(20,20,-20,-20),Qt::AlignBottom|Qt::AlignHCenter,"DEMO CAMERA · SYNTHETIC IMAGE");
            p.end(); feedImage(image);
        });
        m_demoTimer.start(); setStatus("Demo camera · synthetic image and test tone");
    } else if(useCamera) scanDevices();
}

Booth::~Booth() { m_camera.stop(); m_recorder.stop(); }
QObject *Booth::exportDialog() const { return m_exportDialog; }
QString Booth::controlsPath() const {
    const QString path=configHome()+"/macshell/window-controls/";
    if(QFileInfo::exists(path+"light/titlebutton-close@2.png"))
        return QUrl::fromLocalFile(path).toString();
    return QStringLiteral("qrc:/assets/window-controls/");
}
QStringList Booth::effectNames() const { return Effects::names(); }
void Booth::setStatus(const QString &value) { m_status=value; emit stateChanged(); }

void Booth::readTheme() {
    for(const QString &name : {QString("macbar"),QString("macdock")}) {
        const QString path=configHome()+"/"+name+"/settings.json";
        QFile file(path); if(!file.open(QIODevice::ReadOnly)) continue;
        QJsonParseError error; auto document=QJsonDocument::fromJson(file.readAll(),&error);
        if(error.error!=QJsonParseError::NoError || !document.isObject()) continue;
        auto object=document.object(); QString mode=object["appearanceMode"].toString();
        if(mode=="light" || mode=="dark") m_dark=mode=="dark";
        else if(object["darkMode"].isBool()) m_dark=object["darkMode"].toBool();
        if(object["fontFamily"].isString()) m_font=object["fontFamily"].toString();
        if(!m_watcher.files().contains(path)) m_watcher.addPath(path);
        emit themeChanged(); return;
    }
}
bool Booth::droidcamInstalled() const { return !QStandardPaths::findExecutable("droidcam").isEmpty(); }
QVariantList Booth::cameras() const {
    QVariantList result;
    if(m_demo || !m_useCamera) return result;
    for(const auto &device:QMediaDevices::videoInputs()) result.append(QVariantMap{{"name",device.description()},{"id",device.id()}});
    return result;
}
QVariantList Booth::microphones() const {
    QVariantList result;
    if(m_demo || !m_useCamera) return result;
    for(const auto &device:QMediaDevices::audioInputs()) result.append(QVariantMap{{"name",device.description()},{"id",device.id()}});
    return result;
}
void Booth::scanDevices() {
    if(m_demo || !m_useCamera) return;
    const auto video=QMediaDevices::videoInputs();
    if(!video.isEmpty()) {
        int chosen=0;
        auto preferred=m_preferences.value("cameraId").toByteArray();
        for(int i=0;i<video.size();++i) if(video[i].id()==preferred) chosen=i;
        if(m_camera.cameraDevice()!=video[chosen] || !m_camera.isActive()) { m_cameraIndex=-1; setCameraIndex(chosen); }
    } else {
        m_camera.stop(); m_cameraIndex=-1; m_frame={}; m_processed={};
        cancel(); if(m_recording) stopRecording(); setStatus("No camera connected. Connect a webcam, then choose Retry."); emit frameChanged();
    }
    const auto audio=QMediaDevices::audioInputs();
    m_microphoneIndex=audio.isEmpty()?-1:0;
    for(int i=0;i<audio.size();++i) if(audio[i].id()==m_preferences.value("microphoneId").toByteArray()) m_microphoneIndex=i;
    emit devicesChanged();
}
void Booth::setCameraIndex(int index) {
    const auto inputs=QMediaDevices::videoInputs();
    if(busy() || index<0 || index>=inputs.size()) return;
    m_camera.stop(); m_frame={}; m_processed={}; m_cameraIndex=index;
    m_camera.setCameraDevice(inputs[index]);
    QCameraFormat best; double bestScore=-1e10;
    for(const auto &format:inputs[index].videoFormats()) {
        QSize size=format.resolution();
        if(size.width()>1920 || size.height()>1080) continue;
        double score=-std::abs(size.width()-1280)-std::abs(size.height()-720)+std::min(30.0f,format.maxFrameRate())*10;
        if(score>bestScore) { best=format; bestScore=score; }
    }
    if(!best.isNull()) m_camera.setCameraFormat(best);
    m_preferences.setValue("cameraId",inputs[index].id());
    m_camera.start(); setStatus("Starting camera…"); emit devicesChanged(); emit frameChanged();
}
void Booth::setMicrophoneIndex(int index) {
    const auto inputs=QMediaDevices::audioInputs();
    if(busy() || index<0 || index>=inputs.size()) return;
    m_microphoneIndex=index; m_preferences.setValue("microphoneId",inputs[index].id()); emit devicesChanged();
}
void Booth::retryCamera() {
    if(busy() || !m_useCamera || m_demo) return;
    const auto before=QMediaDevices::videoInputs();
    CameraDiscovery::refreshVideoInputs();
    // A changed list emits videoInputsChanged and scans once through that signal.
    if(before==QMediaDevices::videoInputs()) scanDevices();
}
void Booth::openDroidcam() {
    const QString executable=QStandardPaths::findExecutable("droidcam");
    if(executable.isEmpty() || !QProcess::startDetached(executable,{}))
        setStatus("Could not open DroidCam. Check that the Linux client is installed.");
}
void Booth::feedImage(const QImage &source) {
    if(source.isNull()) return;
    m_frame=source.width()>1280 || source.height()>960 ? source.scaled(1280,960,Qt::KeepAspectRatio,Qt::SmoothTransformation) : source;
    if(m_status=="Starting camera…") setStatus({});
    processFrame();
}
void Booth::processFrame() {
    QImage image=m_mirrored?m_frame.flipped(Qt::Horizontal):m_frame;
    m_processed=Effects::apply(image,m_effect,m_strength);
    emit frameChanged();
}
void Booth::savePreferences() {
    m_preferences.setValue("flash",m_flash); m_preferences.setValue("mirrored",m_mirrored);
    m_preferences.setValue("microphone",m_microphone); m_preferences.setValue("effect",m_effect); m_preferences.setValue("strength",m_strength);
}
void Booth::setMode(int value) { if(!busy() && value>=0 && value<=2) { m_mode=value; emit stateChanged(); } }
void Booth::setEffect(int value) { if(!busy() && value>=0 && value<effectNames().size()) { m_effect=value; savePreferences(); processFrame(); emit effectChanged(); } }
void Booth::setStrength(double value) { if(!busy()) { m_strength=std::clamp(value,0.0,1.0); savePreferences(); processFrame(); emit effectChanged(); } }
void Booth::setFlashEnabled(bool value) { m_flash=value; savePreferences(); emit preferencesChanged(); }
void Booth::setMicrophone(bool value) { if(!busy()) { m_microphone=value; savePreferences(); emit preferencesChanged(); } }
void Booth::setMirrored(bool value) { if(!busy()) { m_mirrored=value; savePreferences(); processFrame(); emit preferencesChanged(); } }
QString Booth::makePath(const QString &suffix) const {
    return m_library+"/Photo Booth "+QDateTime::currentDateTime().toString("yyyy-MM-dd 'at' HH.mm.ss.zzz")+"-"+QUuid::createUuid().toString(QUuid::Id128).left(6)+suffix;
}
bool Booth::saveImage(const QImage &image,const QString &path) {
    QSaveFile file(path);
    if(image.isNull() || !file.open(QIODevice::WriteOnly) || !image.save(&file,"JPEG",95) || !file.commit()) { setStatus("Could not save photo. Check available disk space and folder permissions."); return false; }
    return true;
}
void Booth::capture(bool skipCountdown,bool suppressFlash) {
    if(m_recording) { stopRecording(); return; }
    if(busy()) return;
    if(!hasFrame()) { setStatus("The camera is not ready yet."); return; }
    if(!QDir().mkpath(m_library)) { setStatus("The Photo Booth folder is not writable."); return; }
    ++m_captureGeneration;
    m_capturing=true; m_shots.clear(); m_suppressFlash=suppressFlash; m_countdown=skipCountdown?0:3;
    if(m_countdown) m_countTimer.start();
    else if(m_mode==2) startRecording(); else takeShot();
    emit stateChanged();
}
void Booth::cancel() {
    if(m_recording || m_finalizing) return;
    ++m_captureGeneration;
    m_countTimer.stop(); m_countdown=0; m_capturing=false; m_shots.clear(); emit stateChanged();
}
void Booth::takeShot() {
    if(!m_capturing) return;
    if(!hasFrame()) { cancel(); setStatus("Camera disconnected before capture."); return; }
    if(m_flash && !m_suppressFlash) emit flashRequested();
    const auto generation=m_captureGeneration;
    QTimer::singleShot(m_flash && !m_suppressFlash?100:0,this,[this,generation] {
        if(!m_capturing || generation!=m_captureGeneration) return;
        if(!hasFrame()) { cancel(); setStatus("Camera disconnected before capture."); return; }
        m_shots.append(m_processed.copy()); emit stateChanged();
        if(m_mode==0 && m_shots.size()<4) { QTimer::singleShot(1000,this,[this,generation] { if(generation==m_captureGeneration) takeShot(); }); return; }
        const auto image=m_mode==0?Effects::fourUp(m_shots):m_shots.first();
        const QString path=makePath(m_mode==0?" 4-up.jpg":".jpg");
        bool success=saveImage(image,path); m_capturing=false; m_shots.clear();
        if(success) { setStatus("Photo saved"); refreshGallery(); emit saved(QUrl::fromLocalFile(path)); }
        else emit stateChanged();
    });
}
void Booth::startRecording() {
    m_capturing=false; m_countdown=0;
    if(!hasFrame()) { setStatus("Camera disconnected before recording."); return; }
    m_recordSize=QSize(m_processed.width()/2*2,m_processed.height()/2*2);
    m_recorder.setVideoResolution(m_recordSize);
    QMediaFormat format(QMediaFormat::MPEG4); format.setVideoCodec(QMediaFormat::VideoCodec::H264);
    format.setAudioCodec(QMediaFormat::AudioCodec::AAC);
    m_recorder.setMediaFormat(format);
    bool audio=m_microphone && (m_demo || m_microphoneIndex>=0);
    if(audio && m_demo) { m_demoSamples=0; m_demoAudioReady=false; m_recordSession.setAudioBufferInput(&m_demoAudio); }
    else if(audio) {
        if(!m_audioInput) m_audioInput=new QAudioInput(this);
        m_audioInput->setDevice(QMediaDevices::audioInputs().value(m_microphoneIndex));
        m_recordSession.setAudioInput(m_audioInput);
    }
    m_videoPath=makePath(".mp4"); m_recorder.setOutputLocation(QUrl::fromLocalFile(m_videoPath));
    m_recordFailed=false; m_recording=true; m_ready=false; m_recordClock.start();
    m_recorder.record();
    if(m_recordFailed) return;
    saveImage(m_processed.scaled(240,160,Qt::KeepAspectRatio,Qt::SmoothTransformation),m_library+"/.thumbnails/"+QFileInfo(m_videoPath).completeBaseName()+".jpg");
    m_frameTimer.start();
    if(audio && m_demo) m_demoAudioTimer.start();
    setStatus(audio?"Recording with audio":"Recording without audio");
}
void Booth::sendRecordingFrame() {
    if(!m_recording || !m_ready || m_processed.isNull()) return;
    QVideoFrame frame(m_processed.scaled(m_recordSize,Qt::IgnoreAspectRatio,Qt::FastTransformation));
    frame.setStartTime(m_recordClock.nsecsElapsed()/1000); frame.setEndTime(frame.startTime()+33333);
    m_ready=false;
    if(!m_videoInput.sendVideoFrame(frame)) m_ready=true;
}
void Booth::stopRecording() {
    if(!m_recording) return;
    m_frameTimer.stop(); m_demoAudioTimer.stop(); m_recording=false; m_finalizing=true; setStatus("Saving video…"); m_recorder.stop();
}
void Booth::refreshGallery() {
    QVariantList list;
    const QDir dir(m_library);
    for(const auto &info:dir.entryInfoList({"*.jpg","*.jpeg","*.png","*.mp4","*.webm","*.mov"},QDir::Files,QDir::Time)) {
        if((m_recording || m_finalizing || m_recordFailed) && info.absoluteFilePath()==m_videoPath) continue;
        bool video=QStringList{"mp4","webm","mov"}.contains(info.suffix().toLower());
        QString thumb=video?m_library+"/.thumbnails/"+info.completeBaseName()+".jpg":info.absoluteFilePath();
        list.append(QVariantMap{{"url",QUrl::fromLocalFile(info.absoluteFilePath())},{"thumbnail",QUrl::fromLocalFile(thumb)},{"name",info.fileName()},{"video",video},{"date",info.lastModified().toString("dd MMM yyyy, HH:mm")}});
    }
    m_gallery=list; emit galleryChanged();
}
bool Booth::owns(const QUrl &url) const {
    if(!url.isLocalFile()) return false;
    QFileInfo info(url.toLocalFile());
    return info.isFile() && !info.isSymLink() && info.canonicalPath()==QFileInfo(m_library).canonicalFilePath();
}
bool Booth::exportMedia(const QUrl &source,const QUrl &destination) {
    if(!owns(source) || !destination.isLocalFile()) { setStatus("Choose a local export destination."); return false; }
    if(QFileInfo(source.toLocalFile()).absoluteFilePath()==QFileInfo(destination.toLocalFile()).absoluteFilePath()) return true;
    QFile input(source.toLocalFile()); QSaveFile output(destination.toLocalFile());
    if(!input.open(QIODevice::ReadOnly) || !output.open(QIODevice::WriteOnly)) { setStatus("Could not open export destination."); return false; }
    while(!input.atEnd()) { QByteArray data=input.read(1024*1024); if(data.isEmpty() && input.error()!=QFileDevice::NoError) { setStatus("Could not read the original file."); return false; } if(output.write(data)!=data.size()) { setStatus("Could not export file."); return false; } }
    if(!output.commit()) { setStatus("Could not finish export."); return false; }
    setStatus("Exported to "+destination.toLocalFile()); return true;
}
bool Booth::trashMedia(const QUrl &source) {
    if(!owns(source) || busy()) return false;
    if(!QFile::moveToTrash(source.toLocalFile())) { setStatus("Could not move this item to Trash."); return false; }
    refreshGallery(); setStatus("Moved to Trash"); return true;
}
void Booth::copyMedia(const QUrl &source) {
    if(!owns(source)) return;
    auto *mime=new QMimeData; mime->setUrls({source});
    if(!QStringList{"mp4","mov","webm"}.contains(QFileInfo(source.toLocalFile()).suffix().toLower())) mime->setImageData(QImage(source.toLocalFile()));
    QGuiApplication::clipboard()->setMimeData(mime); setStatus("Copied to clipboard");
}
void Booth::openLibrary() { QDesktopServices::openUrl(QUrl::fromLocalFile(m_library)); }
void Booth::withWindow(const QString &action) {
    auto *process=new QProcess(this);
    connect(process,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this,process,action](int code,QProcess::ExitStatus) {
        if(code==0) for(const auto &entry:QJsonDocument::fromJson(process->readAllStandardOutput()).array()) {
            auto object=entry.toObject();
            if(object["pid"].toInteger()!=QCoreApplication::applicationPid()) continue;
            const QString address=object["address"].toString();
            if(!address.startsWith("0x")) continue;
            if(action=="minimize") QProcess::startDetached("qs",{"-c","MacShell","ipc","call","minimize","addr",address});
            else QProcess::startDetached("hyprctl",{"dispatch","hl.dsp.window.tag({window=\"address:"+address+"\",tag=\"+macshell-native-controls\"})"});
            break;
        }
        process->deleteLater();
    });
    connect(process,&QProcess::errorOccurred,process,&QObject::deleteLater);
    process->start("hyprctl",{"-j","clients"});
}
void Booth::windowReady() { withWindow("ready"); }
void Booth::minimize() { withWindow("minimize"); }
void Booth::requestClose() {
    if(m_recording || m_finalizing) { m_closePending=true; if(m_recording) stopRecording(); }
    else { cancel(); m_camera.stop(); emit closeReady(); }
}
