#pragma once
#include <algorithm>

namespace MacShell {
struct Geometry {
    double x, y, width, height;
};
inline Geometry clampTop(Geometry geometry, double top, bool resizing, double minimumHeight = 1.0) {
    if (geometry.y >= top) return geometry;
    const double overshoot = top - geometry.y;
    geometry.y = top;
    if (resizing) geometry.height = std::max(minimumHeight, geometry.height - overshoot);
    return geometry;
}
}
