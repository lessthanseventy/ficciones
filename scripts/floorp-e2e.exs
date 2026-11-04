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

themes = %{"a" => {"#112233", "#ddeeff", false}, "b" => {"#f4ecdc", "#2c2a33", true}}

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

link = Path.join(config, "theme")
File.ln_s!("themes/a", link)

# over http: file:// pages never receive the content script here
html =
  ~s|<!doctype html><html><body>plain white page <a id="l" href="/x" style="color: #00f">a link</a></body></html>|

{:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
{:ok, http_port} = :inet.port(listen)
page = "http://127.0.0.1:#{http_port}/"

serve = fn serve ->
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
  serve.(serve)
end

spawn_link(fn -> serve.(serve) end)

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

s = M.connect(port_n)
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
          ~s|const done = arguments[arguments.length - 1]; window.browser.runtime.sendMessage({ host: "127.0.0.1", off: #{off} }).then(() => done(1));|,
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
