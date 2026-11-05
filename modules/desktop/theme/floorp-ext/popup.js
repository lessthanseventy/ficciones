"use strict";
const $ = id => document.getElementById(id);
const DIALS = [
  ["brightness", "Brightness", 50, 150, 5],
  ["contrast", "Contrast", 50, 150, 5],
  ["sepia", "Sepia", 0, 100, 5],
  ["grayscale", "Grayscale", 0, 100, 5],
  ["textStroke", "Text weight", 0, 1, 0.1],
];

for (const [key, label, min, max, step] of DIALS) {
  const row = document.createElement("label");
  const name = document.createElement("span");
  name.textContent = label;
  const dial = Object.assign(document.createElement("input"), { type: "range", id: key, min, max, step });
  const value = document.createElement("output");
  value.id = `${key}-value`;
  dial.oninput = () => (value.textContent = dial.value);
  row.append(name, dial, value);
  $("dials").append(row);
}

// a page the extension has no host permission for, another extension's say, hands over no url
function hostOf(url) {
  try {
    const { protocol, hostname } = new URL(url);
    return /^https?:$/.test(protocol) ? hostname : null;
  } catch {
    return null;
  }
}

async function show() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  const { theme, paused, off, tune, sites } = await browser.runtime.sendMessage({ ask: true });
  for (const role of ["ground", "body", "link", "heading", "code"]) {
    document.body.style.setProperty(`--${role}`, theme[role]);
  }
  $("swatches").replaceChildren(
    ...["ground", "body", "link", "visited", "heading", "code", "selection"].map(role => {
      const swatch = document.createElement("span");
      swatch.style.background = theme[role];
      return swatch;
    }),
  );

  const host = hostOf(tab.url);
  const themed = host && theme.domains.some(d => host === d || host.endsWith(`.${d}`));
  // background.js's NEVER
  const dev = ["localhost", "127.0.0.1"].includes(host);
  $("all").checked = !paused;
  $("siteRow").hidden = !host || themed || dev;
  $("host").textContent = host;
  $("site").checked = !off.includes(host);
  $("site").disabled = paused;
  $("note").hidden = !themed && !dev && !!host;
  $("note").textContent = themed
    ? `${host} has its own theme`
    : dev
      ? `${host} is a dev server: never recoloured`
      : "This page can't be recoloured";

  const scope = sites[host] ? { host } : {};
  const values = { ...tune, ...sites[host] };
  for (const [key] of DIALS) {
    $(key).value = values[key];
    $(`${key}-value`).textContent = values[key];
    $(key).disabled = paused;
    $(key).onchange = () => send({ ...scope, tune: { [key]: Number($(key).value) } });
  }
  $("justRow").hidden = !host || themed;
  $("just").checked = !!sites[host];
  $("just").disabled = paused;

  $("offSection").hidden = !off.length;
  $("offList").replaceChildren(
    ...off.map(site => {
      const row = document.createElement("li");
      const button = Object.assign(document.createElement("button"), { textContent: "Turn on" });
      button.dataset.host = site;
      button.onclick = () => send({ host: site, off: false });
      row.append(site, button);
      return row;
    }),
  );
  $("themedList").replaceChildren(
    ...theme.domains.map(site => Object.assign(document.createElement("li"), { textContent: site })),
  );

  $("all").onchange = () => send({ paused: !$("all").checked });
  $("site").onchange = () => send({ host, off: !$("site").checked });
  $("just").onchange = () => send($("just").checked ? { host, tune: {} } : { host, reset: true });
  $("reset").onclick = () => send({ ...scope, reset: true });
}

const send = message => browser.runtime.sendMessage(message).then(show);

show();
