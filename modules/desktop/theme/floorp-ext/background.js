"use strict";
let registered = null;
const FILES = ["darkreader.js", "page.js"];

const themedBySheet = (url, domains) => {
  try {
    const host = new URL(url).hostname;
    return domains.some(d => host === d || host.endsWith(`.${d}`));
  } catch {
    return true;
  }
};

// a tab that loaded before this page started has no content script to answer: restored tabs do
async function repaint(tab, state) {
  try {
    await browser.tabs.sendMessage(tab.id, state);
  } catch {
    if (themedBySheet(tab.url, state.domains)) return;
    const inject = opts => browser.tabs.executeScript(tab.id, { allFrames: true, ...opts });
    try {
      for (const file of FILES) await inject({ file });
      await inject({ code: `paint(${JSON.stringify(state)})` });
    } catch {
      // about: pages and the like refuse scripts
    }
  }
}

browser.ficciones.onTheme.addListener(async state => {
  const old = registered;
  // the palette goes in as code, not a message: a message would arrive after first paint
  registered = await browser.contentScripts.register({
    matches: ["<all_urls>"],
    excludeMatches: state.domains.map(d => `*://*.${d}/*`),
    allFrames: true,
    runAt: "document_start",
    js: [...FILES.map(file => ({ file })), { code: `paint(${JSON.stringify(state)})` }],
  });
  if (old) await old.unregister();
  for (const tab of await browser.tabs.query({})) repaint(tab, state);
});
