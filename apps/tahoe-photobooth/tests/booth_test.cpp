#include "../src/booth.h"
#include "../src/effects.h"
#include <QtTest>
#include <QTemporaryDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcess>
#include <QGuiApplication>
#include <QPainter>
#include <QSaveFile>

class BoothTests: public QObject {
    Q_OBJECT
    QTemporaryDir root;
    QImage pattern() {
        QImage image(320,240,QImage::Format_RGB32);
        for(int y=0;y<240;++y) for(int x=0;x<320;++x) image.setPixel(x,y,qRgb(x*255/319,y*255/239,(x+y)%256));
        return image;
    }
    QString folder(const QString &name) { return root.path()+"/"+name; }
    void reset(Booth &booth) { booth.setEffect(4); booth.setMirrored(false); booth.setFlashEnabled(false); }
private slots:
    void effectsAndMirror() {
        QImage source=pattern();
        auto mono=Effects::apply(source,0);
        for(int y=0;y<mono.height();y+=17) for(int x=0;x<mono.width();x+=19) {
            auto pixel=mono.pixel(x,y); QCOMPARE(qRed(pixel),qGreen(pixel)); QCOMPARE(qRed(pixel),qBlue(pixel));
        }
        QCOMPARE(Effects::apply(source,4),source);
        for(int effect=0;effect<9;++effect) {
            auto output=Effects::apply(source,effect,0.65);
            QCOMPARE(output.size(),source.size());
            if(effect!=4) QVERIFY(output!=source);
        }
        Booth booth(folder("mirror"),false,false); reset(booth); booth.feedImage(source); booth.setMirrored(true);
        QCOMPARE(booth.currentImage().pixel(0,0),source.pixel(source.width()-1,0));
    }
    void fourUpLayout() {
        QList<QImage> images;
        for(QColor color:{QColor(Qt::red),QColor(Qt::green),QColor(Qt::blue),QColor(Qt::yellow)}) { QImage image(80,60,QImage::Format_RGB32); image.fill(color); images.append(image); }
        auto result=Effects::fourUp(images);
        QCOMPARE(result.size(),QSize(184,144));
        QCOMPARE(result.pixelColor(0,0),QColor(Qt::white));
        QCOMPARE(result.pixelColor(10,10),QColor(Qt::red));
        QCOMPARE(result.pixelColor(100,10),QColor(Qt::green));
        QCOMPARE(result.pixelColor(10,80),QColor(Qt::blue));
        QCOMPARE(result.pixelColor(100,80),QColor(Qt::yellow));
        QVERIFY(Effects::fourUp({}).isNull());
    }
    void captureAndExport() {
        Booth booth(folder("photo"),false,false); reset(booth); booth.feedImage(pattern()); booth.setEffect(0);
        QSignalSpy saved(&booth,&Booth::saved);
        booth.capture(true,true);
        QTRY_COMPARE(saved.size(),1);
        QVERIFY(!booth.busy()); QCOMPARE(booth.gallery().size(),1);
        auto url=saved[0][0].toUrl(); QImage image(url.toLocalFile()); QCOMPARE(image.size(),QSize(320,240));
        auto p=image.pixel(160,120); QVERIFY(std::abs(qRed(p)-qGreen(p))<=2);
        QString destination=folder("export with spaces.jpg");
        QVERIFY(booth.exportMedia(url,QUrl::fromLocalFile(destination)));
        QFile original(url.toLocalFile()), exported(destination); QVERIFY(original.open(QIODevice::ReadOnly)); QVERIFY(exported.open(QIODevice::ReadOnly)); QCOMPARE(original.readAll(),exported.readAll());
        QVERIFY(!booth.exportMedia(QUrl::fromLocalFile("/etc/passwd"),QUrl::fromLocalFile(folder("forbidden"))));
        QVERIFY(!booth.trashMedia(QUrl::fromLocalFile("/etc/passwd")));
    }
    void countdownCancellationAndStaleTimers() {
        Booth booth(folder("cancel"),false,false); reset(booth); booth.feedImage(pattern());
        QSignalSpy saved(&booth,&Booth::saved);
        booth.capture(); QCOMPARE(booth.countdown(),3); QVERIFY(booth.busy());
        booth.cancel(); QCOMPARE(booth.countdown(),0); QVERIFY(!booth.busy());
        booth.setFlashEnabled(true); booth.capture(true,false); booth.cancel();
        booth.setFlashEnabled(false); booth.capture(true,true);
        QTRY_COMPARE(saved.size(),1); QTest::qWait(200); QCOMPARE(saved.size(),1);
    }
    void timedCaptureAndBurst() {
        Booth booth(folder("countdown"),false,false); reset(booth); booth.feedImage(pattern());
        QSignalSpy saved(&booth,&Booth::saved);
        booth.capture(); QCOMPARE(booth.countdown(),3);
        QTest::qWait(300); QCOMPARE(saved.size(),0);
        QTRY_COMPARE_WITH_TIMEOUT(saved.size(),1,4200);
        booth.setMode(0); booth.capture(true,true);
        QTRY_COMPARE_WITH_TIMEOUT(saved.size(),2,4200);
        QImage image(saved[1][0].toUrl().toLocalFile()); QCOMPARE(image.size(),QSize(664,504));
        QCOMPARE(booth.gallery().size(),2); QVERIFY(!booth.busy());
    }
    void unavailableCamera() {
        Booth booth(folder("no-camera"),false,false);
        QSignalSpy saved(&booth,&Booth::saved);
        booth.capture(true,true); QVERIFY(!booth.busy()); QCOMPARE(saved.size(),0); QVERIFY(booth.status().contains("not ready"));
    }
    void themeFollowsAtomicSettings() {
        Booth booth(folder("theme"),false,false);
        auto write=[](QByteArray data) {
            QSaveFile file(qEnvironmentVariable("XDG_CONFIG_HOME")+"/macbar/settings.json");
            if(!file.open(QIODevice::WriteOnly)) return false;
            return file.write(data)==data.size() && file.commit();
        };
        QVERIFY(write("{\"appearanceMode\":\"light\",\"darkMode\":true}"));
        QTRY_COMPARE(booth.dark(),false);
        QVERIFY(write("{\"appearanceMode\":\"dark\",\"darkMode\":false}"));
        QTRY_COMPARE(booth.dark(),true);
        QVERIFY(write("{\"appearanceMode\":")); QTest::qWait(250); QCOMPARE(booth.dark(),true);
        QVERIFY(write("{\"appearanceMode\":\"auto\",\"darkMode\":false}")); QTRY_COMPARE(booth.dark(),false);
    }
    void effectVideoWithAudio() {
        Booth booth(folder("recording"),true,false); reset(booth); booth.setEffect(0); booth.setMicrophone(true);
        QTRY_VERIFY(booth.hasFrame());
        booth.setMode(2); QSignalSpy saved(&booth,&Booth::saved);
        booth.capture(true,true); QVERIFY(booth.recording());
        QTest::qWait(1400); booth.stopRecording();
        QTRY_COMPARE_WITH_TIMEOUT(saved.size(),1,12000);
        QVERIFY(!booth.busy()); QCOMPARE(booth.gallery().size(),1);
        QString path=saved[0][0].toUrl().toLocalFile();
        QProcess probe; probe.start("ffprobe",{"-v","error","-show_streams","-show_format","-of","json",path}); QVERIFY(probe.waitForFinished(5000)); QCOMPARE(probe.exitCode(),0);
        auto document=QJsonDocument::fromJson(probe.readAllStandardOutput()).object();
        bool audio=false, video=false;
        for(auto entry:document["streams"].toArray()) {
            auto stream=entry.toObject(); audio|=stream["codec_type"]=="audio"; video|=stream["codec_type"]=="video";
            double duration=stream["duration"].toString().toDouble();
            QVERIFY2(duration>0.8 && duration<3.0,qPrintable(QString("%1 stream duration was %2 seconds").arg(stream["codec_type"].toString()).arg(duration)));
        }
        QVERIFY(audio); QVERIFY(video);
        const double seconds=document["format"].toObject()["duration"].toString().toDouble();
        QVERIFY2(seconds>0.8 && seconds<3.0,qPrintable(QString("Recording duration was %1 seconds").arg(seconds)));
        QProcess extract; QString still=folder("decoded.png"); extract.start("ffmpeg",{"-v","error","-i",path,"-frames:v","1","-y",still}); QVERIFY(extract.waitForFinished(5000)); QCOMPARE(extract.exitCode(),0);
        QImage frame(still); QVERIFY(!frame.isNull());
        auto pixel=frame.pixel(300,220); QVERIFY(std::abs(qRed(pixel)-qBlue(pixel))<8);
        QFile::remove(QDir::currentPath()+"/recording-fixture.mp4");
        QVERIFY(QFile::copy(path,QDir::currentPath()+"/recording-fixture.mp4"));
    }
};
int main(int argc,char **argv) {
    QTemporaryDir environment;
    qputenv("XDG_CONFIG_HOME",(environment.path()+"/config").toUtf8());
    qputenv("XDG_DATA_HOME",(environment.path()+"/data").toUtf8());
    qputenv("XDG_CACHE_HOME",(environment.path()+"/cache").toUtf8());
    QDir().mkpath(environment.path()+"/config/macbar");
    QGuiApplication app(argc,argv);
    BoothTests tests; return QTest::qExec(&tests,argc,argv);
}
#include "booth_test.moc"
