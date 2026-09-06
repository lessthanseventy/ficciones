# The sites Andrew lives in, themed from the palette: userContent.css @-moz-document blocks
# appended after the vendored RetroTerminal body. Each entry = the domains and the CSS variables
# (or selectors) that site exposes for its own theme; the values come from palette.nix so the
# paper variant restyles them too. Add a site = add an entry; keep to variables where a site
# has them — selector rules rot with every redesign.
{ hex, h, fontStack }:
let
  block = domains: css: ''
    @-moz-document ${builtins.concatStringsSep ", " (map (d: "domain(\"${d}\")") domains)} {
    ${css}
    }
  '';
in
builtins.concatStringsSep "\n" [
  # GitHub — primer's design tokens
  (block [ "github.com" ] ''
      :root, [data-color-mode] {
        --bgColor-default: ${hex h.bg} !important;
        --bgColor-muted: ${hex h.surface1} !important;
        --bgColor-inset: ${hex h.surface0} !important;
        --fgColor-default: ${hex h.amber} !important;
        --fgColor-muted: ${hex h.lilac} !important;
        --fgColor-accent: ${hex h.cyan} !important;
        --fgColor-success: ${hex h.green} !important;
        --fgColor-danger: ${hex h.red} !important;
        --fgColor-attention: ${hex h.chip} !important;
        --borderColor-default: ${hex h.amberTint2} !important;
        --borderColor-muted: ${hex h.amberTint1} !important;
        --fontStack-monospace: ${fontStack} !important;
      }
  '')
  # claude.ai — its own tokens
  (block [ "claude.ai" ] ''
      :root, .dark, .light {
        --bg-000: ${hex h.surface1} !important; --bg-100: ${hex h.surface0} !important;
        --bg-200: ${hex h.bg} !important; --bg-300: ${hex h.bg} !important;
        --text-000: ${hex h.amber} !important; --text-100: ${hex h.amber} !important;
        --text-200: ${hex h.amber} !important; --text-300: ${hex h.lilac} !important;
        --text-400: ${hex h.dim} !important; --text-500: ${hex h.dim} !important;
        --accent-main-000: ${hex h.pink} !important; --accent-main-100: ${hex h.pink} !important;
        --accent-main-200: ${hex h.pink} !important;
        --accent-secondary-100: ${hex h.cyan} !important;
        --border-300: ${hex h.amberTint2} !important; --border-400: ${hex h.amberDim} !important;
        --font-mono: ${fontStack} !important;
      }
  '')
  # Hacker News — tables, no tokens: the few colours it has
  (block [ "news.ycombinator.com" ] ''
      body, #hnmain, td, .comment, .default { background: ${hex h.bg} !important; color: ${hex h.amber} !important; font-family: ${fontStack} !important; }
      .pagetop, .pagetop a, td[bgcolor="#ff6600"] { background: ${hex h.chip} !important; color: ${hex h.ink} !important; }
      .titleline a, a:link { color: ${hex h.amber} !important; }
      a:visited, .subtext, .comhead, .comhead a, .subtext a, .age a { color: ${hex h.lilac} !important; }
      .c00, .commtext { color: ${hex h.amber} !important; }
      .votearrow { filter: invert(1) sepia(1) saturate(4) hue-rotate(-10deg) !important; }
  '')
  # Reddit (new) — its tokens
  (block [ "reddit.com" "www.reddit.com" "old.reddit.com" ] ''
      :root, .theme-dark, .theme-light, body {
        --color-neutral-background: ${hex h.bg} !important;
        --color-neutral-background-weak: ${hex h.surface0} !important;
        --color-neutral-background-strong: ${hex h.surface1} !important;
        --color-neutral-content: ${hex h.amber} !important;
        --color-neutral-content-strong: ${hex h.amber} !important;
        --color-neutral-content-weak: ${hex h.lilac} !important;
        --color-neutral-border: ${hex h.amberTint2} !important;
        --color-neutral-border-weak: ${hex h.amberTint1} !important;
        --color-primary-background: ${hex h.pink} !important;
        --color-secondary-plain: ${hex h.cyan} !important;
      }
      body { background: ${hex h.bg} !important; color: ${hex h.amber} !important; }
      .res-nightmode .md, .md, .thing .title, .entry { color: ${hex h.amber} !important; }
  '')
  # Wikipedia — the vector skin's night tokens
  (block [ "wikipedia.org" ] ''
      :root, html.skin-theme-clientpref-night, html.skin-theme-clientpref-day {
        --background-color-base: ${hex h.bg} !important;
        --background-color-neutral: ${hex h.surface1} !important;
        --background-color-neutral-subtle: ${hex h.surface0} !important;
        --color-base: ${hex h.amber} !important;
        --color-subtle: ${hex h.lilac} !important;
        --color-emphasized: ${hex h.amber} !important;
        --color-progressive: ${hex h.cyan} !important;
        --color-visited: ${hex h.violet} !important;
        --border-color-base: ${hex h.amberTint2} !important;
        --border-color-subtle: ${hex h.amberTint1} !important;
      }
      body, .mw-body, #content, .vector-header-container, .mw-page-container { background: ${hex h.bg} !important; color: ${hex h.amber} !important; }
  '')
  # Google search — few stable tokens; the page and the result text
  (block [ "www.google.com" "google.com" ] ''
      body, #main, #cnt, .sfbg, .minidiv, .RNNXgb, #searchform { background: ${hex h.bg} !important; color: ${hex h.amber} !important; }
      .RNNXgb, .gLFyf, textarea { background: ${hex h.surface1} !important; color: ${hex h.amber} !important; }
      h3, .LC20lb { color: ${hex h.cyan} !important; }
      .VwiC3b, .yXK7lf, span { color: ${hex h.amber}; }
      cite, .byrV5b, .TbwUpd { color: ${hex h.lilac} !important; }
  '')
  # YouTube — its tokens (the player stays as it is)
  (block [ "youtube.com" "www.youtube.com" ] ''
      html, html[dark], ytd-app {
        --yt-spec-base-background: ${hex h.bg} !important;
        --yt-spec-raised-background: ${hex h.surface1} !important;
        --yt-spec-menu-background: ${hex h.surface1} !important;
        --yt-spec-general-background-a: ${hex h.bg} !important;
        --yt-spec-text-primary: ${hex h.amber} !important;
        --yt-spec-text-secondary: ${hex h.lilac} !important;
        --yt-spec-call-to-action: ${hex h.pink} !important;
        --yt-spec-10-percent-layer: ${hex h.amberTint1} !important;
      }
  '')
]
