"use strict";
const $ = id => document.getElementById(id);

async function show() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  const { theme, paused, off } = await browser.runtime.sendMessage({ ask: true });
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

  const url = new URL(tab.url);
  const host = /^https?:$/.test(url.protocol) ? url.hostname : null;
  const themed = host && theme.domains.some(d => host === d || host.endsWith(`.${d}`));
  $("all").checked = !paused;
  $("siteRow").hidden = !host || themed;
  $("host").textContent = host;
  $("site").checked = !off.includes(host);
  $("site").disabled = paused;
  $("note").hidden = !themed && !!host;
  $("note").textContent = themed ? `${host} has its own theme` : "This page can't be recoloured";

  $("all").onchange = () => send({ paused: !$("all").checked });
  $("site").onchange = () => send({ host, off: !$("site").checked });
}

const send = message => browser.runtime.sendMessage(message).then(show);

show();
