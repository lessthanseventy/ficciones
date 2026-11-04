# The sites Andrew lives in, themed from the palette: userContent.css @-moz-document blocks
# appended after the vendored RetroTerminal body. Each entry = the domains and the CSS variables
# (or selectors) that site exposes for its own theme; the values come from palette.nix so the
# paper variant restyles them too. Add a site = add an entry; keep to variables where a site
# has them — selector rules rot with every redesign. On Floorp the floorp-ext extension loads this
# sheet and leaves every domain() named in it to these rules, recolouring all other pages itself.
{ hex, rgb, r, fontStack, light }:
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
  # Zoho Mail — its tokens, set on whichever of these the account's appearance puts on the page.
  # Listing a site takes it off the page recolourer, so message bodies are flattened here: their
  # hand-written colours would otherwise come through white. Its class hashes change with each
  # build, hence the *= on the double-underscore names.
  (block [ "mail.zoho.com" ] ''
      :root, body, [class*="zmApp"], [class*="zmThm"], [class*="zmLHS"], .zwpAppTheme {
        color-scheme: ${if light then "light" else "dark"} !important;
        --app-bg: ${hex r.ground} !important; --app-bg-rgb: ${rgb r.ground} !important;
        --app-box-bg: ${hex r.card} !important; --app-box-border-color: ${hex r.structure} !important;
        --app-rhsbar-bg: ${hex r.panel} !important; --app-rhsbar-border-color: ${hex r.menuGround} !important;
        --app-border-color: ${hex r.borderInactive} !important;
        --app-border-color-light: ${hex r.menuGround} !important;
        --app-border-color-dark: ${hex r.structure} !important;
        --app-separator-color: ${hex r.structure} !important;
        --app-dd-border-color: ${hex r.structure} !important;
        --app-center-block-border: ${hex r.menuGround} !important;
        --app-text-color: ${hex r.body} !important; --app-text-color-dark: ${hex r.body} !important;
        --app-text-color-title: ${hex r.body} !important; --app-text-color-light: ${hex r.meta} !important;
        --app-text-color-critical: ${hex r.alarm} !important;
        --app-hyperlink-color: ${hex r.key} !important; --app-action-color: ${hex r.key} !important;
        --app-icon-color: ${hex r.key} !important; --app-top-bar-icon-color: ${hex r.key} !important;
        --app-focus-outline-color: ${hex r.key} !important;
        --app-disabled-color: ${hex r.inactive} !important; --app-disabled-bg: ${hex r.raised} !important;
        --app-highlight-bg: ${hex r.selSoft} !important;
        --app-input-box-border-color: ${hex r.borderInactive} !important;
        --app-input-box-hover-border-color: ${hex r.body} !important;
        --app-input-box-filled-bg: ${hex r.inputGround} !important;
        --app-input-box-filled-hover-bg: ${hex r.raised} !important;
        --app-input-box-placeholder-color: ${hex r.inactive} !important;
        --app-list-header-bg: ${hex r.ground} !important; --app-list-header-color: ${hex r.key} !important;
        --app-list-header-border-color: ${hex r.menuGround} !important;
        --app-list-border-color: ${hex r.pressedGround} !important;
        --app-list-hover-bg: ${hex r.inputGround} !important; --app-list-hover-bg-dark: ${hex r.raised} !important;
        --app-list-checked-bg: ${hex r.selSoft} !important;
        --app-list-archived-bg: ${hex r.ground} !important; --app-list-archived-text-color: ${hex r.inactive} !important;
        --app-success-color: ${hex r.live} !important; --app-error-color: ${hex r.alarm} !important;
        --app-info-color: ${hex r.key} !important; --app-warning-color: ${hex r.warn} !important;
        --app-alert-color: ${hex r.body} !important; --app-alert-default-color: ${hex r.body} !important;
        --app-standard-success-bg: ${hex r.card} !important; --app-standard-error-bg: ${hex r.card} !important;
        --app-standard-info-bg: ${hex r.card} !important; --app-standard-warning-bg: ${hex r.card} !important;
        --app-alert-standard-default-bg: ${hex r.card} !important;
        --app-skeleton-bg: ${hex r.raised} !important; --app-skeleton-animation-bg: ${hex r.edge} !important;

        --app-grey-10: ${hex r.card} !important; --app-grey-20: ${hex r.inputGround} !important;
        --app-grey-50: ${hex r.raised} !important; --app-grey-100: ${hex r.edge} !important;
        --app-grey-200: ${hex r.borderInactive} !important; --app-grey-300: ${hex r.inactive} !important;
        --app-grey-400: ${hex r.meta} !important; --app-grey-500: ${hex r.meta} !important;
        --app-grey-600: ${hex r.body} !important; --app-grey-700: ${hex r.body} !important;
        --app-grey-800: ${hex r.body} !important; --app-grey-900: ${hex r.body} !important;

        --app-theme-color-100: ${hex r.menuGround} !important; --app-theme-color-100-rgb: ${rgb r.menuGround} !important;
        --app-theme-color-200: ${hex r.menuGround} !important; --app-theme-color-200-rgb: ${rgb r.menuGround} !important;
        --app-theme-color-300: ${hex r.borderInactive} !important; --app-theme-color-300-rgb: ${rgb r.borderInactive} !important;
        --app-theme-color-400: ${hex r.visited} !important; --app-theme-color-400-rgb: ${rgb r.visited} !important;
        --app-theme-color-500: ${hex r.cursorField} !important; --app-theme-color-500-rgb: ${rgb r.cursorField} !important;
        --app-theme-color-600: ${hex r.cursorField} !important; --app-theme-color-600-rgb: ${rgb r.cursorField} !important;
        --app-theme-color-700: ${hex r.cursorField} !important; --app-theme-color-700-rgb: ${rgb r.cursorField} !important;
        --app-theme-color-800: ${hex r.body} !important; --app-theme-color-800-rgb: ${rgb r.body} !important;
        --app-theme-color-900: ${hex r.body} !important; --app-theme-color-900-rgb: ${rgb r.body} !important;
        --app-theme-button-text-color: ${hex r.fieldInk} !important;
        --app-theme-list-hover-bg: ${hex r.inputGround} !important;
        --app-theme-list-selected-bg: ${hex r.selSoft} !important;
        --app-theme-list-right-click-bg: ${hex r.raised} !important;

        --app-lhs-bg: ${hex r.ground} !important; --app-lhs-apps-bg: ${hex r.ground} !important;
        --app-lhs-apps-color: ${hex r.key} !important; --app-lhs-apps-hover-bg: ${hex r.raised} !important;
        --app-lhs-list-color: ${hex r.body} !important; --app-lhs-list-selected-color: ${hex r.body} !important;
        --app-lhs-list-hover-bg: ${hex r.raised} !important; --app-lhs-list-selected-bg: ${hex r.cursorField} !important;
        --app-tab-bg: transparent !important; --app-tab-color: ${hex r.meta} !important;
        --app-tab-hover-bg: ${hex r.raised} !important; --app-tab-border-color: ${hex r.menuGround} !important;
        --app-tab-selected-bg: ${hex r.raised} !important; --app-tab-selected-color: ${hex r.body} !important;
        --app-tab-close-bg: ${hex r.panel} !important;

        --zmdefault-button-bg: ${hex r.card} !important; --zmdefault-button-hover-bg: ${hex r.raised} !important;
        --zmdefault-button-border-color: ${hex r.borderInactive} !important;
        --zmdefault-button-text-color: ${hex r.body} !important; --zmdefault-button-hover-text-color: ${hex r.body} !important;
        --zmdropdown-bg: ${hex r.card} !important; --zmpopover-bg: ${hex r.card} !important;
        --zmdatepicker-bg: ${hex r.card} !important; --zmdialog-backdrop-color: ${hex r.ground}cc !important;
        --zmtooltip-bg: ${hex r.card} !important; --zmtooltip-color: ${hex r.body} !important;
        --zmscrollbar-bg: ${hex r.ground} !important; --zmscrollbar-thumb-bg: ${hex r.structure} !important;
        --scrollbarbg: ${hex r.ground} !important; --scrolthumbbg: ${hex r.structure} !important;
        --grid-border-color: ${hex r.menuGround} !important; --grid-text-color: ${hex r.body} !important;
        --app-zia-text-color: linear-gradient(112deg, ${hex r.attention}, ${hex r.assistant}) !important;
        --app-zia-border: linear-gradient(112deg, ${hex r.attention}, ${hex r.assistant}) !important;
        --zmfont-display: ${fontStack} !important;
      }
      body, input, textarea, button, select { font-family: ${fontStack} !important; }

      /* read mail recedes to lilac; unread is the one thing here that wants you */
      .zmLSenderName, [class*="zmail-list-item-sender__"] { color: ${hex r.meta} !important; }
      .zmLSub, [class*="zmail-list-item-subject__"] { color: ${hex r.body} !important; font-weight: 400 !important; }
      .zmLDate, .zmLSize, .zmLFolder,
      [class*="zmail-list-item-date__"], [class*="zmail-list-item-size__"], [class*="zmail-list-item-folder__"] {
        color: ${hex r.inactive} !important;
      }
      .zmLUrd .zmLSenderName,
      [class*="zmail-list-item--unread"] [class*="zmail-list-item-sender__"] {
        color: ${hex r.attention} !important; font-weight: 700 !important;
      }
      .zmLUrd .zmLSub,
      [class*="zmail-list-item--unread"] [class*="zmail-list-item-subject__"] {
        color: ${hex r.body} !important; font-weight: 700 !important;
      }
      .zmLUrd .zmLDate, .zmLUrd .zmLSize, .zmLUrd .zmLFolder,
      [class*="zmail-list-item--unread"] [class*="zmail-list-item-date__"],
      [class*="zmail-list-item--unread"] [class*="zmail-list-item-size__"],
      [class*="zmail-list-item--unread"] [class*="zmail-list-item-folder__"] {
        color: ${hex r.key} !important;
      }
      .zmLTicon, .zmLTicon:before, .zmLTicon .path:before { color: ${hex r.inactive} !important; }
      .zmLUrd .zmLTicon, .zmLUrd .zmLTicon:before, .zmLUrd .zmLTicon .path:before { color: ${hex r.attention} !important; }

      /* a folder with unread mail is occupied; the one you are in is inverse video */
      .zmTreeCount { color: ${hex r.attention} !important; }
      .zmTreeNode .zmBold { color: ${hex r.live} !important; }
      .zmTreeNode.zmCurTree { background-color: ${hex r.cursorField} !important; }
      .zmTreeNode.zmCurTree, .zmTreeNode.zmCurTree * { color: ${hex r.fieldInk} !important; }
      .zmNewBtn, .zmNewBtn *, [class*="zmbtn--filled__"][class*="zmbtn--primary__"], [class*="zmbtn--filled__"][class*="zmbtn--primary__"] * {
        color: ${hex r.fieldInk} !important;
      }

      [class*="zmail-body__"] *, [class*="zmail-body__"] {
        background-color: transparent !important;
        color: ${hex r.body} !important;
        border-color: ${hex r.structure} !important;
      }
      [class*="zmail-body__"] a, [class*="zmail-body__"] a * { color: ${hex r.key} !important; }
      ::selection { background: ${hex r.selField} !important; color: ${hex r.selInk} !important; }
  '')
  # DuckDuckGo — its tokens. Results are links, so the title takes the key and the url recedes.
  (block [ "duckduckgo.com" ] ''
      :root, html, body, .dark-bg {
        color-scheme: ${if light then "light" else "dark"} !important;
        --ds-surface-canvas: ${hex r.ground} !important; --ds-surface-primary: ${hex r.ground} !important;
        --ds-surface-secondary: ${hex r.card} !important; --ds-surface-tertiary: ${hex r.inputGround} !important;
        --ds-text-primary: ${hex r.body} !important; --ds-text-secondary: ${hex r.meta} !important;
        --ds-text-tertiary: ${hex r.meta} !important;
        --ds-icons-primary: ${hex r.key} !important; --ds-icons-secondary: ${hex r.key} !important;
        --ds-icons-tertiary: ${hex r.inactive} !important;
        --ds-link-primary: ${hex r.key} !important; --ds-link-primary-visited: ${hex r.visited} !important;
        --ds-link-secondary: ${hex r.meta} !important; --ds-link-secondary-hover: ${hex r.body} !important;
        --ds-link-header: ${hex r.key} !important;
        --ds-accent-primary: ${hex r.cursorField} !important; --ds-accent-primary-content-color: ${hex r.fieldInk} !important;
        --ds-accent-primary-text-color: ${hex r.key} !important;
        --ds-input-primary-background-color: ${hex r.inputGround} !important;
        --ds-container-primary-background-color: ${hex r.card} !important;
        --ds-container-secondary-background-color: ${hex r.card} !important;
        --ds-container-tertiary-background-color: ${hex r.card} !important;
        --ds-container-primary-border-color: ${hex r.menuGround} !important;
        --ds-container-secondary-border-color: ${hex r.menuGround} !important;
        --ds-container-tertiary-border-color: ${hex r.menuGround} !important;
        --ds-control-primary-background-color: ${hex r.card} !important;
        --ds-control-secondary-background-color: ${hex r.card} !important;
        --ds-control-tertiary-background-color: ${hex r.card} !important;
        --ds-control-raised-primary-background-color: ${hex r.card} !important;
        --ds-control-raised-secondary-background-color: ${hex r.card} !important;
        --ds-control-raised-tertiary-background-color: ${hex r.card} !important;
        --ds-control-primary-border-color: ${hex r.borderInactive} !important;
        --ds-control-secondary-border-color: ${hex r.borderInactive} !important;
        --ds-control-tertiary-border-color: ${hex r.borderInactive} !important;
        --ds-destructive-primary-text-color: ${hex r.alarm} !important;
        --sds-color-text-01: ${hex r.body} !important; --sds-color-text-02: ${hex r.meta} !important;
        --sds-color-text-03: ${hex r.meta} !important; --sds-color-text-04: ${hex r.meta} !important;
        --sds-color-text-accent-01: ${hex r.key} !important; --sds-color-text-accent-02: ${hex r.body} !important;
        --sds-color-text-accent-01-alt: ${hex r.key} !important; --sds-color-text-accent-01-state-01: ${hex r.key} !important;
        --sds-color-text-accent-01-state-02: ${hex r.key} !important; --sds-color-border-accent-01: ${hex r.key} !important;
        --sds-color-text-link-01: ${hex r.key} !important; --sds-color-text-link-01-visited: ${hex r.visited} !important;
        --sds-color-text-link-02: ${hex r.meta} !important; --sds-color-text-link-02-hover: ${hex r.body} !important;
        --sds-color-text-success: ${hex r.live} !important; --sds-color-text-destructive: ${hex r.alarm} !important;
        --sds-color-text-on-color: ${hex r.fieldInk} !important; --sds-color-text-disabled: ${hex r.inactive} !important;
        --sds-color-background-01: ${hex r.ground} !important; --sds-color-background-02: ${hex r.card} !important;
        --sds-color-background-03: ${hex r.inputGround} !important;
        --sds-color-background-container-01: ${hex r.card} !important; --sds-color-background-container-02: ${hex r.card} !important;
        --sds-color-background-accent-01: ${hex r.cursorField} !important;
        --sds-color-background-utility: ${hex r.card} !important;
        --sds-color-border-01: ${hex r.menuGround} !important; --sds-color-border-02: ${hex r.menuGround} !important;
        --sds-color-border-03: ${hex r.borderInactive} !important;
        --theme-col-bg-page: ${hex r.ground} !important; --theme-col-bg-page-transparent: transparent !important;
        --theme-col-bg-ui: ${hex r.ground} !important; --theme-col-bg-header: ${hex r.ground} !important;
        --theme-col-bg-header-transparent: transparent !important; --theme-col-header-divider: ${hex r.menuGround} !important;
        --theme-col-metabar-bg: ${hex r.ground} !important; --theme-col-metabar-transparent: transparent !important;
        --theme-col-bg-search: ${hex r.inputGround} !important;
        --theme-col-txt-search-input: ${hex r.body} !important; --theme-col-txt-search-button: ${hex r.key} !important;
        --theme-col-txt-title: ${hex r.key} !important; --theme-col-bg-modal: ${hex r.card} !important;
        --theme-col-bg-card: ${hex r.card} !important; --ds-color-gray-0: ${hex r.card} !important;
        --theme-col-bg-button-primary: ${hex r.cursorField} !important; --theme-col-txt-button-primary: ${hex r.fieldInk} !important;
        --theme-col-bg-button-qna: ${hex r.card} !important; --theme-col-bg-button-qna-hover: ${hex r.raised} !important;
        --theme-col-bg-card-header: ${hex r.card} !important; --theme-col-bg-pill: ${hex r.card} !important;
        --theme-col-bg-ui-active: ${hex r.inputGround} !important; --theme-col-bg-header-modal: ${hex r.card} !important;
        --theme-col-bg-expandcollapse: ${hex r.card} !important; --theme-col-bg-expandcollapse-hover: ${hex r.raised} !important;
        --theme-col-bg-ext-dropdown: ${hex r.card} !important; --theme-col-sitefilter-enabled-card-bg: ${hex r.card} !important;
        --theme-pmenu-expandcollapse-bg: ${hex r.card} !important; --theme-pmenu-mobile-bg: ${hex r.card} !important;
        --ds-surface-backdrop: ${hex r.ground} !important; --result-item-bg: ${hex r.ground} !important;
        --theme-assist-bg-chat-system: ${hex r.card} !important; --theme-assist-gradient-stop: ${hex r.card} !important;
        --theme-assist-bg-opt-in: ${hex r.inputGround} !important; --theme-assist-bg-opt-in-border: ${hex r.menuGround} !important;
        --theme-assist-btn-bg: ${hex r.card} !important; --theme-assist-bg-icon: ${hex r.card} !important;
        --theme-assist-button-border-color: ${hex r.borderInactive} !important; --theme-assist-error-bg: ${hex r.card} !important;
        --theme-assist-txt-link: ${hex r.key} !important; --theme-assist-txt-link-hover: ${hex r.key} !important;
        --theme-assist-txt-link-active: ${hex r.key} !important;
      }
      .nav-menu--slideout { background-color: ${hex r.card} !important; }
      .footer, .zci-wrap { background-color: ${hex r.ground} !important; }
      html, body, .site-wrapper, .content-wrap, .header-wrap, .results--main, [data-testid="mainline"], [data-testid="result"] {
        background-color: ${hex r.ground} !important;
      }
      body { color: ${hex r.body} !important; font-family: ${fontStack} !important; }
      [data-testid="result-title-a"], [data-testid="result-title-a"] * { color: ${hex r.key} !important; }
      [data-testid="result-title-a"]:visited, [data-testid="result-title-a"]:visited * { color: ${hex r.visited} !important; }
      [data-testid="result-extras-url-link"], [data-testid="result-extras-url-link"] * { color: ${hex r.live} !important; }
      [data-result="snippet"], [data-result="snippet"] * { color: ${hex r.body} !important; }
      [data-result="snippet"] b { color: ${hex r.attention} !important; }
      [data-testid="search-form-input-wrapper"], [data-testid="search-form-input-wrapper"] input {
        background-color: ${hex r.inputGround} !important; color: ${hex r.body} !important;
      }
  '')
  # Jira and Confluence — Atlassian's design tokens. A tinted lozenge cannot hold 7:1 on these
  # grounds, so a subtle accent is its hue as text on the ground and a bold one is inverse video.
  (block [ "atlassian.net" "jira.atlassian.com" ] (''
      :root, html, html[data-color-mode], [data-theme] {
        color-scheme: ${if light then "light" else "dark"} !important;
        --ds-surface: ${hex r.ground} !important; --ds-elevation-surface-current: ${hex r.ground} !important;
        --ds-surface-sunken: ${hex r.panel} !important; --ds-surface-raised: ${hex r.card} !important;
        --ds-surface-overlay: ${hex r.card} !important; --ds-surface-hovered: ${hex r.inputGround} !important;
        --ds-surface-pressed: ${hex r.raised} !important; --ds-surface-raised-hovered: ${hex r.inputGround} !important;
        --ds-surface-raised-pressed: ${hex r.raised} !important; --ds-surface-overlay-hovered: ${hex r.inputGround} !important;
        --ds-surface-overlay-pressed: ${hex r.raised} !important;
        --ds-text: ${hex r.body} !important; --ds-text-subtle: ${hex r.meta} !important;
        --ds-text-subtlest: ${hex r.meta} !important; --ds-text-disabled: ${hex r.inactive} !important;
        --ds-text-inverse: ${hex r.fieldInk} !important; --ds-text-brand: ${hex r.key} !important;
        --ds-text-selected: ${hex r.selField} !important; --ds-text-information: ${hex r.key} !important;
        --ds-text-discovery: ${hex r.assistant} !important; --ds-text-success: ${hex r.live} !important;
        --ds-text-warning: ${hex r.warn} !important; --ds-text-warning-inverse: ${hex r.fieldInk} !important;
        --ds-text-danger: ${hex r.alarm} !important;
        --ds-link: ${hex r.key} !important; --ds-link-pressed: ${hex r.key} !important; --ds-link-visited: ${hex r.visited} !important;
        --ds-icon: ${hex r.key} !important; --ds-icon-subtle: ${hex r.meta} !important;
        --ds-icon-inverse: ${hex r.fieldInk} !important; --ds-icon-brand: ${hex r.key} !important;
        --ds-icon-selected: ${hex r.selField} !important; --ds-icon-disabled: ${hex r.inactive} !important;
        --ds-icon-information: ${hex r.key} !important; --ds-icon-discovery: ${hex r.assistant} !important;
        --ds-icon-success: ${hex r.live} !important; --ds-icon-warning: ${hex r.warn} !important;
        --ds-icon-warning-inverse: ${hex r.fieldInk} !important; --ds-icon-danger: ${hex r.alarm} !important;
        --ds-border: ${hex r.menuGround} !important; --ds-border-bold: ${hex r.borderInactive} !important;
        --ds-border-input: ${hex r.borderInactive} !important; --ds-border-focused: ${hex r.key} !important;
        --ds-border-selected: ${hex r.selField} !important; --ds-border-brand: ${hex r.cursorField} !important;
        --ds-background-input: ${hex r.inputGround} !important; --ds-background-input-hovered: ${hex r.raised} !important;
        --ds-background-input-pressed: ${hex r.inputGround} !important;
        --ds-background-neutral: ${hex r.card} !important; --ds-background-neutral-hovered: ${hex r.raised} !important;
        --ds-background-neutral-pressed: ${hex r.edge} !important; --ds-background-neutral-subtle: transparent !important;
        --ds-background-neutral-subtle-hovered: ${hex r.inputGround} !important;
        --ds-background-neutral-subtle-pressed: ${hex r.raised} !important;
        --ds-background-neutral-bold: ${hex r.body} !important; --ds-background-disabled: ${hex r.raised} !important;
        --ds-background-brand-bold: ${hex r.cursorField} !important; --ds-background-brand-bold-hovered: ${hex r.cursorField} !important;
        --ds-background-brand-bold-pressed: ${hex r.cursorField} !important; --ds-background-brand-boldest: ${hex r.cursorField} !important;
        --ds-background-brand-subtlest: ${hex r.card} !important;
        --ds-background-selected: ${hex r.selSoft} !important; --ds-background-selected-hovered: ${hex r.selSoft} !important;
        --ds-background-selected-pressed: ${hex r.selSoft} !important; --ds-background-selected-bold: ${hex r.selField} !important;
        --ds-background-success: ${hex r.ground} !important; --ds-background-success-bold: ${hex r.liveField} !important;
        --ds-background-warning: ${hex r.ground} !important; --ds-background-warning-bold: ${hex r.warnField} !important;
        --ds-background-danger: ${hex r.ground} !important; --ds-background-danger-bold: ${hex r.alarmField} !important;
        --ds-background-information: ${hex r.ground} !important; --ds-background-information-bold: ${hex r.accentField} !important;
        --ds-background-discovery: ${hex r.ground} !important; --ds-background-discovery-bold: ${hex r.attentionField} !important;
        --ds-blanket: ${hex r.ground}cc !important;
        --ds-background-information-hovered: ${hex r.raised} !important; --ds-background-information-pressed: ${hex r.edge} !important;
        --ds-background-discovery-hovered: ${hex r.raised} !important; --ds-background-discovery-pressed: ${hex r.edge} !important;
        --ds-background-success-hovered: ${hex r.raised} !important; --ds-background-success-pressed: ${hex r.edge} !important;
        --ds-background-warning-hovered: ${hex r.raised} !important; --ds-background-warning-pressed: ${hex r.edge} !important;
        --ds-background-danger-hovered: ${hex r.raised} !important; --ds-background-danger-pressed: ${hex r.edge} !important;
        --ds-background-brand-subtlest-hovered: ${hex r.raised} !important; --ds-background-brand-subtlest-pressed: ${hex r.edge} !important;
        font-family: ${fontStack} !important;
  '' + builtins.concatStringsSep "" (map ({ name, hue }: ''
        --ds-text-accent-${name}: ${hex hue} !important; --ds-text-accent-${name}-bolder: ${hex hue} !important;
        --ds-icon-accent-${name}: ${hex hue} !important; --ds-border-accent-${name}: ${hex hue} !important;
        --ds-background-accent-${name}-subtlest: ${hex r.ground} !important; --ds-background-accent-${name}-subtler: ${hex r.ground} !important;
        --ds-background-accent-${name}-subtle: ${hex r.ground} !important; --ds-background-accent-${name}-bolder: ${hex hue} !important;
        --ds-background-accent-${name}-subtlest-hovered: ${hex r.raised} !important; --ds-background-accent-${name}-subtlest-pressed: ${hex r.edge} !important;
        --ds-background-accent-${name}-subtler-hovered: ${hex r.raised} !important; --ds-background-accent-${name}-subtler-pressed: ${hex r.edge} !important;
        --ds-background-accent-${name}-subtle-hovered: ${hex r.raised} !important; --ds-background-accent-${name}-subtle-pressed: ${hex r.edge} !important;
  '') [
    { name = "blue"; hue = r.key; }
    { name = "teal"; hue = r.key; }
    { name = "green"; hue = r.live; }
    { name = "lime"; hue = r.live; }
    { name = "yellow"; hue = r.body; }
    { name = "orange"; hue = r.warn; }
    { name = "red"; hue = r.alarm; }
    { name = "magenta"; hue = r.attention; }
    { name = "purple"; hue = r.assistant; }
    { name = "gray"; hue = r.meta; }
  ]) + ''
      }
      html, body { background-color: ${hex r.ground} !important; color: ${hex r.body} !important; }
      body, input, textarea, button, select { font-family: ${fontStack} !important; }
      h1, h2, h3, h4, h5, h6 { color: ${hex r.attention} !important; }
      a:link:not([role=button]) { color: ${hex r.key} !important; }
      a:visited:not([role=button]) { color: ${hex r.visited} !important; }
      [data-testid*="lozenge" i], [class*="lozenge" i] { background-color: ${hex r.ground} !important; }
      [data-testid*="lozenge" i], [data-testid*="lozenge" i] *, [class*="lozenge" i], [class*="lozenge" i] * { color: ${hex r.key} !important; }
      .aui-header { background-color: ${hex r.ground} !important; border-bottom: 1px solid ${hex r.menuGround} !important; }
      #onetrust-banner-sdk, #onetrust-pc-btn-handler { background-color: ${hex r.card} !important; color: ${hex r.body} !important; }
      #onetrust-banner-sdk * { color: ${hex r.body} !important; }
      #onetrust-banner-sdk a { color: ${hex r.key} !important; }
      #onetrust-accept-btn-handler { background-color: ${hex r.cursorField} !important; color: ${hex r.fieldInk} !important; }
      #onetrust-pc-sdk, #onetrust-pc-sdk div { background-color: ${hex r.card} !important; color: ${hex r.body} !important; }
  ''))
  # Craigslist — no tokens and no dark mode, so its own class names.
  (block [ "craigslist.org" ] ''
      :root, html, body { color-scheme: ${if light then "light" else "dark"} !important; background-color: ${hex r.ground} !important; color: ${hex r.body} !important; }
      * { scrollbar-color: ${hex r.structure} ${hex r.ground}; }
      a:link { color: ${hex r.key} !important; }
      a:visited { color: ${hex r.visited} !important; }
      h1, h2, h3, h4, .heading, a.heading, a.heading:visited { color: ${hex r.attention} !important; background: none !important; }
      .cl-goto-home { color: ${hex r.attention} !important; }
      .icon, [class*="icom-"], td { color: ${hex r.key} !important; }
      svg text { fill: ${hex r.body} !important; }
      .priceinfo, .price { color: ${hex r.live} !important; }
      .posting-title .label, .gallery-card a { color: ${hex r.key} !important; }
      .gallery-card a:visited .label { color: ${hex r.visited} !important; }
      .cl-header, .cl-footer, .cl-query-bar, .cl-search-filters-panel, .cl-search-toolbar, .cl-horiz-scroller, .priceinfo, .left, .right, .left div, .right div, td,
      .cl-search-day-paginator-ng, .bd-tab-content, .bd-input, #curtain .cover, .cl-homepage-top-banner, .cl-homepage-top-banner > div {
        background-color: ${hex r.ground} !important;
      }
      span.label { color: ${hex r.key} !important; }
      td.disabled { color: ${hex r.inactive} !important; }
      td.today, td.today a { background-color: ${hex r.cursorField} !important; color: ${hex r.fieldInk} !important; }
      .cl-goto-post { background-color: ${hex r.inputGround} !important; }
      .meta, .filter-label, .cl-label, .count { color: ${hex r.meta} !important; }
      .gallery-card, .cl-search-result { background-color: ${hex r.ground} !important; border-color: ${hex r.menuGround} !important; }
      input, select, textarea, .bd-button, .cl-exec-search, .bd-combo-box {
        background-color: ${hex r.inputGround} !important; color: ${hex r.body} !important; border-color: ${hex r.borderInactive} !important;
      }
      .bd-button.selected, .bd-button.selected *, .bd-button.active, .bd-button.active * {
        background-color: ${hex r.cursorField} !important; color: ${hex r.fieldInk} !important;
      }
      input[type="checkbox"], input[type="radio"] { accent-color: ${hex r.cursorField} !important; }
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
