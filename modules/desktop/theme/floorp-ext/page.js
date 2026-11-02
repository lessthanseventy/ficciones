"use strict";
// a content script's fetch carries the extension's host permission, so cross-origin sheets read
DarkReader.setFetchMethod(url => fetch(url));

function paint(s) {
  // enable over an enabled page keeps the first theme's root background
  DarkReader.disable();
  DarkReader.enable({
    mode: s.light ? 0 : 1,
    brightness: 100,
    contrast: 100,
    sepia: 0,
    darkSchemeBackgroundColor: s.ground,
    darkSchemeTextColor: s.body,
    lightSchemeBackgroundColor: s.ground,
    lightSchemeTextColor: s.body,
    selectionColor: s.selection,
  });
}

browser.runtime.onMessage.addListener(paint);
