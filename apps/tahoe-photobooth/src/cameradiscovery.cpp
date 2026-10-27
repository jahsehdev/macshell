#include "cameradiscovery.h"
#include <QtGlobal>
#ifdef Q_OS_LINUX
#include <QtMultimedia/private/qplatformmediaintegration_p.h>
#include <QtMultimedia/private/qplatformvideodevices_p.h>
#include <QMetaMethod>
#endif

bool CameraDiscovery::refreshVideoInputs() {
#ifdef Q_OS_LINUX
    // Qt's V4L2 backend watches /dev directory changes. With exclusive_caps,
    // v4l2loopback switches OUTPUT -> CAPTURE on the existing node when DroidCam
    // connects, so the cached camera list otherwise stays empty. Keep this
    // version-matched private Qt adapter here; the public API has no refresh.
    auto *devices=QPlatformMediaIntegration::instance()->videoDevices();
    if(!devices) return false;
    const int method=devices->metaObject()->indexOfMethod("checkCameras()");
    if(method<0) return false; // Other backends use their own discovery mechanism.
    return devices->metaObject()->method(method).invoke(devices,Qt::DirectConnection);
#else
    return false;
#endif
}
