#include "shake.hpp"
#include <cassert>
#include <iostream>
#include <limits>
#include <numbers>

using namespace MacShell::Shake;

static bool oscillate(Detector& detector, bool vertical = false, double step = .008, double amplitude = 45, double frequency = 9) {
    bool detected = false;
    for (double t = 0; t < .8; t += step) {
        const double offset = amplitude * std::sin(2 * std::numbers::pi * frequency * t);
        detected |= detector.move(t, vertical ? Point{200, 200 + offset} : Point{200 + offset, 200});
    }
    return detected;
}

int main() {
    Detector d;
    assert(oscillate(d));
    d.reset(); assert(oscillate(d, true));
    d.reset(); assert(oscillate(d, false, .001)); // high polling rate
    d.reset(); assert(oscillate(d, false, 1.0 / 60)); // trackpad / lower rate
    d.reset(); assert(!oscillate(d, false, .008, 2)); // sensor jitter
    d.reset(); assert(!oscillate(d, false, .008, 45, .8)); // slow wiggle
    d.reset();
    for (int i = 0; i < 120; ++i) assert(!d.move(i * .008, {i * 20.0, i * 4.0})); // fast traversal
    d.reset();
    for (int i = 0; i < 120; ++i) assert(!d.move(i * .008, {i % 2 ? 1000.0 : 0, 0})); // repeated warps
    d.reset();
    for (int i = 0; i < 100; ++i) {
        const double x = i < 50 ? i * 5.0 : (100 - i) * 5.0;
        assert(!d.move(i * .004, {x, 0})); // single correction / U-turn
    }
    d.reset();
    assert(oscillate(d));
    assert(!d.move(2, {200, 200})); // old samples expire across idle
    d.reset();
    for (int i = 0; i < 30; ++i) assert(!d.move(i * .2, {i % 2 ? 80.0 : 0, 0}));
    d.move(1, {0, 0});
    assert(!d.move(.5, {80, 0})); // monotonic clock reset
    assert(!d.move(3, {std::numeric_limits<double>::quiet_NaN(), 0}));

    double scale = 1;
    for (int i = 0; i < 30; ++i) {
        const double next = animate(scale, .016, true);
        assert(next >= scale && next <= 4);
        scale = next;
    }
    assert(scale > 3.9);
    for (int i = 0; i < 60; ++i) {
        const double next = animate(scale, .016, false);
        assert(next <= scale && next >= 1);
        scale = next;
    }
    assert(scale == 1); // timer can disarm completely
    assert(animate(1, .5, true, 100) <= 8);
    double coarse = 1, fine = 1;
    for (int i = 0; i < 15; ++i) coarse = animate(coarse, .016, true);
    for (int i = 0; i < 120; ++i) fine = animate(fine, .002, true);
    assert(std::abs(coarse - fine) < .001); // frame-rate independent easing

    const auto box = geometry({400, 300}, {3, 5}, {24, 32}, 4);
    assert(box.position.x == 388 && box.position.y == 280);
    assert(box.size.x == 96 && box.size.y == 128);
    assert(box.position.x + 3 * 4 == 400 && box.position.y + 5 * 4 == 300); // click anchor stays fixed
    const auto fractional = geometry({0, 0}, {2.5, 4.5}, {24, 24}, 1.5);
    assert(fractional.position.x == -3.75 && fractional.size.x == 36);
    std::cout << "Shake detector, animation and cursor geometry checks passed.\n";
}
