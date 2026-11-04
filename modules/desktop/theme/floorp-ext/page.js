"use strict";
// a content script's fetch carries the extension's host permission, so cross-origin sheets read
DarkReader.setFetchMethod(url => fetch(url));

// Dark Reader can miss the rule that colours the page itself, and a white body is the worst of what
// it misses. A frame stays out of it: many are see-through on purpose.
const pageGround = s =>
  window === top
    ? `html, body {
        background-color: var(--darkreader-neutral-background, ${s.ground}) !important;
        color: var(--darkreader-neutral-text, ${s.body}) !important;
      }`
    : "";

// Dark Reader keeps a page's own hues, which on black are often unreadable blues, and has no say
// in what a link is. The darkreader class stops it recolouring the <style> these go in.
const accents = s => `
    ${pageGround(s)}
    a:link:not([role=button]), a:link:not([role=button]) * { color: ${s.link} !important; }
    a:visited:not([role=button]), a:visited:not([role=button]) * { color: ${s.visited} !important; }
    h1, h2, h3 { color: ${s.heading} !important; }
    code, kbd, samp { color: ${s.code} !important; }
    * { scrollbar-color: ${s.body} ${s.ground} !important; }
`;

function paint(s) {
  // enable over an enabled page keeps the first theme's root background
  DarkReader.disable();
  document.getElementById("ficciones-accents")?.remove();
  if (s.clear) return;
  DarkReader.enable({
    mode: s.light ? 0 : 1,
    ...s.tune,
    ...s.sites[location.hostname],
    darkSchemeBackgroundColor: s.ground,
    darkSchemeTextColor: s.body,
    lightSchemeBackgroundColor: s.ground,
    lightSchemeTextColor: s.body,
    selectionColor: s.selection,
  });
  const sheet = document.createElement("style");
  sheet.id = "ficciones-accents";
  sheet.className = "darkreader";
  sheet.textContent = accents(s);
  document.documentElement.append(sheet);
}

// Dark Reader hands its own fetch replies to every runtime.onMessage listener on the page
browser.runtime.onMessage.addListener(message => {
  if (message.ficciones) paint(message.ficciones);
});
