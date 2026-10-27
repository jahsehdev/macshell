// Run with QT_QPA_PLATFORM=offscreen. The compositor move itself needs a session.
#include "../qt/controls.cpp"
#include <QTest>
#include <QToolButton>
#include <cstdio>

static void check(bool condition, const char *message) {
    if (!condition) qFatal("%s", message);
}

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    QMainWindow window;
    auto *toolbar = window.addToolBar("Navigation");
    auto *action = toolbar->addAction("Open");
    int clicks = 0;
    QObject::connect(action, &QAction::triggered, [&] { ++clicks; });
    new NativeRowDrag(toolbar, &window);
    auto *controls = new Controls(&window, toolbar);
    toolbar->addWidget(controls);
    window.resize(800, 400);
    window.show();
    QCoreApplication::processEvents();

    auto *button = toolbar->widgetForAction(action);
    QTest::mouseClick(button, Qt::LeftButton);
    check(clicks == 1, "Toolbar actions must still receive clicks");
    QTest::mouseDClick(button, Qt::LeftButton);
    check(!window.isMaximized(), "Action double-click must not become a window gesture");
    const QPoint blank(toolbar->width() - 20, toolbar->height() / 2);
    check(!toolbar->childAt(blank) && !toolbar->actionAt(blank), "Expected blank toolbar area");
    QTest::mouseDClick(toolbar, Qt::LeftButton, Qt::NoModifier, blank);
    QTest::qWait(80);
    QFile gestureLog(qEnvironmentVariable("MACSHELL_GESTURE_LOG"));
    check(gestureLog.open(QIODevice::ReadOnly), "Blank toolbar must invoke the shared preference helper");
    check(gestureLog.readAll().contains("titlebar_action.py"), "Double-click must use the configured action");
    gestureLog.close();
    window.showNormal();
    QTest::mouseDClick(controls, Qt::LeftButton, Qt::NoModifier, QPoint(3, 14));
    QTest::qWait(80);
    check(gestureLog.open(QIODevice::ReadOnly), "Control margins must invoke the shared helper");
    check(gestureLog.readAll().count("titlebar_action.py") == 2, "Exactly two blank-row gestures must be handled");
    gestureLog.close();
    window.showNormal();
    QTest::mouseClick(controls->findChild<QAbstractButton *>("macshell-maximize"), Qt::LeftButton);
    check(window.isMaximized(), "The maximize button must still work");
    window.showNormal();

    auto *tabs = new QTabWidget;
    tabs->addTab(new QWidget, "First");
    tabs->addTab(new QWidget, "Second");
    window.setCentralWidget(tabs);
    auto *bar = tabs->findChild<QTabBar *>();
    new NativeRowDrag(tabs, &window);
    new NativeRowDrag(bar, &window);
    QCoreApplication::processEvents();
    QTest::mouseClick(bar, Qt::LeftButton, Qt::NoModifier, bar->tabRect(1).center());
    check(tabs->currentIndex() == 1, "Tab selection must still work");
    QTest::mouseDClick(bar, Qt::LeftButton, Qt::NoModifier, bar->tabRect(1).center());
    check(!window.isMaximized(), "Tab double-click must not maximize the window");
    QTest::mouseDClick(tabs->currentWidget(), Qt::LeftButton);
    check(!window.isMaximized(), "Content area must not initiate window gestures");
    std::puts("Qt drag regions: blank rows, control margins, buttons and tab/content exclusion passed.");
}
