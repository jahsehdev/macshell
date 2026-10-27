// Headless Qt Quick screenshot renderer. EGL llvmpipe renders the real shaders.
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlContext>
#include <QQmlComponent>
#include <QSettings>
#include <QQuickItem>
#include <QQuickWindow>
#include <QQuickRenderControl>
#include <QQuickGraphicsDevice>
#include <QQuickRenderTarget>
#include <QOpenGLContext>
#include <QOffscreenSurface>
#include <QOpenGLFramebufferObject>
#include <QOpenGLFunctions>
#include <QTimer>
#include <QDebug>
#include <QtGui/private/qopenglcontext_p.h>
#include <qpa/qplatformopenglcontext.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

class HeadlessGL : public QPlatformOpenGLContext {
    EGLDisplay display;
    EGLContext ctx;
public:
    HeadlessGL() {
        display = eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, nullptr);
        EGLint major, minor;
        if (!eglInitialize(display, &major, &minor)) qFatal("eglInitialize failed");
        eglBindAPI(EGL_OPENGL_API);
        EGLint attributes[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
        EGLConfig config; EGLint n;
        if (!eglChooseConfig(display, attributes, &config, 1, &n) || !n) qFatal("EGL config missing");
        EGLint contextAttributes[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 3, EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, EGL_NONE};
        ctx = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttributes);
        if (ctx == EGL_NO_CONTEXT) qFatal("EGL context failed");
    }
    ~HeadlessGL() override { eglDestroyContext(display, ctx); eglTerminate(display); }
    QSurfaceFormat format() const override {
        QSurfaceFormat f; f.setRenderableType(QSurfaceFormat::OpenGL); f.setVersion(3, 3); f.setProfile(QSurfaceFormat::CoreProfile); f.setDepthBufferSize(24); f.setStencilBufferSize(8); return f;
    }
    bool makeCurrent(QPlatformSurface *) override { return eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx); }
    void doneCurrent() override { eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT); }
    void swapBuffers(QPlatformSurface *) override {}
    QFunctionPointer getProcAddress(const char *name) override { return reinterpret_cast<QFunctionPointer>(eglGetProcAddress(name)); }
};

int main(int argc, char **argv) {
    qputenv("QT_QPA_PLATFORM", "offscreen");
    qputenv("QT_QPA_OFFSCREEN_NO_GLX", "1");
    qputenv("LIBGL_ALWAYS_SOFTWARE", "1");
    qputenv("QT_FORCE_STDERR_LOGGING", "1");
    QSurfaceFormat requested; requested.setRenderableType(QSurfaceFormat::OpenGL); requested.setVersion(3, 3); requested.setProfile(QSurfaceFormat::CoreProfile); QSurfaceFormat::setDefaultFormat(requested);
    qputenv("QT_QUICK_BACKEND", "rhi");
    QGuiApplication app(argc, argv);
    if (argc < 3) qFatal("Usage: render scene.qml output.png [width height theme.conf state]");
    int w = argc > 3 ? atoi(argv[3]) : 1920, h = argc > 4 ? atoi(argv[4]) : 1080;
    QOpenGLContext context;
    QOpenGLContextPrivate::get(&context)->adopt(new HeadlessGL);
    QOffscreenSurface surface; surface.setFormat(context.format()); surface.create();
    if (!context.makeCurrent(&surface)) qFatal("makeCurrent failed");
    qInfo() << "Renderer:" << reinterpret_cast<const char *>(context.functions()->glGetString(GL_RENDERER));
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QQuickRenderControl control;
    QQuickWindow window(&control);
    window.setGraphicsDevice(QQuickGraphicsDevice::fromOpenGLContext(&context));
    window.setGeometry(0, 0, w, h);
    window.contentItem()->setSize(QSizeF(w,h));
    if (!control.initialize()) qFatal("RenderControl initialization failed");
    QOpenGLFramebufferObjectFormat f; f.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
    QOpenGLFramebufferObject fbo(w, h, f);
    window.setRenderTarget(QQuickRenderTarget::fromOpenGLTexture(fbo.texture(), QSize(w,h)));
    QQmlEngine engine;
    QSettings settings(argc > 5 ? QString::fromLocal8Bit(argv[5]) : QStringLiteral("@DATA_HOME@/sddm/themes/macshell/theme.conf"), QSettings::IniFormat);
    // QSettings maps the INI [General] section to the root group.
    QVariantMap themeConfig;
    for (const auto &key : settings.childKeys()) themeConfig.insert(key, settings.value(key).toString());
    engine.rootContext()->setContextProperty("config", themeConfig);
    engine.rootContext()->setContextProperty("previewState", argc > 6 ? QString::fromLocal8Bit(argv[6]) : QStringLiteral("idle"));
    QQmlComponent component(&engine, QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    QObject *obj = component.create();
    if (!obj) { qCritical() << component.errors(); return 1; }
    QQuickItem *root = qobject_cast<QQuickItem *>(obj);
    if (!root) qFatal("Root is not an Item");
    root->setParentItem(window.contentItem()); root->setSize(QSizeF(w,h));
    QTimer timer; int frames = 0;
    QObject::connect(&timer, &QTimer::timeout, [&] {
        context.makeCurrent(&surface);
        control.polishItems(); control.beginFrame(); control.sync(); control.render(); control.endFrame();
        context.functions()->glFinish();
        if (++frames == 100) {
            if (!root->property("validationPassed").toBool()) {
                qCritical() << "Preview interaction validation failed";
                app.exit(2); return;
            }
            bool ok = fbo.toImage().save(QString::fromLocal8Bit(argv[2]));
            qInfo() << "Screenshot:" << argv[2] << ok;
            app.exit(ok ? 0 : 1);
        }
    });
    timer.start(30);
    int result = app.exec();
    delete root;
    control.invalidate();
    return result;
}
