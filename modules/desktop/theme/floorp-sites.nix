# The sites Andrew lives in, themed from the palette: userContent.css @-moz-document blocks
# appended after the vendored RetroTerminal body. Each entry = the domains and the CSS variables
# (or selectors) that site exposes for its own theme; the values come from palette.nix so the
# paper variant restyles them too. Add a site = add an entry; keep to variables where a site
# has them — selector rules rot with every redesign. On Floorp the floorp-ext extension loads this
# sheet and leaves every domain() named in it to these rules, recolouring all other pages itself.
{ hex, r, fontStack }:
let
  block = domains: css: ''
    @-moz-document ${builtins.concatStringsSep ", " (map (d: "domain(\"${d}\")") domains)} {
    ${css}
    }
  '';
in
builtins.concatStringsSep "\n" [
  # Sidebery's pages, by path: an extension's uuid differs per profile. Sidebery keeps its own
  # custom CSS in its storage, and only a user sheet's !important beats that.
  ''
    @-moz-document regexp("moz-extension://[0-9a-f-]+/(sidebar|page\\.setup|popup\\.[a-z-]+)/.*") {
      :root, #root {
        --frame-bg: ${hex r.panel} !important;
        --frame-fg: ${hex r.body} !important;
        --toolbar-bg: ${hex r.card} !important;
        --toolbar-fg: ${hex r.body} !important;
        --popup-bg: ${hex r.card} !important;
        --popup-fg: ${hex r.body} !important;
        --border: ${hex r.structure} !important;
        --ctx-menu-bg: ${hex r.card} !important;
        --ctx-menu-fg: ${hex r.body} !important;
        --ctx-menu-separator: ${hex r.structure} !important;
        --notification-bg: ${hex r.card} !important;
        --notification-fg: ${hex r.body} !important;
        --windows-popup-window-border: ${hex r.structure} !important;
        --nav-btn-fg: ${hex r.body} !important;
        --nav-btn-accent: ${hex r.key} !important;
        --nav-btn-active-shadow: none !important;
        --accent: ${hex r.key} !important;
        --status-active: ${hex r.key} !important;
        --status-notice: ${hex r.attention} !important;
        --status-ok: ${hex r.live} !important;
        --status-err: ${hex r.alarm} !important;
        --scroll-progress-bg: ${hex r.key} !important;
        --scroll-color: ${hex r.structure} !important;
        --frame-scrollbar-color: ${hex r.structure} !important;
        --toolbar-scrollbar-color: ${hex r.structure} !important;
        --popup-scrollbar-color: ${hex r.structure} !important;
        --tabs-normal-bg: transparent !important;
        --tabs-normal-fg: ${hex r.body} !important;
        --tabs-activated-bg: ${hex r.cursorField} !important;
        --tabs-activated-fg: ${hex r.fieldInk} !important;
        --tabs-activated-shadow: none !important;
        --tabs-progress-bg: ${hex r.structure} !important;
        --tabs-discarded-title-opacity: 0.75 !important;
        --active-el-bg: ${hex r.cursorField} !important;
        --active-el-fg: ${hex r.fieldInk} !important;
        --active-el-shadow: none !important;
        --bookmarks-node-activated-fg: ${hex r.key} !important;
        --bookmarks-expanded-folder-bg: ${hex r.card} !important;
        --bookmarks-expanded-folder-shadow: none !important;
        --ctx-menu-shadow: 0 0 0 1px ${hex r.structure} !important;
        --popup-shadow: 0 0 0 1px ${hex r.structure} !important;
        --frame-el-overlay-hover-bg: color-mix(in srgb, ${hex r.body} 10%, transparent) !important;
        --frame-el-overlay-clicked-bg: color-mix(in srgb, ${hex r.body} 20%, transparent) !important;
        --frame-el-overlay-selected-bg: ${hex r.selField} !important;
        --frame-el-overlay-selected-border: ${hex r.selField} !important;
        --toolbar-el-overlay-hover-bg: color-mix(in srgb, ${hex r.body} 10%, transparent) !important;
        --toolbar-el-overlay-clicked-bg: color-mix(in srgb, ${hex r.body} 20%, transparent) !important;
        --toolbar-el-overlay-active-bg: color-mix(in srgb, ${hex r.body} 15%, transparent) !important;
        --toolbar-el-overlay-active-border: ${hex r.body} !important;
        --toolbar-el-overlay-selected-bg: ${hex r.selField} !important;
        --toolbar-el-overlay-selected-border: ${hex r.selField} !important;
        --active-el-overlay-hover-bg: color-mix(in srgb, ${hex r.fieldInk} 10%, transparent) !important;
        --active-el-overlay-clicked-bg: color-mix(in srgb, ${hex r.fieldInk} 20%, transparent) !important;
      }
      body, #root, .Sidebar, .ScrollBox, .NavigationBar {
        background-color: ${hex r.panel} !important;
      }
    }
  ''
  # GitHub — primer's design tokens
  (block [ "github.com" ] ''
      :root, [data-color-mode] {
        --bgColor-default: ${hex r.ground} !important;
        --bgColor-muted: ${hex r.card} !important;
        --bgColor-inset: ${hex r.panel} !important;
        --fgColor-default: ${hex r.body} !important;
        --fgColor-muted: ${hex r.meta} !important;
        --fgColor-accent: ${hex r.key} !important;
        --fgColor-success: ${hex r.live} !important;
        --fgColor-danger: ${hex r.alarm} !important;
        --fgColor-attention: ${hex r.cursorField} !important;
        --borderColor-default: ${hex r.menuGround} !important;
        --borderColor-muted: ${hex r.pressedGround} !important;
        --fontStack-monospace: ${fontStack} !important;
      }
  '')
  # claude.ai — its own tokens
  (block [ "claude.ai" ] ''
      :root, .dark, .light {
        --bg-000: ${hex r.card} !important; --bg-100: ${hex r.panel} !important;
        --bg-200: ${hex r.ground} !important; --bg-300: ${hex r.ground} !important;
        --text-000: ${hex r.body} !important; --text-100: ${hex r.body} !important;
        --text-200: ${hex r.body} !important; --text-300: ${hex r.meta} !important;
        --text-400: ${hex r.inactive} !important; --text-500: ${hex r.inactive} !important;
        --accent-main-000: ${hex r.attention} !important; --accent-main-100: ${hex r.attention} !important;
        --accent-main-200: ${hex r.attention} !important;
        --accent-secondary-100: ${hex r.key} !important;
        --border-300: ${hex r.menuGround} !important; --border-400: ${hex r.borderInactive} !important;
        --font-mono: ${fontStack} !important;
      }
  '')
  # Hacker News — tables, no tokens: the few colours it has
  (block [ "news.ycombinator.com" ] ''
      body, #hnmain, td, .comment, .default { background: ${hex r.ground} !important; color: ${hex r.body} !important; font-family: ${fontStack} !important; }
      .pagetop, .pagetop a, td[bgcolor="#ff6600"] { background: ${hex r.cursorField} !important; color: ${hex r.fieldInk} !important; }
      .titleline a, a:link { color: ${hex r.body} !important; }
      a:visited, .subtext, .comhead, .comhead a, .subtext a, .age a { color: ${hex r.meta} !important; }
      .c00, .commtext { color: ${hex r.body} !important; }
      .votearrow { filter: invert(1) sepia(1) saturate(4) hue-rotate(-10deg) !important; }
  '')
  # Reddit (new) — its tokens
  (block [ "reddit.com" "www.reddit.com" "old.reddit.com" ] ''
      :root, .theme-dark, .theme-light, body {
        --color-neutral-background: ${hex r.ground} !important;
        --color-neutral-background-weak: ${hex r.panel} !important;
        --color-neutral-background-strong: ${hex r.card} !important;
        --color-neutral-content: ${hex r.body} !important;
        --color-neutral-content-strong: ${hex r.body} !important;
        --color-neutral-content-weak: ${hex r.meta} !important;
        --color-neutral-border: ${hex r.menuGround} !important;
        --color-neutral-border-weak: ${hex r.pressedGround} !important;
        --color-primary-background: ${hex r.attention} !important;
        --color-secondary-plain: ${hex r.key} !important;
      }
      body { background: ${hex r.ground} !important; color: ${hex r.body} !important; }
      .res-nightmode .md, .md, .thing .title, .entry { color: ${hex r.body} !important; }
  '')
  # Wikipedia — the vector skin's night tokens
  (block [ "wikipedia.org" ] ''
      :root, html.skin-theme-clientpref-night, html.skin-theme-clientpref-day {
        --background-color-base: ${hex r.ground} !important;
        --background-color-neutral: ${hex r.card} !important;
        --background-color-neutral-subtle: ${hex r.panel} !important;
        --color-base: ${hex r.body} !important;
        --color-subtle: ${hex r.meta} !important;
        --color-emphasized: ${hex r.body} !important;
        --color-progressive: ${hex r.key} !important;
        --color-visited: ${hex r.assistant} !important;
        --border-color-base: ${hex r.menuGround} !important;
        --border-color-subtle: ${hex r.pressedGround} !important;
      }
      body, .mw-body, #content, .vector-header-container, .mw-page-container { background: ${hex r.ground} !important; color: ${hex r.body} !important; }
  '')
  # Google search — few stable tokens; the page and the result text
  (block [ "www.google.com" "google.com" ] ''
      body, #main, #cnt, .sfbg, .minidiv, .RNNXgb, #searchform { background: ${hex r.ground} !important; color: ${hex r.body} !important; }
      .RNNXgb, .gLFyf, textarea { background: ${hex r.card} !important; color: ${hex r.body} !important; }
      h3, .LC20lb { color: ${hex r.key} !important; }
      .VwiC3b, .yXK7lf, span { color: ${hex r.body}; }
      cite, .byrV5b, .TbwUpd { color: ${hex r.meta} !important; }
  '')
  # YouTube — its tokens (the player stays as it is)
  (block [ "youtube.com" "www.youtube.com" ] ''
      html, html[dark], ytd-app {
        --yt-spec-base-background: ${hex r.ground} !important;
        --yt-spec-raised-background: ${hex r.card} !important;
        --yt-spec-menu-background: ${hex r.card} !important;
        --yt-spec-general-background-a: ${hex r.ground} !important;
        --yt-spec-text-primary: ${hex r.body} !important;
        --yt-spec-text-secondary: ${hex r.meta} !important;
        --yt-spec-call-to-action: ${hex r.attention} !important;
        --yt-spec-10-percent-layer: ${hex r.pressedGround} !important;
      }
  '')
]
