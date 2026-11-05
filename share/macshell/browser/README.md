# MacShell Browser Tools

A Firefox WebExtension for tab topics, Notify Me page watches, and structured page customizations. It never calls cloud AI. Topic assignment uses explicit local rules until a local Luma model and browser bridge are available.

For a development session, open `about:debugging#/runtime/this-firefox`, choose **Load Temporary Add-on**, and select `manifest.json` in this directory. Temporary installation ends when Firefox closes. Persistent distribution requires Firefox signing or a supported managed deployment; this repository does not silently modify the user's Firefox profile.

- **Group tabs** uses native tab groups where supported and presents topic lists otherwise. Undo attempts to restore the previous groups and order; closed groups/tabs cannot always be restored.
- **Notify Me** requests access to each chosen site, stores a baseline, and checks at a minimum interval of five minutes while Firefox runs. CSS selectors can isolate a price or stock status. A contains condition filters alerts. Watches persist, rebuild alarms after startup, and support pause/remove. Login-only, redirecting, and JavaScript-rendered pages are not fully supported.
- **Describe a page customization** supports fixed reading-layout, larger-text, focus, and reset templates. Try applies to the active tab. Save persists the selected action for a site after permission is granted. No arbitrary generated scripts are executed.

Primary API references: [tab grouping](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/tabs/group), [scheduled alarms](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/alarms).

Source and syntax checks are complete; real Firefox interaction and persistent installation still need verification in an accessible desktop session.
