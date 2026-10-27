#include "booth.h"
#include "frameview.h"
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QCommandLineParser>
#include <QIcon>
#include <QQuickWindow>

int main(int argc,char **argv) {
    qputenv("QT_MEDIA_BACKEND","ffmpeg");
    QGuiApplication app(argc,argv);
    QCoreApplication::setOrganizationName("MacShell");
    QCoreApplication::setApplicationName("Photo Booth");
    QCoreApplication::setApplicationVersion("1.0.0");
    QGuiApplication::setDesktopFileName("org.macshell.PhotoBooth");
    app.setWindowIcon(QIcon(":/packaging/org.macshell.PhotoBooth.svg"));
    QCommandLineParser parser;
    parser.setApplicationDescription("Photo Booth for Hyprland · MacTahoe camera, live effects, and local gallery");
    parser.addHelpOption(); parser.addVersionOption();
    parser.addOption({"demo","Use an explicitly labelled synthetic camera and test tone (no hardware access)."});
    parser.addOption({"library","Save media in a custom folder.","folder"});
    parser.addOption({"screenshot","Save a UI preview, then exit. Combine with --demo to avoid hardware access.","file"});
    parser.process(app);
    QQuickStyle::setStyle("Basic");
    qmlRegisterType<FrameView>("Tahoe.PhotoBooth",1,0,"CameraView");
    qmlRegisterUncreatableType<Booth>("Tahoe.PhotoBooth",1,0,"Booth","Available as the booth context object");
    Booth booth(parser.value("library"),parser.isSet("demo"));
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("booth",&booth);
    QObject::connect(&engine,&QQmlApplicationEngine::objectCreationFailed,&app,[] { QCoreApplication::exit(1); },Qt::QueuedConnection);
    engine.load(QUrl("qrc:/qml/Main.qml"));
    if(parser.isSet("screenshot")) QTimer::singleShot(1200,&app,[&] {
        auto *window=engine.rootObjects().isEmpty()?nullptr:qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        const bool saved=window && window->grabWindow().save(parser.value("screenshot"));
        app.exit(saved?0:1);
    });
    return app.exec();
}
