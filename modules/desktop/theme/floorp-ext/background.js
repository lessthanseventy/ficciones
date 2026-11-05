"use strict";
let registered = null;
let theme = null;
const NEUTRAL = { brightness: 100, contrast: 100, sepia: 0, grayscale: 0, textStroke: 0 };
let settings = { paused: false, off: [], tune: NEUTRAL, sites: {} };
let applying = browser.storage.local.get(settings).then(stored => (settings = stored));
const FILES = ["darkreader.js", "page.js"];

const hostOf = url => {
  try {
    return new URL(url).hostname;
  } catch {
    return null;
  }
};

const themedBySheet = (url, domains) => {
  const host = hostOf(url);
  return !host || domains.some(d => host === d || host.endsWith(`.${d}`));
};

const switchedOff = url => settings.paused || settings.off.includes(hostOf(url));

// a tab that loaded before this page started has no content script to answer: restored tabs do
async function repaint(tab, state) {
  const off = switchedOff(tab.url);
  try {
    await browser.tabs.sendMessage(tab.id, { ficciones: off ? { clear: true } : state });
  } catch {
    if (off || themedBySheet(tab.url, state.domains)) return;
    const inject = opts => browser.tabs.executeScript(tab.id, { allFrames: true, ...opts });
    try {
      for (const file of FILES) await inject({ file });
      await inject({ code: `paint(${JSON.stringify(state)})` });
    } catch {
      // about: pages and the like refuse scripts
    }
  }
}

function setIcon(state) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" opacity="${settings.paused ? 0.5 : 1}"><path fill="none" stroke="${state.link}" stroke-width="1.5" d="M8 3.5C6.5 2.5 4 2.5 1.5 3v10c2.5-.5 5-.5 6.5.5 1.5-1 4-1 6.5-.5V3C12 2.5 9.5 2.5 8 3.5zm0 0v10"/></svg>`;
  browser.browserAction.setIcon({ path: `data:image/svg+xml,${encodeURIComponent(svg)}` });
}

async function apply() {
  const state = { ...theme, tune: settings.tune, sites: settings.sites };
  const old = registered;
  const excludeMatches = [
    ...state.domains.map(d => `*://*.${d}/*`),
    ...settings.off.map(host => `*://${host}/*`),
  ];
  // the palette goes in as code, not a message: a message would arrive after first paint
  registered = settings.paused
    ? null
    : await browser.contentScripts.register({
        matches: ["<all_urls>"],
        // the schema refuses an empty list
        excludeMatches: excludeMatches.length ? excludeMatches : undefined,
        allFrames: true,
        runAt: "document_start",
        js: [...FILES.map(file => ({ file })), { code: `paint(${JSON.stringify(state)})` }],
      });
  if (old) await old.unregister();
  setIcon(state);
  for (const tab of await browser.tabs.query({})) repaint(tab, state);
}

// one at a time: two overlapping applies would both unregister the same scripts. A rejected link
// would skip every apply after it, so a failure stops here and the old scripts stay registered.
const reapply = () => (applying = applying.then(apply).catch(console.error));

browser.ficciones.onTheme.addListener(state => {
  theme = state;
  reapply();
});

browser.runtime.onMessage.addListener(message => {
  if (message.ask) return Promise.resolve({ theme, ...settings });
  const { host, tune, reset } = message;
  if ("paused" in message) settings.paused = message.paused;
  if ("off" in message) {
    settings.off = settings.off.filter(site => site !== host);
    if (message.off) settings.off.push(host);
  }
  if (tune && host) settings.sites[host] = { ...settings.sites[host], ...tune };
  else if (tune) settings.tune = { ...settings.tune, ...tune };
  if (reset && host) delete settings.sites[host];
  else if (reset) settings.tune = NEUTRAL;
  return browser.storage.local.set(settings).then(reapply);
});
