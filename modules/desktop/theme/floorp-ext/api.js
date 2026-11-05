"use strict";
/* global ExtensionAPI, ExtensionCommon, ChromeUtils, Services, Cc, Ci, Cu */
// Privileged half: owns the browser's user sheets, so a theme change repaints chrome and sites
// without a restart. The profile's chrome/*.css must not exist: the sheet service's sheets sort
// before those, so a stale file would win the cascade.
const { setInterval, clearInterval } = ChromeUtils.importESModule("resource://gre/modules/Timer.sys.mjs");
// an experiment's scope has neither of these as globals
const { IOUtils, console } = Cu.getGlobalForObject(Services);
const sss = Cc["@mozilla.org/content/style-sheet-service;1"].getService(Ci.nsIStyleSheetService);

const themeFile = name => {
  const f = Services.dirsvc.get("Home", Ci.nsIFile);
  for (const part of [".config", "ficciones", "theme", name]) f.append(part);
  return f;
};
const SHEETS = ["floorp-userChrome.css", "floorp-userContent.css"];

this.ficciones = class extends ExtensionAPI {
  sheets = [];
  timer = null;
  seen = "";
  listeners = new Set();
  state = null;

  async load() {
    const texts = await Promise.all(SHEETS.map(n => IOUtils.readUTF8(themeFile(n).path)));
    // data: because content processes can't read ~/.config or the store under their sandbox
    const next = texts.map(t => Services.io.newURI("data:text/css;charset=utf-8," + encodeURIComponent(t)));
    next.forEach(u => sss.loadAndRegisterSheet(u, sss.USER_SHEET));
    this.sheets.forEach(u => sss.unregisterSheet(u, sss.USER_SHEET));
    this.sheets = next;
    const page = JSON.parse(await IOUtils.readUTF8(themeFile("floorp-page.json").path));
    // the sites the sheet styles by hand are the ones the page recolourer must leave alone
    const domains = [...new Set([...texts[1].matchAll(/domain\("([^"]+)"\)/g)].map(m => m[1]))];
    this.state = { ...page, domains };
    this.listeners.forEach(fire => fire(this.state));
  }

  // the links' far end is the only thing that changes, and it costs two realpaths a second
  poll() {
    let now;
    try {
      now = SHEETS.map(n => {
        const f = themeFile(n);
        f.normalize();
        return f.path;
      }).join();
    } catch (e) {
      return;
    }
    if (now === this.seen) return;
    this.seen = now;
    this.load().catch(e => this.listeners.forEach(fire => fire({ failed: String(e) })));
  }

  start() {
    if (this.timer) return;
    this.poll();
    this.timer = setInterval(() => this.poll(), 1000);
  }

  onShutdown() {
    clearInterval(this.timer);
    this.sheets.forEach(u => sss.unregisterSheet(u, sss.USER_SHEET));
  }

  getAPI(context) {
    return {
      ficciones: {
        onTheme: new ExtensionCommon.EventManager({
          context,
          name: "ficciones.onTheme",
          register: fire => {
            const send = s => fire.async(s);
            this.listeners.add(send);
            if (this.state) send(this.state);
            this.start();
            return () => this.listeners.delete(send);
          },
        }).api(),
      },
    };
  }
};
