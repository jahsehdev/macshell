const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");
const theme = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, "../ThemeColors.js"), "utf8")
    .replace(/^\.pragma library\s*/, ""), theme);

test("Multicolor uses each app's preferred accent; a fixed accent overrides both", () => {
    assert.equal(theme.accentFor({ mode: "multicolor" }, "settings"), "#0a84ff");
    assert.equal(theme.accentFor({ mode: "multicolor" }, "clock"), "#ff9f0a");
    for (const context of ["settings", "shell", "clock", "launchpad"])
        assert.equal(theme.accentFor({ mode: "single", accent: "#ff453a" }, context), "#ff453a");
});

test("Automatic follows the app accent, including after changing the accent", () => {
    assert.equal(theme.highlightBase({ mode: "multicolor" }, "clock"), "#ff9f0a");
    assert.equal(theme.highlightBase({ mode: "single", accent: "#30d158" }, "clock"), "#30d158");
});

test("An explicit highlight remains independent of accent mode and accent color", () => {
    for (const mode of ["single", "multicolor"])
        for (const accent of ["#0a84ff", "#ff453a", "#ffd60a"])
            for (const context of ["settings", "clock"])
                assert.equal(theme.highlightBase({ mode, accent, highlight: "purple" }, context), "#bf5af2");
});

test("Custom highlights survive serialization without changing the control accent", () => {
    const saved = JSON.parse(JSON.stringify(theme.normalize({
        mode: "single", accent: "#FF453A", highlight: "custom", customHighlight: "#C5D91A"
    })));
    assert.equal(theme.highlightBase(saved, "settings"), "#c5d91a");
    assert.equal(theme.accentFor(saved, "settings"), "#ff453a");
});

test("Legacy accents are preserved; invalid settings safely use defaults", () => {
    const legacy = theme.fromLegacy({ accent: "#BF5AF2" });
    assert.equal(legacy.mode, "single");
    assert.equal(theme.accentFor(legacy, "clock"), "#bf5af2");
    for (const value of [null, undefined, {}, { mode: "rainbow", accent: "url(evil)", highlight: "missing" }]) {
        assert.equal(theme.normalize(value).mode, "multicolor");
        assert.equal(theme.normalize(value).highlight, "automatic");
    }
    assert.equal(theme.normalize({ highlight: "custom", customHighlight: "invalid" }).customHighlight, "#a8caff");
});

test("Selected text meets 4.5:1 contrast for all palettes, modes and extreme custom colors", () => {
    for (const dark of [false, true])
        for (const mode of ["single", "multicolor"])
            for (const context of ["settings", "clock"])
                for (const highlight of ["automatic", ...theme.colors.map(c => c.id), "custom"])
                    for (const customHighlight of ["#000000", "#ffffff", "#ffff00", "#1024bf"]) {
                        const config = { mode, accent: "#ffd60a", highlight, customHighlight };
                        const background = theme.selectionFor(config, context, dark);
                        const foreground = theme.selectedTextFor(config, context, dark);
                        const a = theme.luminance(background), b = theme.luminance(foreground);
                        assert.ok((Math.max(a, b) + .05) / (Math.min(a, b) + .05) >= 4.5,
                            `${highlight} / ${mode} / ${context} / dark=${dark}`);
                    }
});
