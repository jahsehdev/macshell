const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "../GlassBackdrop.js"), "utf8")
    .replace(/^\.pragma library\s*/, "");
const glass = vm.createContext({});
vm.runInContext(source, glass);

function client(address, title, monitor = 0) {
    return { address, title, monitor, mapped: true, hidden: false };
}

test("a closed Launchpad's cached IPC record cannot hide application windows", () => {
    const app = client("0x123", "Console");
    const staleLaunchpad = client("0x456", "qs-launchpad-backdrop");
    const live = [app, staleLaunchpad].filter(c => glass.hasLiveClient(c, c === app));
    assert.deepEqual(Array.from(glass.clientsForGlass(live)), [app]);
});

test("an open Launchpad still hides apps only on its own monitor", () => {
    const app = client("0x123", "Console");
    const other = client("0x789", "Browser", 1);
    const launchpad = client("0x456", "qs-launchpad-backdrop");
    const live = [app, other, launchpad].filter(c => glass.hasLiveClient(c, true));
    assert.deepEqual(Array.from(glass.clientsForGlass(live)), [other]);
});

test("pending and missing IPC records are not capture clients", () => {
    assert.equal(glass.hasLiveClient(null, true), false);
    assert.equal(glass.hasLiveClient({}, true), false);
    assert.equal(glass.hasLiveClient(client("0x123", "Console"), false), false);
    assert.equal(glass.hasLiveClient(client("0x123", "Console"), true), true);
});

test("a hidden or unmapped Launchpad does not cover app windows", () => {
    const app = client("0x123", "Console");
    for (const change of [{ hidden: true }, { mapped: false }]) {
        const launchpad = { ...client("0x456", "qs-launchpad-backdrop"), ...change };
        assert.deepEqual(Array.from(glass.clientsForGlass([app, launchpad])), [app]);
    }
});


test("minimized clients never contribute pixels, even while still mapped", () => {
    const app = client("0x123", "Console");
    const parked = { ...client("0x456", "Music"), workspace: { id: -99, name: "special:minimized" } };
    assert.deepEqual(Array.from(glass.clientsForGlass([app, parked])), [app]);
    for (const state of [{ hidden: true }, { mapped: false }, { minimized: true }]) {
        assert.deepEqual(Array.from(glass.clientsForGlass([app, { ...parked, workspace: { id: 1, name: "1" }, ...state }])), [app]);
    }
});

test("minimize records suppress stale geometry until restore without mutating it", () => {
    const app = { ...client("0x123", "Console"), pid: 42, workspace: { id: 1, name: "1" } };
    const raw = [app];
    for (const key of ["123", "0x123"]) {
        assert.deepEqual(Array.from(glass.clientsForGlass(raw, { [key]: { pid: 42 } })), []);
    }
    assert.deepEqual(Array.from(glass.clientsForGlass(raw, {})), [app]);
    assert.equal(raw[0].workspace.name, "1");
});

test("an old minimize record cannot hide a new process reusing the address", () => {
    const app = { ...client("0x123", "Console"), pid: 43 };
    assert.deepEqual(Array.from(glass.clientsForGlass([app], { "123": { pid: 42 } })), [app]);
});

test("other special workspaces remain available for monitor visibility filtering", () => {
    const app = { ...client("0x123", "Console"), workspace: { id: -98, name: "special:magic" } };
    assert.deepEqual(Array.from(glass.clientsForGlass([app])), [app]);
});

const monitor = (id, active, special = 0) => ({ id,
    activeWorkspace: { id: active }, specialWorkspace: { id: special } });
const onWorkspace = (id, name = String(id), mon = 0) => ({
    ...client("0x123", "Console", mon), workspace: { id, name }
});

test("Hide, Show Desktop and inactive stages cannot export retained app frames", () => {
    for (const name of ["special:hidden", "special:macshell-desktop", "special:macshell-stage"]) {
        const app = onWorkspace(-98, name);
        // Even a stale monitor snapshot must not re-admit a storage workspace.
        assert.deepEqual(Array.from(glass.clientsForGlass([app], {}, [monitor(0, 1, -98)])), []);
    }
});

test("workspace changes invalidate glass admission without changing client geometry", () => {
    const app = onWorkspace(1);
    assert.deepEqual(Array.from(glass.clientsForGlass([app], {}, [monitor(0, 1)])), [app]);
    assert.deepEqual(Array.from(glass.clientsForGlass([app], {}, [monitor(0, 2)])), []);
    assert.deepEqual(Array.from(glass.clientsForGlass([app], {}, [monitor(0, 1)])), [app]);
    assert.deepEqual(Array.from(glass.clientsForGlass([app], {}, [])), []);
    assert.equal(app.workspace.id, 1);
});

test("each monitor admits its own visible regular and special workspaces", () => {
    const first = onWorkspace(1), second = onWorkspace(2, "2", 1);
    const special = { ...onWorkspace(-98, "special:magic", 1), address: "0x456" };
    const monitors = [monitor(0, 1), monitor(1, 2, -98)];
    assert.deepEqual(Array.from(glass.clientsForGlass([first, second, special], {}, monitors)), [first, second, special]);
    assert.deepEqual(Array.from(glass.clientsForGlass([special], {}, [monitor(1, 2)])), []);
});
