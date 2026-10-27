#pragma once

namespace CameraDiscovery {
// Refresh capabilities on already-created virtual cameras (no /dev hotplug event).
bool refreshVideoInputs();
}
