"use strict";
// a content script's fetch carries the extension's host permission, so cross-origin sheets read
DarkReader.setFetchMethod(url => fetch(url));

// Dark Reader keeps a page's own hues, which on black are often unreadable blues, and has no say
// in what a link is. The darkreader class stops it recolouring this sheet.
function accents(s) {
  let sheet = document.getElementById("ficciones-accents");
  if (!sheet) {
    sheet = document.createElement("style");
    sheet.id = "ficciones-accents";
    sheet.className = "darkreader";
    document.documentElement.append(sheet);
  }
  sheet.textContent = `
    a:link:not([role=button]), a:link:not([role=button]) * { color: ${s.link} !important; }
    a:visited:not([role=button]), a:visited:not([role=button]) * { color: ${s.visited} !important; }
    h1, h2, h3 { color: ${s.heading} !important; }
    code, kbd, samp { color: ${s.code} !important; }
    * { scrollbar-color: ${s.body} ${s.ground} !important; }
  `;
}

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
  accents(s);
}

browser.runtime.onMessage.addListener(paint);
