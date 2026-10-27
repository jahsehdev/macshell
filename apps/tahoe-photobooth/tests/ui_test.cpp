#include "../src/booth.h"
#include "../src/frameview.h"
#include <QtTest>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QSGRendererInterface>
#include <QTemporaryDir>
#include <QSaveFile>
#include <QPainter>
#include <QClipboard>
#include <QMimeData>

class UiTests:public QObject {
    Q_OBJECT
    QTemporaryDir library;
    QStringList errors;
    void writeTheme(const QByteArray &json) {
        QSaveFile file(qEnvironmentVariable("XDG_CONFIG_HOME")+"/macbar/settings.json");
        QVERIFY(file.open(QIODevice::WriteOnly)); QCOMPARE(file.write(json),json.size()); QVERIFY(file.commit());
    }
    QQuickItem *findVisual(QQuickItem *root,const QString &name) {
        if(root->objectName()==name) return root;
        for(auto *child:root->childItems()) if(auto *found=findVisual(child,name)) return found;
        return nullptr;
    }
    QQuickItem *item(QQuickWindow *window,const char *name) { return findVisual(window->contentItem(),QString::fromLatin1(name)); }
    void click(QQuickWindow *window,const char *name,Qt::KeyboardModifiers modifiers=Qt::NoModifier) {
        auto *button=item(window,name); QVERIFY2(button,name); QVERIFY(button->isVisible());
        QTest::mouseClick(window,Qt::LeftButton,modifiers,button->mapToScene(QPointF(button->width()/2,button->height()/2)).toPoint());
    }
private slots:
    void toolbarAndDeviceControls_data() {
        QTest::addColumn<bool>("dark");
        QTest::newRow("light") << false;
        QTest::newRow("dark") << true;
    }
    void toolbarAndDeviceControls() {
        QFETCH(bool,dark);
        writeTheme(dark ? "{\"appearanceMode\":\"dark\"}" : "{\"appearanceMode\":\"light\"}");
        Booth booth(library.path()+"/controls-"+(dark?"dark":"light"),true,false);
        booth.setEffect(4); booth.setFlashEnabled(false);
        QQmlApplicationEngine engine;
        QStringList warnings;
        connect(&engine,&QQmlEngine::warnings,this,[&warnings](const QList<QQmlError> &items) {
            for(const auto &warning:items) warnings.append(warning.toString());
        });
        engine.rootContext()->setContextProperty("booth",&booth);
        engine.load(QUrl("qrc:/qml/Main.qml"));
        QVERIFY2(!engine.rootObjects().isEmpty(),qPrintable(warnings.join('\n')));
        auto *window=qobject_cast<QQuickWindow *>(engine.rootObjects().first()); QVERIFY(window);
        QTRY_VERIFY(booth.hasFrame());
        booth.capture(true,true); QTRY_COMPARE(booth.gallery().size(),1);
        QTRY_VERIFY(item(window,"galleryCapture-0"));
        click(window,"galleryCapture-0"); QVERIFY(window->property("viewing").toBool());
        for(const QSize size:{QSize(800,640),QSize(560,450)}) {
            window->resize(size); QTest::qWait(150);
            QRectF previous;
            for(const char *name:{"backToCameraButton","copyButton","exportButton","trashButton"}) {
                auto *button=item(window,name); QVERIFY(button); QVERIFY(button->isVisible());
                const auto bounds=button->mapRectToScene(button->boundingRect());
                QVERIFY(bounds.left()>=0 && bounds.right()<=window->width());
                QVERIFY(bounds.top()>=0 && bounds.bottom()<=window->height());
                QVERIFY(!bounds.intersects(previous)); previous=bounds;
            }
            QVERIFY(window->grabWindow().save(QDir::currentPath()+QString("/photobooth-gallery-%1-%2.png").arg(dark?"dark":"light").arg(size.width())));
        }
        click(window,"copyButton");
        QVERIFY(QGuiApplication::clipboard()->mimeData()->hasImage());
        QVERIFY(!item(window,"copyButton")->property("visualFocus").toBool());
        QTest::keyClick(window,Qt::Key_Tab);
        QVERIFY(item(window,"exportButton")->property("visualFocus").toBool());
        auto *ring=findVisual(item(window,"exportButton"),"keyboardFocusRing"); QVERIFY(ring); QVERIFY(ring->isVisible());
        click(window,"backToCameraButton"); QVERIFY(!window->property("viewing").toBool());
        click(window,"settingsButton");
        auto *menu=window->findChild<QObject *>("settingsMenu"); QVERIFY(menu);
        QTRY_VERIFY(menu->property("opened").toBool());
        auto *picker=item(window,"cameraPicker"); QVERIFY(picker);
        // Synthetic device choices exercise the dropdown without camera hardware.
        const QVariantList devices{QVariantMap{{"name","First camera"}},QVariantMap{{"name","Second camera"}}};
        QVERIFY(picker->setProperty("model",devices)); picker->setEnabled(true);
        picker->setProperty("currentIndex",0);
        QSignalSpy activated(picker,SIGNAL(activated(int)));
        click(window,"cameraPicker");
        auto *popup=picker->property("popup").value<QObject *>(); QVERIFY(popup);
        QTRY_VERIFY(popup->property("opened").toBool());
        auto *list=popup->property("contentItem").value<QQuickItem *>(); QVERIFY(list);
        QTest::qWait(100);
        QVERIFY(window->grabWindow().save(QDir::currentPath()+QString("/photobooth-devices-%1.png").arg(dark?"dark":"light")));
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,list->mapToScene(QPointF(40,45)).toPoint());
        QTRY_COMPARE(picker->property("currentIndex").toInt(),1);
        QCOMPARE(activated.size(),1);
        QTRY_VERIFY(!popup->property("visible").toBool());
        QTest::keyClick(window,Qt::Key_Escape); QTRY_VERIFY(!menu->property("visible").toBool());
        QVERIFY2(warnings.isEmpty(),qPrintable(warnings.join('\n')));
        window->setProperty("allowClose",true); window->close();
    }
    void deleteConfirmation_data() {
        QTest::addColumn<bool>("dark");
        QTest::newRow("light") << false;
        QTest::newRow("dark") << true;
    }
    void deleteConfirmation() {
        QFETCH(bool,dark);
        writeTheme(dark ? "{\"appearanceMode\":\"dark\"}" : "{\"appearanceMode\":\"light\"}");
        Booth booth(library.path()+"/delete-"+(dark?"dark":"light"),false,false);
        booth.setEffect(4); booth.setFlashEnabled(false);
        QImage frame(320,240,QImage::Format_RGB32); frame.fill(QColor("#506b77"));
        booth.feedImage(frame); booth.capture(true,true);
        QTRY_COMPARE(booth.gallery().size(),1);
        const auto capture=booth.gallery().first().toMap();
        const QString original=capture.value("url").toUrl().toLocalFile();
        QQmlApplicationEngine engine;
        QStringList warnings;
        connect(&engine,&QQmlEngine::warnings,this,[&warnings](const QList<QQmlError> &items) {
            for(const auto &warning:items) warnings.append(warning.toString());
        });
        engine.rootContext()->setContextProperty("booth",&booth);
        engine.load(QUrl("qrc:/qml/Main.qml"));
        QVERIFY2(!engine.rootObjects().isEmpty(),qPrintable(warnings.join('\n')));
        auto *window=qobject_cast<QQuickWindow *>(engine.rootObjects().first()); QVERIFY(window);
        window->setProperty("selected",capture); QTest::qWait(100);
        auto *dialog=window->findChild<QObject *>("deleteDialog"); QVERIFY(dialog);
        QSignalSpy accepted(dialog,SIGNAL(accepted()));
        click(window,"trashButton"); QTRY_VERIFY(dialog->property("opened").toBool());
        QTest::qWait(100);
        QVERIFY(window->grabWindow().save(QDir::currentPath()+QString("/photobooth-delete-%1.png").arg(dark?"dark":"light")));
        click(window,"cancelDeleteButton"); QTRY_VERIFY(!dialog->property("visible").toBool());
        QVERIFY(QFileInfo::exists(original)); QCOMPARE(booth.gallery().size(),1); QCOMPARE(accepted.size(),0);
        click(window,"trashButton"); QTRY_VERIFY(dialog->property("opened").toBool());
        QTest::keyClick(window,Qt::Key_Escape); QTRY_VERIFY(!dialog->property("visible").toBool());
        QVERIFY(QFileInfo::exists(original)); QVERIFY(window->property("viewing").toBool()); QCOMPARE(accepted.size(),0);
        click(window,"trashButton"); QTRY_VERIFY(dialog->property("opened").toBool());
        click(window,"confirmDeleteButton"); QTRY_VERIFY(!dialog->property("visible").toBool());
        // Confirm the UI action independently of OS Trash support in headless sandboxes.
        QCOMPARE(accepted.size(),1);
        QVERIFY2(warnings.isEmpty(),qPrintable(warnings.join('\n')));
        window->setProperty("allowClose",true); window->close();
    }
    void cameraPreviewFillsArea() {
        Booth booth(library.path()+"/fill",false,false);
        booth.setEffect(4); booth.setMirrored(false);
        QImage source(320,240,QImage::Format_RGB32); source.fill(QColor("#00aa55"));
        { QPainter painter(&source); painter.setPen(Qt::NoPen); painter.setBrush(Qt::blue);
          painter.drawRect(QRectF(110,70,100,100)); }
        booth.feedImage(source);
        FrameView preview; preview.setWidth(800); preview.setHeight(520); preview.setBooth(&booth);
        QImage output(800,520,QImage::Format_RGB32); output.fill(Qt::black);
        { QPainter painter(&output); preview.paint(&painter); }
        // A 4:3 camera fills a wider view, with no black bars at either edge.
        for(const QPoint corner:{QPoint(1,1),QPoint(798,1),QPoint(1,518),QPoint(798,518)})
            QCOMPARE(output.pixelColor(corner),QColor("#00aa55"));
        // A square stays square: filling must crop, rather than stretch the feed.
        int horizontal=0,vertical=0;
        for(int x=0;x<800;++x) if(output.pixelColor(x,260)==QColor(Qt::blue)) ++horizontal;
        for(int y=0;y<520;++y) if(output.pixelColor(400,y)==QColor(Qt::blue)) ++vertical;
        QVERIFY(horizontal>240);
        QVERIFY2(std::abs(horizontal-vertical)<=2,qPrintable(QString("square raster spans: %1 x %2").arg(horizontal).arg(vertical)));
        QCOMPARE(booth.currentImage().size(),QSize(320,240));
    }
    void settingsMotion_data() {
        QTest::addColumn<bool>("dark");
        QTest::newRow("light") << false;
        QTest::newRow("dark") << true;
    }
    void settingsMotion() {
        QFETCH(bool,dark);
        writeTheme(dark ? "{\"appearanceMode\":\"dark\"}" : "{\"appearanceMode\":\"light\"}");
        Booth booth(library.path()+"/motion",true,false);
        QQmlApplicationEngine engine;
        QStringList warnings;
        connect(&engine,&QQmlEngine::warnings,this,[&warnings](const QList<QQmlError> &items) {
            for(const auto &warning:items) warnings.append(warning.toString());
        });
        engine.rootContext()->setContextProperty("booth",&booth);
        engine.load(QUrl("qrc:/qml/Main.qml"));
        QVERIFY2(!engine.rootObjects().isEmpty(),qPrintable(warnings.join('\n')));
        auto *window=qobject_cast<QQuickWindow *>(engine.rootObjects().first()); QVERIFY(window);
        QTRY_VERIFY(booth.hasFrame()); QTest::qWait(100);
        const auto graphicsApi=window->rendererInterface()->graphicsApi();
        const bool renderedPixels=graphicsApi!=QSGRendererInterface::Null;
        auto *menu=window->findChild<QObject *>("settingsMenu"); QVERIFY(menu);
        // A click during entry must reverse it, rather than reopen an unopened popup.
        click(window,"settingsButton"); QTest::qWait(70);
        QVERIFY(menu->property("visible").toBool()); QVERIFY(!menu->property("opened").toBool());
        const auto opening=window->grabWindow();
        if(renderedPixels) QVERIFY(opening.save(QDir::currentPath()+QString("/photobooth-settings-opening-%1.png").arg(dark?"dark":"light")));
        click(window,"settingsButton"); QTest::qWait(50);
        QVERIFY(!menu->property("requestedOpen").toBool());
        click(window,"settingsButton");
        QTRY_VERIFY(menu->property("opened").toBool());
        QVERIFY(menu->property("requestedOpen").toBool());
        QVERIFY(!menu->property("modal").toBool()); QVERIFY(!menu->property("dim").toBool());
        const auto open=window->grabWindow();
        if(renderedPixels) {
            QVERIFY(open!=opening);
            QVERIFY(open.save(QDir::currentPath()+QString("/photobooth-settings-open-%1.png").arg(dark?"dark":"light")));
        }
        if(graphicsApi!=QSGRendererInterface::Software) {
            auto *shader=window->findChild<QObject *>("settingsRefraction"); QVERIFY(shader);
            QTRY_COMPARE(shader->property("status").toInt(),1); // ShaderEffect.Compiled
        }
        QTest::keyClick(window,Qt::Key_Escape); QTest::qWait(70);
        QVERIFY(menu->property("visible").toBool()); QVERIFY(!menu->property("requestedOpen").toBool());
        if(renderedPixels) QVERIFY(window->grabWindow().save(QDir::currentPath()+QString("/photobooth-settings-closing-%1.png").arg(dark?"dark":"light")));
        QTRY_VERIFY(!menu->property("visible").toBool());
        // Keyboard reopening and outside dismissal also complete at minimum size.
        window->resize(560,450); QTest::qWait(50);
        QTest::keyClick(window,Qt::Key_Comma,Qt::ControlModifier);
        QTRY_VERIFY(menu->property("opened").toBool());
        auto *content=menu->property("contentItem").value<QQuickItem *>(); QVERIFY(content);
        auto bounds=content->mapRectToScene(content->boundingRect());
        QVERIFY(bounds.left()>=0 && bounds.top()>=0);
        QVERIFY(bounds.right()<=window->width() && bounds.bottom()<=window->height());
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,QPoint(100,100));
        QTRY_VERIFY(!menu->property("visible").toBool());
        QVERIFY2(warnings.isEmpty(),qPrintable(warnings.join('\n')));
        window->setProperty("allowClose",true); window->close();
    }
    void closeTrafficLightOnce_data() {
        QTest::addColumn<int>("state");
        QTest::newRow("no-camera") << 0;
        QTest::newRow("live-preview") << 1;
        QTest::newRow("countdown") << 2;
        QTest::newRow("recording") << 3;
    }
    void closeTrafficLightOnce() {
        QFETCH(int,state);
        Booth booth(library.path()+"/close-"+QString::number(state),state!=0,false);
        booth.setFlashEnabled(false); booth.setMicrophone(false);
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("booth",&booth);
        engine.load(QUrl("qrc:/qml/Main.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window=qobject_cast<QQuickWindow *>(engine.rootObjects().first()); QVERIFY(window);
        QTRY_VERIFY(window->isVisible());
        if(state!=0) QTRY_VERIFY(booth.hasFrame());
        QSignalSpy saved(&booth,&Booth::saved);
        if(state==2) { booth.capture(); QCOMPARE(booth.countdown(),3); }
        if(state==3) {
            booth.setMode(2); booth.capture(true,true);
            QTRY_VERIFY(booth.recording()); QTest::qWait(400);
        }
        // Exactly one real pointer click, with the normal close guard enabled.
        QVERIFY(!window->property("allowClose").toBool());
        click(window,"trafficLight-close");
        QTRY_VERIFY_WITH_TIMEOUT(!window->isVisible(),2000);
        QVERIFY(!booth.busy()); QCOMPARE(booth.countdown(),0);
        if(state==3) {
            QCOMPARE(saved.size(),1);
            QVERIFY(QFileInfo(saved[0][0].toUrl().toLocalFile()).size()>0);
        } else QCOMPARE(saved.size(),0);
    }
    void cameraUiAndTheme() {
        writeTheme("{\"appearanceMode\":\"dark\",\"darkMode\":true}");
        Booth booth(library.path(),true,false); booth.setEffect(4); booth.setFlashEnabled(false); booth.setMicrophone(false);
        QQmlApplicationEngine engine;
        connect(&engine,&QQmlEngine::warnings,this,[this](const QList<QQmlError> &warnings) { for(const auto &warning:warnings) errors.append(warning.toString()); });
        engine.rootContext()->setContextProperty("booth",&booth);
        engine.load(QUrl("qrc:/qml/Main.qml"));
        QVERIFY2(!engine.rootObjects().isEmpty(),qPrintable(errors.join('\n')));
        auto *window=qobject_cast<QQuickWindow *>(engine.rootObjects().first()); QVERIFY(window);
        QTRY_VERIFY(booth.hasFrame()); QTest::qWait(250);
        click(window,"effectsButton"); QCOMPARE(window->property("effectsOpen").toBool(),true);
        QTest::qWait(200);
        QVERIFY(window->grabWindow().save(QDir::currentPath()+"/photobooth-effects.png"));
        click(window,"effect-1"); QCOMPARE(booth.effect(),1); QVERIFY(!window->property("effectsOpen").toBool());
        click(window,"mode-0"); QCOMPARE(booth.mode(),0);
        click(window,"mode-1"); QCOMPARE(booth.mode(),1);
        QSignalSpy saved(&booth,&Booth::saved);
        click(window,"captureButton",Qt::AltModifier | Qt::ShiftModifier);
        QTRY_COMPARE_WITH_TIMEOUT(saved.size(),1,1200);
        QVERIFY(!booth.busy()); QCOMPARE(booth.gallery().size(),1);
        QVERIFY(window->grabWindow().save(QDir::currentPath()+"/photobooth-dark.png"));
        click(window,"settingsButton");
        auto *menu=window->findChild<QObject *>("settingsMenu"); QVERIFY(menu); QTRY_VERIFY(menu->property("opened").toBool());
        QVERIFY(!menu->property("modal").toBool()); QVERIFY(!menu->property("dim").toBool());
        QTest::qWait(100);
        QVERIFY(window->grabWindow().save(QDir::currentPath()+"/photobooth-settings-dark.png"));
        click(window,"settingsButton"); QTRY_VERIFY(!menu->property("opened").toBool());
        click(window,"settingsButton"); QTRY_VERIFY(menu->property("opened").toBool());
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,QPoint(100,100)); QTRY_VERIFY(!menu->property("opened").toBool());
        writeTheme("{\"appearanceMode\":\"light\",\"darkMode\":true}");
        QTRY_COMPARE(booth.dark(),false); QTest::qWait(200);
        QVERIFY(window->grabWindow().save(QDir::currentPath()+"/photobooth-light.png"));
        click(window,"settingsButton"); QTRY_VERIFY(menu->property("opened").toBool()); QTest::qWait(100);
        QVERIFY(window->grabWindow().save(QDir::currentPath()+"/photobooth-settings-light.png"));
        auto *toggle=item(window,"microphoneToggle"); QVERIFY(toggle);
        auto position=toggle->mapToScene(QPointF(toggle->width()/2,toggle->height()/2)).toPoint();
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,position); QVERIFY(booth.microphone());
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,position); QVERIFY(!booth.microphone());
        QTest::keyClick(window,Qt::Key_Escape); QTRY_VERIFY(!menu->property("opened").toBool());
        click(window,"mode-2"); QCOMPARE(booth.mode(),2);
        click(window,"captureButton",Qt::AltModifier); QTRY_VERIFY(booth.recording());
        QTest::qWait(400); click(window,"captureButton");
        QTRY_VERIFY_WITH_TIMEOUT(!booth.busy(),8000); QTRY_COMPARE(saved.size(),2);
        QVERIFY2(errors.isEmpty(),qPrintable(errors.join('\n')));
        window->setProperty("allowClose",true); window->close();
    }
    void noCameraState() {
        Booth booth(library.path()+"/no-camera",false,false);
        QQmlApplicationEngine engine; engine.rootContext()->setContextProperty("booth",&booth); engine.load(QUrl("qrc:/qml/Main.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window=qobject_cast<QQuickWindow *>(engine.rootObjects().first()); QVERIFY(window); QTest::qWait(150);
        QVERIFY(!item(window,"captureButton")->isEnabled());
        QVERIFY(window->grabWindow().save(QDir::currentPath()+"/photobooth-no-camera.png"));
        window->setProperty("allowClose",true); window->close();
    }
};
int main(int argc,char **argv) {
    QTemporaryDir environment;
    qputenv("XDG_CONFIG_HOME",(environment.path()+"/config").toUtf8());
    qputenv("XDG_DATA_HOME",(environment.path()+"/data").toUtf8());
    qputenv("XDG_CACHE_HOME",(environment.path()+"/cache").toUtf8());
    QDir().mkpath(environment.path()+"/config/macbar");
    QDir().mkpath(environment.path()+"/config/macshell");
    QGuiApplication app(argc,argv); app.setQuitOnLastWindowClosed(false); QQuickStyle::setStyle("Basic");
    qmlRegisterType<FrameView>("Tahoe.PhotoBooth",1,0,"CameraView");
    qmlRegisterUncreatableType<Booth>("Tahoe.PhotoBooth",1,0,"Booth","Test controller");
    UiTests tests; return QTest::qExec(&tests,argc,argv);
}
#include "ui_test.moc"
