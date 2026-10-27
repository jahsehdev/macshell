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
