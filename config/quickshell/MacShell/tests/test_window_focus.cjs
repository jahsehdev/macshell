const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../MacDock.qml'), 'utf8');
const start = source.indexOf('function focusWindow(');
const open = source.indexOf('{', start);
let depth = 1, end = open + 1;
while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
}
const focusSource = source.slice(start, end);
function setup({minimized = false, controller = true, stage = false, revealed = []} = {}) {
    const calls = [];
    const root = {
        hub: controller ? {desktopController: {revealed, activate: addr => calls.push(['controller', addr])}} : null,
        minimize: {isMinimized: () => minimized, restore: addr => calls.push(['restore', addr])}
    };
    const context = vm.createContext({root, desktopPrefs: {stageManager: stage}, winAddr: tl => tl.addr});
    vm.runInContext(focusSource, context);
    return {calls, focus: context.focusWindow, window: {addr: 'abc', activate: () => calls.push(['direct', 'abc'])}};
}
test('Dock activation has one owner, avoiding a late duplicate focus', () => {
    const s = setup(); s.focus(s.window);
    assert.deepEqual(s.calls, [['direct', 'abc']]);
});
test('Stage Manager restores the selected group before focusing once', () => {
    const s = setup({stage: true}); s.focus(s.window);
    assert.deepEqual(s.calls, [['controller', 'abc']]);
});
test('Show Desktop restores the parked window before focusing once', () => {
    const s = setup({revealed: ['0']}); s.focus(s.window);
    assert.deepEqual(s.calls, [['controller', 'abc']]);
});
test('minimized windows restore without competing activation', () => {
    const s = setup({minimized: true}); s.focus(s.window);
    assert.deepEqual(s.calls, [['restore', 'abc']]);
});
test('standalone Dock still activates the selected window', () => {
    const s = setup({controller: false}); s.focus(s.window);
    assert.deepEqual(s.calls, [['direct', 'abc']]);
});
test('missing window does not issue an activation', () => {
    const s = setup(); s.focus(null);
    assert.deepEqual(s.calls, []);
});
