// Application-local Qt style: real controls inside Dolphin's existing toolbar.
#include <QAbstractButton>
#include <QAction>
#include <QApplication>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QHBoxLayout>
#include <QMainWindow>
#include <QMenuBar>
#include <QMouseEvent>
#include <QPainter>
#include <QPointer>
#include <QProcess>
#include <QProxyStyle>
#include <QStandardPaths>
#include <QStyleFactory>
#include <QStylePlugin>
#include <QTabWidget>
#include <QTabBar>
#include <QTimer>
#include <QToolBar>
#include <QToolBox>
#include <QWindow>
#include <QWidgetAction>

namespace {
// Only the empty part of an existing row initiates a native compositor move.
// Child controls and actions retain their normal press, click and tab gestures.
class NativeRowDrag final : public QObject {
public:
    NativeRowDrag(QWidget *row, QWidget *window)
        : QObject(row), m_row(row), m_window(window) {
        row->installEventFilter(this);
    }
    bool eventFilter(QObject *, QEvent *event) override {
        if (!m_row || !m_window || (event->type() != QEvent::MouseButtonPress
            && event->type() != QEvent::MouseButtonDblClick)) return false;
        auto *mouse = static_cast<QMouseEvent *>(event);
        const auto point = mouse->position().toPoint();
        if (mouse->button() != Qt::LeftButton || m_row->childAt(point)) return false;
        if (auto *bar = qobject_cast<QToolBar *>(m_row.data()); bar && bar->actionAt(point)) return false;
        if (auto *bar = qobject_cast<QMenuBar *>(m_row.data()); bar && bar->actionAt(point)) return false;
        if (auto *bar = qobject_cast<QTabBar *>(m_row.data()); bar && bar->tabAt(point) >= 0) return false;
        if (auto *tabs = qobject_cast<QTabWidget *>(m_row.data())) {
            auto *bar = tabs->findChild<QTabBar *>();
            if (!bar || point.y() < bar->y() || point.y() >= bar->y() + bar->height()) return false;
        }
        if (event->type() == QEvent::MouseButtonDblClick) {
            const auto helper = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
                              + "/quickshell/MacShell/bin/titlebar_action.py";
            QProcess::startDetached("python3", {helper, "--pid", QString::number(QCoreApplication::applicationPid())});
            return true;
        }
        return m_window->windowHandle() && m_window->windowHandle()->startSystemMove();
    }
private:
    QPointer<QWidget> m_row, m_window;
};

bool darkAppearance() {
    QFile settings(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
                   + "/gtk-3.0/settings.ini");
    return !settings.open(QIODevice::ReadOnly)
        || !settings.readAll().contains("gtk-theme-name=MacTahoe-Light");
}

class TrafficButton final : public QAbstractButton {
public:
    TrafficButton(const QString &kind, QWidget *window, QWidget *parent)
        : QAbstractButton(parent), m_kind(kind), m_window(window) {
        setObjectName("macshell-" + kind);
        setAccessibleName(kind == "close" ? tr("Close window")
                          : kind == "minimize" ? tr("Minimize window")
                          : tr("Maximize or restore window"));
        setToolTip(accessibleName());
        setFixedSize(18, 28);
        setFocusPolicy(Qt::StrongFocus);
        setAttribute(Qt::WA_Hover);
        window->installEventFilter(this);
        connect(this, &QAbstractButton::clicked, this, [this] {
            if (!m_window) return;
            if (m_kind == "close") m_window->close();
            else if (m_kind == "minimize") {
                const auto helper = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
                                  + "/hypr/minimize.sh";
                // The button belongs to the active window. Use the same Dock
                // animation and special workspace as the other native controls.
                QProcess::startDetached("/bin/sh", {helper, "minimize"});
            } else if (m_window->isMaximized()) m_window->showNormal();
            else m_window->showMaximized();
        });
    }
protected:
    void paintEvent(QPaintEvent *) override {
        if (!m_window) return;
        const bool dark = darkAppearance();
        const bool active = m_window->isActiveWindow();
        const QString kind = m_kind == "maximize" && m_window->isMaximized()
                           ? "restore" : m_kind;
        const QString suffix = isDown() ? "-active"
                             : !active ? (underMouse() ? "-backdrop-hover" : "-backdrop")
                             : underMouse() ? "-hover" : "";
        const QString path = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + "/macshell/window-controls/" + (dark ? "dark/" : "light/")
            + "titlebutton-" + kind + suffix + (dark ? "-dark" : "") + "@2.png";
        QPainter painter(this);
        painter.setRenderHint(QPainter::SmoothPixmapTransform);
        painter.drawPixmap(QRect((width() - 16) / 2, (height() - 16) / 2, 16, 16), QPixmap(path));
        if (hasFocus()) {
            painter.setPen(palette().highlight().color());
            painter.setBrush(Qt::NoBrush);
            painter.drawEllipse(QRect((width() - 16) / 2, (height() - 16) / 2, 16, 16));
        }
    }
    bool event(QEvent *event) override {
        if (event->type() == QEvent::Enter || event->type() == QEvent::Leave
            || event->type() == QEvent::PaletteChange) update();
        return QAbstractButton::event(event);
    }
    bool eventFilter(QObject *object, QEvent *event) override {
        if (event->type() == QEvent::WindowActivate || event->type() == QEvent::WindowDeactivate
            || event->type() == QEvent::WindowStateChange) update();
        return QAbstractButton::eventFilter(object, event);
    }
private:
    QString m_kind;
    QPointer<QWidget> m_window;
};

class Controls final : public QWidget {
public:
    Controls(QWidget *window, QWidget *parent) : QWidget(parent) {
        setObjectName("macshell-window-controls");
        auto *layout = new QHBoxLayout(this);
        layout->setContentsMargins(8, 0, 10, 0);
        layout->setSpacing(6);
        for (const auto &kind : {"close", "minimize", "maximize"})
            layout->addWidget(new TrafficButton(QString::fromLatin1(kind), window, this));
        setFixedSize(84, 28);
        new NativeRowDrag(this, window);
    }
};

void registerControls(QWidget *window, const QString &application) {
    auto *controls = window->findChild<QWidget *>("macshell-window-controls");
    if (!controls || !controls->isVisible() || !window->isVisible()) return;
    if (window->property("macshell-native-controls-ready").toBool()
        || qEnvironmentVariable("QT_QPA_PLATFORM") == "offscreen") return;
    window->setProperty("macshell-native-controls-ready", true);
    const QString helper = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                         + "/macshell/window-controls/window_action.py";
    QProcess::startDetached("python3", {helper, "ready", application, "--pid",
        QString::number(QCoreApplication::applicationPid()), "--title", window->windowTitle()});
}

void integrateUtility(QWidget *window) {
    const auto app = QFileInfo(QCoreApplication::applicationFilePath()).fileName();
    const QStringList utilities = {"qt6ct", "kvantummanager", "cmake-gui", "qv4l2", "qvidcap"};
    if (!utilities.contains(app) || !window->isWindow() || window->isModal()
        || window->parentWidget() || window->windowType() != Qt::Window) return;
    if (window->findChild<QWidget *>("macshell-window-controls")) {
        registerControls(window, app);
        return;
    }
    if (app == "kvantummanager") {
        auto *toolbox = window->findChild<QToolBox *>();
        auto *header = toolbox ? toolbox->findChild<QAbstractButton *>("qt_toolbox_toolboxbutton") : nullptr;
        if (!header || header->layout()) return;
        auto *layout = new QHBoxLayout(header);
        layout->setContentsMargins(0, 0, 0, 0);
        layout->setSpacing(0);
        auto *controls = new Controls(window, header);
        layout->addWidget(controls);
        layout->addStretch();
        header->setMinimumHeight(28);
        controls->show();
    } else if (app == "qt6ct") {
        auto *tabs = window->findChild<QTabWidget *>();
        if (!tabs || tabs->cornerWidget(Qt::TopLeftCorner)) return;
        auto *controls = new Controls(window, tabs);
        tabs->setCornerWidget(controls, Qt::TopLeftCorner);
        new NativeRowDrag(tabs, window);
        if (auto *bar = tabs->findChild<QTabBar *>()) new NativeRowDrag(bar, window);
        controls->show();
    } else {
        auto *menu = window->findChild<QMenuBar *>();
        if (!menu || menu->cornerWidget(Qt::TopLeftCorner)) return;
        auto *controls = new Controls(window, menu);
        menu->setCornerWidget(controls, Qt::TopLeftCorner);
        new NativeRowDrag(menu, window);
        controls->show();
    }
    registerControls(window, app);
}

// Theme managers replace their QStyle while starting. Keep their native
// tab-corner controls bound to the application rather than the old style.
class UtilityWatcher final : public QObject {
public:
    explicit UtilityWatcher(QObject *parent) : QObject(parent) {}
    bool eventFilter(QObject *object, QEvent *event) override {
        if (event->type() == QEvent::Show) {
            auto *window = qobject_cast<QWidget *>(object);
            if (window && window->isWindow()) {
                QPointer<QWidget> safe(window);
                QTimer::singleShot(0, window, [safe] { if (safe) integrateUtility(safe); });
            }
        }
        return QObject::eventFilter(object, event);
    }
};

void integrate(QToolBar *toolbar) {
    auto *window = qobject_cast<QMainWindow *>(toolbar->window());
    // Only Dolphin's primary toolbar: no dialogs, detached docks, or other apps.
    if (!window || !window->inherits("DolphinMainWindow")
        || toolbar->objectName() != "mainToolBar" || window->isModal()) return;
    auto *action = toolbar->findChild<QWidgetAction *>("macshell-controls-action", Qt::FindDirectChildrenOnly);
    if (!action) {
        action = new QWidgetAction(toolbar);
        action->setObjectName("macshell-controls-action");
        action->setDefaultWidget(new Controls(window, toolbar));
        new NativeRowDrag(toolbar, window);
    }
    const auto actions = toolbar->actions();
    if (!actions.isEmpty() && actions.first() == action) {
        registerControls(window, "dolphin");
        return;
    }
    toolbar->removeAction(action);
    toolbar->insertAction(toolbar->actions().value(0), action);
    registerControls(window, "dolphin");
    // Keep the window's existing resize frame; only Hyprbars is excluded by rule.
    // Qt's toolbar and window actions remain real native widgets.
}

class ControlsStyle final : public QProxyStyle {
public:
    ControlsStyle() : QProxyStyle(QStyleFactory::create("kvantum")) {
        setObjectName("MacShellControls");
        if (qApp && !qApp->property("macshell-utility-watcher").toBool()) {
            qApp->setProperty("macshell-utility-watcher", true);
            qApp->installEventFilter(new UtilityWatcher(qApp));
        }
    }
    void polish(QWidget *widget) override {
        QProxyStyle::polish(widget);
        if (widget->isWindow()) {
            widget->installEventFilter(this);
            QPointer<QWidget> safe(widget);
            QTimer::singleShot(0, widget, [safe] { if (safe) integrateUtility(safe); });
        }
        if (auto *toolbar = qobject_cast<QToolBar *>(widget)) {
            if (toolbar->objectName() != "mainToolBar") return;
            toolbar->installEventFilter(this);
            QPointer<QToolBar> safe(toolbar);
            QTimer::singleShot(0, toolbar, [safe] { if (safe) integrate(safe); });
        }
    }
    void unpolish(QWidget *widget) override {
        widget->removeEventFilter(this);
        QProxyStyle::unpolish(widget);
    }
    bool eventFilter(QObject *object, QEvent *event) override {
        if (event->type() == QEvent::Show) {
            auto *window = qobject_cast<QWidget *>(object);
            if (window && window->isWindow()) {
                QPointer<QWidget> safe(window);
                QTimer::singleShot(0, window, [safe] { if (safe) integrateUtility(safe); });
            }
        }
        if (event->type() == QEvent::Show || event->type() == QEvent::ActionAdded
            || event->type() == QEvent::ActionRemoved) {
            auto *toolbar = qobject_cast<QToolBar *>(object);
            if (toolbar && !toolbar->property("macshell-controls-pending").toBool()) {
                toolbar->setProperty("macshell-controls-pending", true);
                QPointer<QToolBar> safe(toolbar);
                QTimer::singleShot(0, toolbar, [safe] {
                    if (!safe) return;
                    integrate(safe);
                    safe->setProperty("macshell-controls-pending", false);
                });
            }
        }
        return QProxyStyle::eventFilter(object, event);
    }
};
}

class ControlsPlugin final : public QStylePlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QStyleFactoryInterface_iid FILE "controls.json")
public:
    QStyle *create(const QString &key) override {
        return key.compare("MacShellControls", Qt::CaseInsensitive) == 0 ? new ControlsStyle : nullptr;
    }
};

#include "controls.moc"
