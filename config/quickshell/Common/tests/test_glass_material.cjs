const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "../GlassMaterial.js"), "utf8")
    .replace(/^\.pragma library\s*/, "");
const material = vm.createContext({});
vm.runInContext(source, material);

test("mode-only installations migrate to the correct slider endpoint", () => {
    assert.equal(material.fromSaved({ mode: "clear" }), 0);
    assert.equal(material.fromSaved({ mode: "tinted" }), 1);
    assert.equal(material.fromSaved({}), 0);
    assert.equal(material.fromSaved({ mode: "unknown" }), 0);
});

test("a saved fractional intensity takes precedence over the compatibility mode", () => {
    for (const intensity of [0, 0.17, 0.5, 0.83, 1]) {
        assert.equal(material.fromSaved({ mode: "clear", intensity }), intensity);
        assert.equal(material.fromSaved({ mode: "tinted", intensity }), intensity);
    }
});

test("corrupt settings are bounded or fall back to the legacy mode", () => {
    assert.equal(material.fromSaved({ intensity: -12 }), 0);
    assert.equal(material.fromSaved({ intensity: 12 }), 1);
    for (const intensity of [undefined, null, NaN, Infinity, "0.5", {}]) {
        assert.equal(material.fromSaved({ mode: "clear", intensity }), 0);
        assert.equal(material.fromSaved({ mode: "tinted", intensity }), 1);
    }
});

test("blur continuously increases from existing tuning to maximum", () => {
    for (const base of [0, 5, 20, 80]) {
        assert.equal(material.blurAt(0, base), base);
        assert.equal(material.blurAt(1, base), 80);
        assert.equal(material.blurAt(0.5, base), (base + 80) / 2);
        let previous = base;
        for (let step = 0; step <= 100; step++) {
            const blur = material.blurAt(step / 100, base);
            assert.ok(blur >= previous && blur <= 80);
            previous = blur;
        }
    }
    assert.equal(material.blurAt(0, undefined), 5);
    assert.equal(material.blurAt(0, -1), 0);
    assert.equal(material.blurAt(0, 1000), 80);
});

test("tint preserves Clear tuning and never weakens a denser custom material", () => {
    for (const base of [0, 0.42, 0.85, 0.97]) {
        assert.equal(material.opacityAt(0, base), base);
        assert.ok(Math.abs(material.opacityAt(1, base) - Math.max(base, 0.92)) < 1e-12);
        let previous = base;
        for (let step = 0; step <= 100; step++) {
            const opacity = material.opacityAt(step / 100, base);
            assert.ok(opacity >= previous && opacity <= 1);
            previous = opacity;
        }
    }
});
