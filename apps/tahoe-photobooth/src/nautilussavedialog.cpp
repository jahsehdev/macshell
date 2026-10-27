#include "nautilussavedialog.h"
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QSettings>
#include <QUuid>
#include <QWindow>
#include <limits>
#ifdef Q_OS_LINUX
#include <QtGui/private/qguiapplication_p.h>
#include <QtGui/private/qdesktopunixservices_p.h>
#include <qpa/qplatformintegration.h>
#endif

namespace {
constexpr auto service="org.gnome.Nautilus";
constexpr auto objectPath="/org/freedesktop/portal/desktop";
constexpr auto chooserInterface="org.freedesktop.impl.portal.FileChooser";
struct FilterRule { uint type=0; QString pattern; };
struct FileFilter { QString label; QList<FilterRule> rules; };
QDBusArgument &operator<<(QDBusArgument &a,const FilterRule &r) {
    a.beginStructure(); a<<r.type<<r.pattern; a.endStructure(); return a;
}
const QDBusArgument &operator>>(const QDBusArgument &a,FilterRule &r) {
    a.beginStructure(); a>>r.type>>r.pattern; a.endStructure(); return a;
}
QDBusArgument &operator<<(QDBusArgument &a,const FileFilter &f) {
    a.beginStructure(); a<<f.label<<f.rules; a.endStructure(); return a;
}
const QDBusArgument &operator>>(const QDBusArgument &a,FileFilter &f) {
    a.beginStructure(); a>>f.label>>f.rules; a.endStructure(); return a;
}
QString parentIdentifier(QWindow *window) {
#ifdef Q_OS_LINUX
    if(window && (QGuiApplication::platformName().startsWith("wayland") || QGuiApplication::platformName()=="xcb")) {
        auto *services=QGuiApplicationPrivate::platformIntegration()->services();
        if(auto *desktop=dynamic_cast<QDesktopUnixServices *>(services))
            return desktop->portalWindowIdentifier(window);
    }
#else
    Q_UNUSED(window);
#endif
    return {};
}
}
Q_DECLARE_METATYPE(FilterRule)
Q_DECLARE_METATYPE(FileFilter)

NautilusSaveDialog::NautilusSaveDialog(QObject *parent):QObject(parent) {}
NautilusSaveDialog::~NautilusSaveDialog() { close(); }

QVariantMap NautilusSaveDialog::saveOptions(const QUrl &source,const QString &folder) {
    // Portal filters have the exact D-Bus signature a(sa(us)).
    static const bool registered=[] {
        qDBusRegisterMetaType<FilterRule>();
        qDBusRegisterMetaType<QList<FilterRule>>();
        qDBusRegisterMetaType<FileFilter>();
        qDBusRegisterMetaType<QList<FileFilter>>();
        return true;
    }();
    Q_UNUSED(registered);
    const QFileInfo info(source.toLocalFile());
    const bool video=info.suffix().compare("mp4",Qt::CaseInsensitive)==0;
    const QList<FileFilter> filters={
        {video?QStringLiteral("MP4 video"):QStringLiteral("JPEG image"),{{0,video?"*.mp4":"*.jpg"}}},
        {QStringLiteral("All files"),{{0,QStringLiteral("*")}}}
    };
    return {
        {"current_name","Export "+info.fileName()},
        {"current_folder",QFile::encodeName(folder.isEmpty()?info.absolutePath():folder)+QByteArray(1,'\0')},
        {"accept_label",QStringLiteral("_Save")}, {"modal",true},
        {"filters",QVariant::fromValue(filters)},
        {"current_filter",QVariant::fromValue(filters.first())}
    };
}

QUrl NautilusSaveDialog::selectedFile(uint response,const QVariantMap &results,QString *error) {
    error->clear();
    if(response==1) return {}; // Cancel never exports or changes a file.
    if(response!=0) { *error="Nautilus could not complete the file selection."; return {}; }
    const QStringList uris=qdbus_cast<QStringList>(results.value("uris"));
    if(uris.size()!=1) { *error="Nautilus did not return an export destination."; return {}; }
    const QUrl destination(uris.first());
    if(!destination.isValid() || !destination.isLocalFile() || destination.toLocalFile().isEmpty()) {
        *error="Choose a local file to export this capture."; return {};
    }
    return destination;
}

void NautilusSaveDialog::open(const QUrl &source,QWindow *parentWindow) {
    if(visible()) return;
    if(!source.isLocalFile() || !QFileInfo(source.toLocalFile()).isFile()) {
        emit failed("The original capture is no longer available."); return;
    }
    const auto bus=QDBusConnection::sessionBus();
    if(!bus.isConnected()) { emit failed("Could not connect to Nautilus. The desktop session bus is unavailable."); return; }
    QSettings preferences("MacShell","PhotoBooth");
    QString folder=preferences.value("exportFolder").toString();
    if(!QDir(folder).exists()) folder.clear();
    QString sender=bus.baseService(); sender.remove(':'); sender.replace('.','_');
    m_handle=QStringLiteral("/org/freedesktop/portal/desktop/request/%1/export_%2")
        .arg(sender,QUuid::createUuid().toString(QUuid::Id128));
    auto message=QDBusMessage::createMethodCall(service,objectPath,chooserInterface,"SaveFile");
    message.setArguments({QVariant::fromValue(QDBusObjectPath(m_handle)),QStringLiteral("org.macshell.PhotoBooth"),
                          parentIdentifier(parentWindow),QStringLiteral("Export capture"),saveOptions(source,folder)});
    // Nautilus itself implements the chooser backend. This is the same endpoint
    // used by GNOME's portal, without changing Hyprland's global portal routing.
    m_pending=new QDBusPendingCallWatcher(bus.asyncCall(message,std::numeric_limits<int>::max()),this);
    emit visibleChanged();
    connect(m_pending,&QDBusPendingCallWatcher::finished,this,[this,source](QDBusPendingCallWatcher *watcher) {
        const QDBusPendingReply<uint,QVariantMap> reply=*watcher;
        m_pending=nullptr; watcher->deleteLater(); m_handle.clear(); emit visibleChanged();
        if(reply.isError()) {
            emit failed("Could not open Nautilus's save dialog.\n"+reply.error().message()); return;
        }
        QString error;
        const QUrl destination=selectedFile(reply.argumentAt<0>(),reply.argumentAt<1>(),&error);
        if(!error.isEmpty()) { emit failed(error); return; }
        if(destination.isEmpty()) return;
        QSettings("MacShell","PhotoBooth").setValue("exportFolder",QFileInfo(destination.toLocalFile()).absolutePath());
        emit fileSelected(source,destination);
    });
}
void NautilusSaveDialog::close() {
    if(!visible()) return;
    if(m_pending) { m_pending->disconnect(this); m_pending->deleteLater(); m_pending=nullptr; }
    auto message=QDBusMessage::createMethodCall(service,m_handle,"org.freedesktop.impl.portal.Request","Close");
    QDBusConnection::sessionBus().asyncCall(message);
    m_handle.clear(); emit visibleChanged();
}
