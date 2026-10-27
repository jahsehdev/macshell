const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");
const icons = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, "../IconStyle.js"), "utf8")
  .replace(/^\.pragma library\s*/, ""), icons);

test("Dark Auto follows appearance; Always remains dark", () => {
  for (const system of [false, true]) {
    assert.equal(icons.resolvedDark({style: "dark", darkAppearance: "auto"}, system), system);
    assert.equal(icons.effectiveStyle({style: "dark", darkAppearance: "auto"}, system), system ? "dark" : "default");
    assert.equal(icons.resolvedDark({style: "dark", darkAppearance: "always"}, system), true);
  }
});
test("Clear Light/Dark/Auto resolve independently of system appearance", () => {
  for (const system of [false, true]) {
    assert.equal(icons.resolvedDark({style: "clear", clearAppearance: "light"}, system), false);
    assert.equal(icons.resolvedDark({style: "clear", clearAppearance: "dark"}, system), true);
    assert.equal(icons.resolvedDark({style: "clear", clearAppearance: "auto"}, system), system);
  }
});
test("All widget types resolve globally; photos never acquire an effect", () => {
  for (const style of ["default", "dark", "clear", "tinted"])
    for (const system of [false, true]) {
      const config = {style};
      assert.equal(icons.widgetStyle(config, "image", system), "normal");
      for (const type of ["weather", "calendar", "clock", "player"]) {
        const result = icons.widgetStyle(config, type, system);
        if (style === "clear") assert.equal(result, "liquid");
        if (style === "tinted") assert.equal(result, "tinted");
        if (style === "default") assert.ok(["normal", "light"].includes(result));
      }
    }
});
test("Tinted uses one color; independent folder preference survives leaving Tinted", () => {
  const config = {style: "tinted", folderColor: "#ff453a", tintColor: "#30d158"};
  assert.equal(icons.folder(config, "#bf5af2"), "#30d158");
  assert.equal(icons.tint(config, "#bf5af2"), "#30d158");
  const restored = icons.normalize({...config, style: "clear"});
  assert.equal(icons.folder(restored, "#bf5af2"), "#ff453a");
  assert.equal(icons.folder({style: "default"}, "#bf5af2"), "#0a84ff");
  assert.equal(icons.tint({style: "tinted"}, "#bf5af2"), "#bf5af2");
});
test("Persistence retains submodes; invalid colors and modes use safe defaults", () => {
  const config = {style: "clear", clearAppearance: "dark", folderColor: "#AA0011", tintColor: "#33BB44"};
  const reloaded = icons.normalize(JSON.parse(JSON.stringify(icons.normalize(config))));
  assert.equal(reloaded.clearAppearance, "dark");
  assert.equal(reloaded.folderColor, "#aa0011");
  for (const value of [undefined, null, [], {style: "invalid", folderColor: "../../evil", tintColor: "url(evil)"}]) {
    assert.equal(icons.normalize(value).style, "default");
    assert.equal(icons.normalize(value).folderColor, "automatic");
  }
});
test("Tinted text stays readable even for very dark custom colors", () => {
  for (const color of ["#000000", "#ff0000", "#000080", "#001000", "#ffffff", "#bf5af2"]) {
    const fg = icons.foreground(color);
    const rgb = [1,3,5].map(i => parseInt(fg.slice(i,i+2),16) / 255)
      .map(v => v <= 0.04045 ? v / 12.92 : Math.pow((v+.055)/1.055,2.4));
    const luminance = rgb[0]*.2126 + rgb[1]*.7152 + rgb[2]*.0722;
    assert.ok(luminance >= .40, `${color} -> ${fg}`);
  }
});
