#pragma once

#include <algorithm>
#include <cmath>
#include <deque>

namespace MacShell::Shake {
struct Point { double x, y; };
struct Sample { double time; Point point; };

// Logical pixels and monotonic seconds, independent of compositor APIs.
class Detector {
  public:
    void reset() { samples.clear(); }

    bool move(double now, Point point) {
        if (!std::isfinite(point.x) || !std::isfinite(point.y) || !std::isfinite(now)) {
            reset();
            return false;
        }
        if (!samples.empty()) {
            const auto& previous = samples.back();
            if (now < previous.time || now - previous.time > window
                || std::hypot(point.x - previous.point.x, point.y - previous.point.y) > 400)
                reset(); // idle gaps and pointer warps are not shakes
        }
        samples.push_back({now, point});
        while (!samples.empty() && (now - samples.front().time > window || samples.size() > 1024))
            samples.pop_front();
        if (samples.size() < 4 || now - samples.front().time < 0.12)
            return false;

        double left = point.x, right = point.x, top = point.y, bottom = point.y, path = 0;
        for (size_t i = 0; i < samples.size(); ++i) {
            const auto p = samples[i].point;
            left = std::min(left, p.x); right = std::max(right, p.x);
            top = std::min(top, p.y); bottom = std::max(bottom, p.y);
            if (i) path += std::hypot(p.x - samples[i - 1].point.x, p.y - samples[i - 1].point.y);
        }
        const double diagonal = std::hypot(right - left, bottom - top);
        if (diagonal < 24 || path < 160 || path < diagonal * 3.5)
            return false;

        // Hysteresis: count complete strokes, not tiny per-event sign changes.
        const bool horizontal = right - left >= bottom - top;
        auto coordinate = [horizontal](Point p) { return horizontal ? p.x : p.y; };
        double extreme = coordinate(samples.front().point), lastReversal = -1;
        int direction = 0, reversals = 0;
        for (const auto& sample : samples) {
            const double value = coordinate(sample.point);
            if (direction == 0) {
                if (std::abs(value - extreme) >= 12) {
                    direction = value > extreme ? 1 : -1;
                    extreme = value;
                }
            } else if ((value - extreme) * direction >= 0) {
                extreme = value;
            } else if ((extreme - value) * direction >= 12) {
                direction = -direction;
                extreme = value;
                lastReversal = sample.time;
                ++reversals;
            }
        }
        return reversals >= 3 && now - lastReversal <= 0.10;
    }

  private:
    static constexpr double window = 0.45;
    std::deque<Sample> samples;
};

inline double animate(double current, double elapsed, bool shaking, double maximum = 4.0) {
    const double target = shaking ? std::clamp(maximum, 1.0, 8.0) : 1.0;
    const double result = target + (current - target) * std::exp(-std::max(0.0, elapsed) / (shaking ? 0.055 : 0.085));
    return std::abs(result - target) < 0.005 ? target : result;
}

struct Geometry { Point position, size; };
inline Geometry geometry(Point pointer, Point hotspot, Point logicalSize, double scale) {
    return {{pointer.x - hotspot.x * scale, pointer.y - hotspot.y * scale},
            {logicalSize.x * scale, logicalSize.y * scale}};
}
}
