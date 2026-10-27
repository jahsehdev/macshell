'use strict';
// Standard local Tabby plugin; no application binary or renderer bundle edits.
Object.defineProperty(exports, '__esModule', {value: true});
const angular = require('@angular/core');
const core = require('tabby-core');
const {spawn} = require('child_process');
const path = require('path');
const os = require('os');
class MacShellControls {
  constructor(hostWindow) {
    // Apply independently of saved appearance.css: an already-running Tabby
    // may save its older CSS when it exits after a configuration update.
    const dragStyle = document.createElement('style');
    dragStyle.id = 'macshell-native-window-drag';
    dragStyle.textContent = require('fs').readFileSync(path.join(__dirname, 'drag.css'), 'utf8');
    (document.head || document.documentElement).appendChild(dragStyle);
    const helper = path.join(os.homedir(), '.local/share/macshell/window-controls/window_action.py');
    if (!require('fs').existsSync(helper)) return;
    function action(kind) {
      const child = spawn('python3', [helper, kind, 'tabby'], {detached: true, stdio: 'ignore'});
      child.on('error', () => {});
      child.unref();
    }
    // Keep Tabby's native close/confirmation and maximize behavior.
    hostWindow.minimize = () => action('minimize');
    let observer;
    const ready = () => {
      const controls = document.querySelector('.tab-bar > window-controls');
      if (!controls || controls.querySelectorAll('button').length !== 3 || !controls.getBoundingClientRect().height) return;
      if (observer) observer.disconnect();
      action('ready');
    };
    observer = new MutationObserver(ready);
    observer.observe(document.documentElement, {childList: true, subtree: true});
    ready();
  }
}
MacShellControls.ctorParameters = () => [{type: core.HostWindowService}];
angular.NgModule({})(MacShellControls);
exports.default = MacShellControls;
