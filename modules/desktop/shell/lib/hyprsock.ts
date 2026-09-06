// Hyprland's request socket, spoken directly: `query("cursorpos")` without spawning hyprctl.
import Gio from "gi://Gio?version=2.0"
import GLib from "gi://GLib?version=2.0"

const path = `${GLib.getenv("XDG_RUNTIME_DIR")}/hypr/${GLib.getenv("HYPRLAND_INSTANCE_SIGNATURE")}/.socket.sock`

export function query(cmd: string): string {
  const client = new Gio.SocketClient()
  const conn = client.connect(new Gio.UnixSocketAddress({ path }), null)
  const out = conn.get_output_stream()
  out.write_all(new TextEncoder().encode(cmd), null)
  const inp = new Gio.DataInputStream({ base_stream: conn.get_input_stream() })
  let s = ""
  for (;;) {
    const bytes = inp.read_bytes(4096, null)
    if (bytes.get_size() === 0) break
    s += new TextDecoder().decode(bytes.get_data()!)
  }
  conn.close(null)
  return s
}
