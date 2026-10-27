'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const styles = [], actions = [];
const document = {
  createElement: () => ({}),
  head: {appendChild: style => styles.push(style)},
  documentElement: {},
  querySelector: () => ({querySelectorAll: () => [1, 2, 3], getBoundingClientRect: () => ({height: 28})}),
};
const context = {exports: {}, __dirname, document,
  MutationObserver: class {observe() {} disconnect() {}},
  require(name) {
    if (name === '@angular/core') return {NgModule: () => value => value};
    if (name === 'tabby-core') return {HostWindowService: class {}};
    if (name === 'child_process') return {spawn: (_cmd, args) => {
      actions.push(args[1]); return {on() {}, unref() {}};
    }};
    if (name === 'fs') return {existsSync: () => true, readFileSync: fs.readFileSync};
    return require(name);
  },
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'plugin.js'), 'utf8'), context);
let close = 0, maximize = 0;
const host = {close() {++close;}, maximize() {++maximize;}};
new context.exports.default(host);
assert.equal(styles.length, 1);
assert.equal(styles[0].id, 'macshell-native-window-drag');
assert.equal(styles[0].textContent, fs.readFileSync(path.join(__dirname, 'drag.css'), 'utf8'));
host.minimize(); host.close(); host.maximize();
assert.deepEqual(actions, ['ready', 'minimize']);
assert.equal(close, 1); assert.equal(maximize, 1);
console.log('Tabby: startup drag CSS, readiness, minimize, native close and maximize passed.');
