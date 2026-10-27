const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const common = path.join(__dirname, "..");
const source = fs.readFileSync(path.join(common, "GlassMaterial.js"), "utf8")
    .replace(/^\.pragma library\s*/, "");
const material = vm.createContext({});
vm.runInContext(source, material);

test("Tinted always uses the former maximum blur, regardless of Clear's setting", () => {
    for (const value of [0, 5, 42, 80, undefined, NaN])
        assert.equal(material.blurRadius("tinted", value), 80);
});

test("Clear preserves existing valid blur settings", () => {
    for (const value of [0, 5, 15, 42, 80])
        assert.equal(material.blurRadius("clear", value), value);
});

test("unknown material modes fall back to Clear", () => {
    for (const value of [undefined, null, "", "dark", "invalid"])
        assert.equal(material.normalize(value), "clear");
    assert.equal(material.blurRadius("invalid", 5), 5);
});

test("invalid legacy values are bounded or use a light blur", () => {
    assert.equal(material.blurRadius("clear", -1), 0);
    assert.equal(material.blurRadius("clear", 1000), 80);
    assert.equal(material.blurRadius("clear", undefined), 5);
    assert.equal(material.blurRadius("clear", "invalid"), 5);
});

test("Appearance exposes material choices instead of a Blur slider", () => {
    const dock = fs.readFileSync(path.join(common, "../MacShell/MacDock.qml"), "utf8");
    assert.equal((dock.match(/GlassMaterialTile\s*\{/g) || []).length, 2);
    assert.doesNotMatch(dock, /title:\s*"Blur"/);
    assert.doesNotMatch(dock, /onMoved:.*setLook\("glassBlur"/);
});

test("Tinted never introduces an extra darkening uniform in the glass shaders", () => {
    for (const file of ["liquidglass.frag", "UpstreamBar/liquidglass.frag", "dockmenu.frag", "docktooltip.frag"]) {
        const shader = fs.readFileSync(path.join(common, "../MacShell", file), "utf8");
        assert.doesNotMatch(shader, /materialTint|liquidGlassMaterial/);
    }
});
