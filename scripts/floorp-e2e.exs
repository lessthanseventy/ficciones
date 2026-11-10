# A throwaway headless Floorp with its own HOME and profile: flips the theme link and checks the
# chrome and a page repaint with no restart. usage: elixir floorp-e2e.exs <xpi> <user.js>
[xpi, prefs] = System.argv()
root = Path.join(System.tmp_dir!(), "floorp-e2e-#{System.unique_integer([:positive])}")
profile = Path.join(root, "profile")
config = Path.join(root, ".config/ficciones")
File.mkdir_p!(Path.join(profile, "extensions"))
File.cp!(xpi, Path.join(profile, "extensions/theme@ficciones.xpi"))
port_n = 2828 + rem(System.unique_integer([:positive]), 1000)

File.write!(
  Path.join(profile, "user.js"),
  File.read!(prefs) <> ~s|user_pref("marionette.port", #{port_n});\n|
)

themes = %{
  "a" => {"#112233", "#ddeeff", false},
  "b" => {"#f4ecdc", "#2c2a33", true},
  "bare" => {"#223344", "#ddeeff", false},
  "broken" => {"#334455", "#ddeeff", false},
  "corrupt" => {"#445566", "#ddeeff", false}
}

for {name, {ground, body, light}} <- themes do
  dir = Path.join(config, "themes/#{name}")
  File.mkdir_p!(dir)

  File.write!(
    Path.join(dir, "floorp-userChrome.css"),
    ~s|@-moz-document url(chrome://browser/content/browser.xhtml) { :root { --retro-bg: #{ground}; } }|
  )

  File.write!(
    Path.join(dir, "floorp-userContent.css"),
    ~s|@-moz-document domain("example.invalid") { :root { --site: #{ground}; } }|
  )

  File.write!(
    Path.join(dir, "floorp-page.json"),
    JSON.encode!(%{
      light: light,
      ground: ground,
      body: body,
      selection: "#884488",
      link: body,
      visited: body,
      heading: body,
      code: body
    })
  )
end

File.write!(Path.join(config, "themes/bare/floorp-userContent.css"), "")

File.write!(Path.join(config, "themes/corrupt/floorp-page.json"), "{")

# contentScripts.register refuses this as a match pattern
File.write!(
  Path.join(config, "themes/broken/floorp-userContent.css"),
  ~s|@-moz-document domain("a*b") { :root { --site: red; } }|
)

link = Path.join(config, "theme")
File.ln_s!("themes/a", link)

# over http: file:// pages never receive the content script here. On 127.0.0.2: the extension never
# recolours localhost or 127.0.0.1
html =
  ~s|<!doctype html><html><body>plain white page <a id="l" href="/x" style="color: #00f">a link</a></body></html>|

{:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 2}])
{:ok, http_port} = :inet.port(listen)
page = "http://127.0.0.2:#{http_port}/"
# another site, for what a setting does beyond the open page's
{:ok, listen_other} =
  :gen_tcp.listen(http_port, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 3}])

serve = fn serve, listen ->
  {:ok, c} = :gen_tcp.accept(listen)
  {:ok, request} = :gen_tcp.recv(c, 0, 5000)

  {csp, body} =
    cond do
      String.starts_with?(request, "GET /csp") ->
        {"content-security-policy: style-src 'self'\r\n", html}

      String.starts_with?(request, "GET /meta") ->
        {"",
         String.replace(
           html,
           "<body>",
           ~s|<head><meta http-equiv="Content-Security-Policy" content="style-src 'self'"></head><body>|
         )}

      true ->
        {"", html}
    end

  :gen_tcp.send(
    c,
    "HTTP/1.1 200 OK\r\ncontent-type: text/html\r\n#{csp}connection: close\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}"
  )

  :gen_tcp.close(c)
  serve.(serve, listen)
end

spawn_link(fn -> serve.(serve, listen) end)
spawn_link(fn -> serve.(serve, listen_other) end)

floorp = System.find_executable("floorp")

port =
  Port.open({:spawn_executable, floorp}, [
    :binary,
    :stderr_to_stdout,
    args: [
      "--headless",
      "--marionette",
      "-remote-allow-system-access",
      "--no-remote",
      "--profile",
      profile
    ],
    env: [{~c"HOME", String.to_charlist(root)}]
  ])

{:os_pid, os_pid} = Port.info(port, :os_pid)

defmodule M do
  def connect(p, tries \\ 120) do
    case :gen_tcp.connect(~c"127.0.0.1", p, [:binary, active: false, packet: :raw], 500) do
      {:ok, s} ->
        read(s)
        s

      _ when tries > 0 ->
        Process.sleep(500)
        connect(p, tries - 1)

      _ ->
        :error
    end
  end

  defp len(s, acc \\ "") do
    {:ok, c} = :gen_tcp.recv(s, 1, 60_000)
    if c == ":", do: String.to_integer(acc), else: len(s, acc <> c)
  end

  def read(s) do
    {:ok, b} = :gen_tcp.recv(s, len(s), 60_000)
    JSON.decode!(b)
  end

  def call(s, cmd, params \\ %{}) do
    j = JSON.encode!([0, System.unique_integer([:positive]), cmd, params])
    :ok = :gen_tcp.send(s, "#{byte_size(j)}:#{j}")
    [1, _, err, res] = read(s)
    if err, do: raise("#{cmd}: #{inspect(err)}")
    res
  end

  def js(s, script), do: call(s, "WebDriver:ExecuteScript", %{script: script, args: []})["value"]

  def wait(what, want, f, tries \\ 40) do
    got = f.()

    cond do
      got == want ->
        IO.puts("ok   #{what}: #{got}")

      tries > 0 ->
        Process.sleep(250)
        wait(what, want, f, tries - 1)

      true ->
        raise "FAIL #{what}: want #{want}, got #{inspect(got)}"
    end
  end
end

drain = fn drain, acc ->
  receive do
    {^port, {:data, d}} -> drain.(drain, acc <> d)
  after
    0 -> acc
  end
end

s =
  case M.connect(port_n) do
    :error ->
      IO.puts("floorp never opened marionette:\n" <> String.slice(drain.(drain, ""), -3000, 3000))
      System.cmd("kill", ["#{os_pid}"])
      File.rm_rf(root)
      System.halt(1)

    s ->
      s
  end

M.call(s, "WebDriver:NewSession", %{})

code =
  try do
    chrome = fn ->
      M.call(s, "Marionette:SetContext", %{value: "chrome"})

      M.js(
        s,
        ~s|return getComputedStyle(document.documentElement).getPropertyValue("--retro-bg").trim()|
      )
    end

    pageBg = fn ->
      M.call(s, "Marionette:SetContext", %{value: "content"})
      M.js(s, "return getComputedStyle(document.documentElement).backgroundColor")
    end

    linkInk = fn ->
      M.call(s, "Marionette:SetContext", %{value: "content"})
      M.js(s, ~s|return getComputedStyle(document.getElementById("l")).color|)
    end

    M.call(s, "WebDriver:Navigate", %{url: page})

    M.wait("chrome, theme a", "#112233", chrome)
    M.wait("page open before the extension started", "rgb(17, 34, 51)", pageBg)
    M.wait("a link takes the theme's accent", "rgb(221, 238, 255)", linkInk)

    File.rm!(link)
    File.ln_s!("themes/b", link)
    M.wait("chrome, flipped to b", "#f4ecdc", chrome)
    M.wait("same open page, flipped to b", "rgb(244, 236, 220)", pageBg)
    M.wait("the link flips with it", "rgb(44, 42, 51)", linkInk)
    M.call(s, "Marionette:SetContext", %{value: "content"})
    M.call(s, "WebDriver:Navigate", %{url: page})
    M.wait("fresh page, under b", "rgb(244, 236, 220)", pageBg)

    File.rm!(link)
    File.ln_s!("themes/bare", link)
    M.wait("chrome, a theme with no site blocks", "#223344", chrome)
    M.call(s, "Marionette:SetContext", %{value: "content"})
    M.call(s, "WebDriver:Navigate", %{url: page})
    M.wait("and a fresh page still paints", "rgb(34, 51, 68)", pageBg)
    File.rm!(link)
    File.ln_s!("themes/broken", link)
    M.wait("chrome, a theme the page half refuses", "#334455", chrome)
    File.rm!(link)
    File.ln_s!("themes/b", link)
    M.wait("back to b", "#f4ecdc", chrome)
    M.call(s, "Marionette:SetContext", %{value: "content"})
    M.call(s, "WebDriver:Navigate", %{url: page})
    M.wait("the next theme still reaches pages", "rgb(244, 236, 220)", pageBg)

    M.call(s, "Marionette:SetContext", %{value: "chrome"})

    M.wait(
      "the button sits on the toolbar",
      "nav-bar",
      fn ->
        M.js(
          s,
          ~s|return CustomizableUI.getPlacementOfWidget("theme_ficciones-browser-action")?.area \|\| "no placement"|
        )
      end
    )

    menu =
      "moz-extension://" <>
        M.js(
          s,
          ~s|return WebExtensionPolicy.getByID("theme@ficciones").mozExtensionHostname|
        ) <> "/popup.html"

    M.call(s, "Marionette:SetContext", %{value: "content"})
    pageTab = M.call(s, "WebDriver:GetWindowHandle")["value"]
    menuTab = M.call(s, "WebDriver:NewWindow", %{type: "tab"})["handle"]
    switch = fn tab -> M.call(s, "WebDriver:SwitchToWindow", %{handle: tab, focus: true}) end

    switch.(menuTab)
    M.call(s, "WebDriver:Navigate", %{url: menu})

    M.wait("the menu shows the palette", "7", fn ->
      "#{M.js(s, ~s|return document.querySelectorAll("#swatches span").length|)}"
    end)

    button = fn getter ->
      M.call(s, "WebDriver:ExecuteAsyncScript", %{
        script:
          "const done = arguments[arguments.length - 1]; window.browser.browserAction.#{getter}({}).then(done);",
        args: []
      })["value"]
    end

    flipTo = fn name ->
      File.rm!(link)
      File.ln_s!("themes/#{name}", link)
    end

    M.wait("a healthy theme shows no badge", "", fn -> button.("getBadgeText") end)
    flipTo.("broken")
    M.wait("a refused theme badges the button", "!", fn -> button.("getBadgeText") end)

    M.wait("and the button says why", true, fn ->
      String.starts_with?(button.("getTitle"), "Ficciones: ")
    end)

    flipTo.("b")
    M.wait("the next good theme clears the badge", "", fn -> button.("getBadgeText") end)
    M.wait("and the title", "Ficciones", fn -> button.("getTitle") end)
    flipTo.("corrupt")
    M.wait("an unreadable theme badges it too", "!", fn -> button.("getBadgeText") end)
    flipTo.("b")
    M.wait("and clears the same way", "", fn -> button.("getBadgeText") end)

    M.js(s, ~s|document.getElementById("all").click()|)
    switch.(pageTab)
    M.wait("all sites off clears the open page", "rgb(0, 0, 255)", linkInk)
    switch.(menuTab)
    M.js(s, ~s|document.getElementById("all").click()|)
    switch.(pageTab)
    M.wait("all sites on repaints it", "rgb(44, 42, 51)", linkInk)

    setHost = fn off ->
      switch.(menuTab)

      M.call(s, "WebDriver:ExecuteAsyncScript", %{
        script:
          ~s|const done = arguments[arguments.length - 1]; window.browser.runtime.sendMessage({ host: "127.0.0.2", off: #{off} }).then(() => done(1));|,
        args: []
      })

      switch.(pageTab)
    end

    setHost.(true)
    M.wait("this site off clears the open page", "rgb(0, 0, 255)", linkInk)
    M.call(s, "WebDriver:Navigate", %{url: page})
    M.wait("and it stays off on a fresh load", "rgb(0, 0, 255)", linkInk)
    setHost.(false)
    M.wait("this site on repaints it", "rgb(44, 42, 51)", linkInk)
    M.call(s, "WebDriver:Navigate", %{url: page})
    M.wait("and a fresh load paints again", "rgb(44, 42, 51)", linkInk)

    M.call(s, "WebDriver:Navigate", %{url: page <> "csp"})
    M.wait("a page whose policy blocks styles still paints", "rgb(244, 236, 220)", pageBg)
    M.wait("and its links too", "rgb(44, 42, 51)", linkInk)
    File.rm!(link)
    File.ln_s!("themes/a", link)
    M.wait("and it flips with the theme", "rgb(17, 34, 51)", pageBg)
    M.call(s, "WebDriver:Navigate", %{url: page <> "meta"})
    M.wait("a policy in a meta tag too", "rgb(17, 34, 51)", pageBg)

    send = fn message ->
      switch.(menuTab)

      M.call(s, "WebDriver:ExecuteAsyncScript", %{
        script:
          "const done = arguments[arguments.length - 1]; window.browser.runtime.sendMessage(#{JSON.encode!(message)}).then(() => done(1));",
        args: []
      })

      M.call(s, "WebDriver:Navigate", %{url: menu})
    end

    menuSays = fn what, want, script ->
      switch.(menuTab)
      M.wait(what, want, fn -> "#{M.js(s, script)}" end)
    end

    menuSays.(
      "the menu has every dial",
      "brightness contrast sepia grayscale textStroke",
      ~s|return [...document.querySelectorAll("#dials input")].map(i => i.id).join(" ")|
    )

    full = "rgb(17, 34, 51)"
    dim = "rgb(9, 17, 26)"
    other = "http://127.0.0.3:#{http_port}/"

    send.(%{tune: %{brightness: 50}})
    switch.(pageTab)
    M.wait("the brightness dial dims the open page", dim, pageBg)
    M.call(s, "WebDriver:Navigate", %{url: other})
    M.wait("and every other site", dim, pageBg)
    send.(%{reset: true})
    switch.(pageTab)
    M.wait("reset puts it back", full, pageBg)

    send.(%{tune: %{textStroke: 0.5}})
    switch.(pageTab)

    M.wait("the text weight dial thickens the text", "0.5px", fn ->
      M.js(
        s,
        ~s|return getComputedStyle(document.body).getPropertyValue("-webkit-text-stroke-width")|
      )
    end)

    send.(%{reset: true})

    send.(%{host: "127.0.0.3", tune: %{brightness: 50}})
    switch.(pageTab)
    M.wait("a dial for just this site dims it", dim, pageBg)
    M.call(s, "WebDriver:Navigate", %{url: page})
    M.wait("and leaves another site alone", full, pageBg)
    send.(%{host: "127.0.0.3", reset: true})

    send.(%{host: "example.test", off: true})
    firstOff = ~s|return document.querySelector("#offList button")?.dataset.host \|\| "none"|
    menuSays.("the menu lists a site switched off", "example.test", firstOff)
    M.js(s, ~s|document.querySelector("#offList button").click()|)
    menuSays.("its button turns it back on", "none", firstOff)

    # the menu reads the active tab, so a background menu tab can be pointed at any page
    showFor = fn tab ->
      M.call(s, "WebDriver:SwitchToWindow", %{handle: tab, focus: true})
      M.call(s, "WebDriver:SwitchToWindow", %{handle: menuTab, focus: false})
      M.js(s, ~s|document.getElementById("all").click(); document.getElementById("all").click()|)
    end

    showFor.(pageTab)

    M.wait("over a site the menu names it", "127.0.0.2", fn ->
      M.js(s, ~s|return document.getElementById("host").textContent|)
    end)

    switch.(pageTab)
    M.call(s, "WebDriver:Navigate", %{url: "about:blank"})
    showFor.(pageTab)

    M.wait("over a page it cannot read it still draws", "true", fn ->
      "#{M.js(s, ~s|return document.getElementById("siteRow").hidden|)}"
    end)

    send.(%{host: "example.test", off: true})
    switch.(pageTab)
    M.call(s, "WebDriver:Navigate", %{url: page})
    build = fn -> M.js(s, ~s|return document.documentElement.dataset.build \|\| "none"|) end
    M.wait("the installed build runs", "none", build)

    {:ok, files} = :zip.extract(String.to_charlist(xpi), [:memory])

    rebuilt =
      Enum.map(files, fn
        {~c"page.js", code} ->
          {~c"page.js", code <> "document.documentElement.dataset.build = 2;\n"}

        file ->
          file
      end)

    {:ok, {_, zipped}} = :zip.create(~c"rebuilt.xpi", rebuilt, [:memory])
    installed = Path.join(profile, "extensions/theme@ficciones.xpi")
    File.rm!(installed)
    File.write!(installed, zipped)

    M.wait("a new install reaches the open tab", "2", fn -> "#{build.()}" end, 80)
    M.wait("which keeps its paint", full, pageBg)
    M.call(s, "WebDriver:Navigate", %{url: page})
    M.wait("a fresh page runs it too", "2", fn -> "#{build.()}" end)
    M.wait("the chrome is themed again", "#112233", chrome)
    M.call(s, "Marionette:SetContext", %{value: "content"})
    M.call(s, "WebDriver:Navigate", %{url: menu})
    M.wait("the settings came through", "example.test", fn -> M.js(s, firstOff) end)

    IO.puts("PASS")
    0
  rescue
    e ->
      IO.puts(Exception.message(e))

      # why: did floorp even load it?
      try do
        M.call(s, "Marionette:SetContext", %{value: "content"})

        IO.puts(
          "page: " <>
            M.js(
              s,
              ~s|return location.href + " " + document.documentElement.outerHTML.slice(0, 500) + " body=" + getComputedStyle(document.body).backgroundColor|
            )
        )

        M.call(s, "Marionette:SetContext", %{value: "chrome"})

        addon =
          M.call(s, "WebDriver:ExecuteAsyncScript", %{
            script:
              ~s|const done = arguments[arguments.length - 1];
              const { AddonManager } = ChromeUtils.importESModule("resource://gre/modules/AddonManager.sys.mjs");
              AddonManager.getAddonByID("theme@ficciones").then(a => done(a && JSON.stringify({ active: a.isActive, disabled: a.userDisabled, sig: a.signedState, perms: a.permissions, compat: a.isCompatible, err: a.appDisabled, scope: a.scope })));|,
            args: []
          })

        IO.inspect(addon, label: "addon")
        IO.puts("window: " <> M.js(s, "return document.location.href"))

        IO.puts(
          M.js(
            s,
            ~s|const e = WebExtensionPolicy.getByID("theme@ficciones").extension; return JSON.stringify({ warnings: e.warnings, errors: e.errors, privileged: e.isPrivileged, experiments: e.experimentAPIManager ? "manager" : null, keys: Object.keys(e.manifest), views: [...e.views].map(v => v.viewType) })|
          )
        )

        IO.puts(
          M.js(
            s,
            ~s|return Services.console.getMessageArray().map(m => m.message \|\| String(m)).filter(m => /ficciones\|moz-extension\|api\\.js\|background\\.js\|darkreader\|page\\.js/i.test(m)).slice(-15).join("\\n")|
          )
        )
      rescue
        d -> IO.puts("no addon state: " <> Exception.message(d))
      end

      IO.puts(String.slice(drain.(drain, ""), -3000, 3000) || "")
      1
  end

System.cmd("kill", ["#{os_pid}"])
File.rm_rf(root)
System.halt(code)
