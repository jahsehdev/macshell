#pragma once
#include <QObject>
#include <QImage>
#include <QVariantList>
#include <QCamera>
#include <QVideoSink>
#include <QMediaCaptureSession>
#include <QVideoFrameInput>
#include <QMediaRecorder>
#include <QAudioInput>
#include <QAudioBufferInput>
#include <QMediaDevices>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QElapsedTimer>
#include <QSettings>
#include <QUrl>

class NautilusSaveDialog;

class Booth : public QObject {
    Q_OBJECT
    Q_PROPERTY(QObject *exportDialog READ exportDialog CONSTANT)
    Q_PROPERTY(bool dark READ dark NOTIFY themeChanged)
    Q_PROPERTY(QString fontFamily READ fontFamily NOTIFY themeChanged)
    Q_PROPERTY(QString controlsPath READ controlsPath CONSTANT)
    Q_PROPERTY(bool demo READ demo CONSTANT)
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY frameChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)
    Q_PROPERTY(int mode READ mode WRITE setMode NOTIFY stateChanged)
    Q_PROPERTY(int effect READ effect WRITE setEffect NOTIFY effectChanged)
    Q_PROPERTY(double strength READ strength WRITE setStrength NOTIFY effectChanged)
    Q_PROPERTY(QStringList effectNames READ effectNames CONSTANT)
    Q_PROPERTY(int countdown READ countdown NOTIFY stateChanged)
    Q_PROPERTY(int burstProgress READ burstProgress NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(bool recording READ recording NOTIFY stateChanged)
    Q_PROPERTY(bool finalizing READ finalizing NOTIFY stateChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY stateChanged)
    Q_PROPERTY(bool flashEnabled READ flashEnabled WRITE setFlashEnabled NOTIFY preferencesChanged)
    Q_PROPERTY(bool mirrored READ mirrored WRITE setMirrored NOTIFY preferencesChanged)
    Q_PROPERTY(bool microphone READ microphone WRITE setMicrophone NOTIFY preferencesChanged)
    Q_PROPERTY(bool droidcamInstalled READ droidcamInstalled CONSTANT)
    Q_PROPERTY(QVariantList cameras READ cameras NOTIFY devicesChanged)
    Q_PROPERTY(QVariantList microphones READ microphones NOTIFY devicesChanged)
    Q_PROPERTY(int cameraIndex READ cameraIndex WRITE setCameraIndex NOTIFY devicesChanged)
    Q_PROPERTY(int microphoneIndex READ microphoneIndex WRITE setMicrophoneIndex NOTIFY devicesChanged)
    Q_PROPERTY(QVariantList gallery READ gallery NOTIFY galleryChanged)
    Q_PROPERTY(QString libraryPath READ libraryPath CONSTANT)
public:
    explicit Booth(QString library = {}, bool demo = false, bool useCamera = true, QObject *parent = nullptr);
    ~Booth() override;
    QObject *exportDialog() const;
    bool dark() const { return m_dark; }
    QString fontFamily() const { return m_font; }
    QString controlsPath() const;
    bool demo() const { return m_demo; }
    bool hasFrame() const { return !m_frame.isNull(); }
    QString status() const { return m_status; }
    int mode() const { return m_mode; }
    int effect() const { return m_effect; }
    double strength() const { return m_strength; }
    QStringList effectNames() const;
    int countdown() const { return m_countdown; }
    int burstProgress() const { return m_shots.size(); }
    bool busy() const { return m_capturing || m_recording || m_finalizing; }
    bool recording() const { return m_recording; }
    bool finalizing() const { return m_finalizing; }
    qint64 duration() const { return m_recorder.duration(); }
    bool flashEnabled() const { return m_flash; }
    bool mirrored() const { return m_mirrored; }
    bool microphone() const { return m_microphone; }
    bool droidcamInstalled() const;
    QVariantList cameras() const;
    QVariantList microphones() const;
    int cameraIndex() const { return m_cameraIndex; }
    int microphoneIndex() const { return m_microphoneIndex; }
    QVariantList gallery() const { return m_gallery; }
    QString libraryPath() const { return m_library; }
    QImage frame() const { return m_frame; }
    QImage currentImage() const { return m_processed; }
    void feedImage(const QImage &image);
    void setMode(int mode);
    void setEffect(int effect);
    void setStrength(double strength);
    void setFlashEnabled(bool enabled);
    void setMirrored(bool enabled);
    void setMicrophone(bool enabled);
    void setCameraIndex(int index);
    void setMicrophoneIndex(int index);
    Q_INVOKABLE void capture(bool skipCountdown = false, bool suppressFlash = false);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void stopRecording();
    Q_INVOKABLE void retryCamera();
    Q_INVOKABLE void openDroidcam();
    Q_INVOKABLE bool exportMedia(const QUrl &source, const QUrl &destination);
    Q_INVOKABLE bool trashMedia(const QUrl &source);
    Q_INVOKABLE void copyMedia(const QUrl &source);
    Q_INVOKABLE void openLibrary();
    Q_INVOKABLE void refreshGallery();
    Q_INVOKABLE void windowReady();
    Q_INVOKABLE void minimize();
    Q_INVOKABLE void requestClose();
signals:
    void frameChanged();
    void themeChanged();
    void effectChanged();
    void preferencesChanged();
    void stateChanged();
    void devicesChanged();
    void galleryChanged();
    void flashRequested();
    void saved(QUrl url);
    void closeReady();
    void exportFailed(QString message);
private:
    void readTheme();
    void scanDevices();
    void processFrame();
    void takeShot();
    void startRecording();
    void sendRecordingFrame();
    bool saveImage(const QImage &image, const QString &path);
    QString makePath(const QString &suffix) const;
    bool owns(const QUrl &url) const;
    void setStatus(const QString &status);
    void savePreferences();
    void withWindow(const QString &action);
    QString m_library, m_status, m_font = "SF Pro Text", m_videoPath;
    bool m_demo=false, m_useCamera=true, m_dark=true, m_flash=true, m_mirrored=true, m_microphone=true;
    bool m_capturing=false, m_recording=false, m_finalizing=false, m_suppressFlash=false, m_ready=false, m_closePending=false, m_recordFailed=false;
    bool m_demoAudioReady=false;
    int m_mode=1, m_effect=4, m_countdown=0, m_cameraIndex=-1, m_microphoneIndex=-1;
    quint64 m_captureGeneration=0;
    double m_strength=0.5;
    QSize m_recordSize;
    QImage m_frame, m_processed;
    QList<QImage> m_shots;
    QVariantList m_gallery;
    QSettings m_preferences;
    NautilusSaveDialog *m_exportDialog=nullptr;
    QMediaDevices m_devices;
    QCamera m_camera;
    QVideoSink m_sink;
    QMediaCaptureSession m_cameraSession, m_recordSession;
    QVideoFrameInput m_videoInput;
    QMediaRecorder m_recorder;
    QAudioInput *m_audioInput=nullptr;
    QAudioBufferInput m_demoAudio;
    QAudioFormat m_demoAudioFormat;
    qint64 m_demoSamples=0;
    QTimer m_countTimer, m_frameTimer, m_demoTimer, m_demoAudioTimer, m_themeDebounce, m_galleryDebounce, m_cameraPoll;
    QElapsedTimer m_recordClock, m_previewClock;
    QFileSystemWatcher m_watcher;
};
