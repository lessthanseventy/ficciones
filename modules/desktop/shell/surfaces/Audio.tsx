// The audio switcher, off the bar's VOL cell. OUTPUT and INPUT list devices with the default
// chipped (click sets it); the master slider drives the default speaker; APPS lists every
// playing stream with its own slider, mute, and a button that cycles its output device.
import Gtk from "gi://Gtk?version=4.0"
import Pango from "gi://Pango?version=1.0"
import Wp from "gi://AstalWp"
import { For, createBinding, createComputed } from "ags"
import { Panel, RuleH } from "../lib/tui"
import { pct } from "../lib/format"

const short = (s: string, n = 28) => (s.length > n ? s.slice(0, n - 1) + "…" : s)

function Slider({ node, width = 220 }: { node: Wp.Node; width?: number }) {
  return (
    <slider
      cssClasses={["vol"]}
      widthRequest={width}
      hexpand
      value={createBinding(node, "volume")}
      onChangeValue={({ value }) => { if (Math.abs(value - node.volume) > 0.005) node.set_volume(value) }}
    />
  )
}

function Device({ ep }: { ep: Wp.Endpoint }) {
  const isDefault = createBinding(ep, "isDefault")
  return (
    <button cssClasses={isDefault((d) => ["row", ...(d ? ["chip"] : [])])} onClicked={() => ep.set_is_default(true)}>
      <box spacing={8}>
        <label label={createBinding(ep, "description")((d) => short(d ?? ""))} hexpand xalign={0} ellipsize={Pango.EllipsizeMode.END} />
        <label cssClasses={["dim"]} label={createBinding(ep, "volume")(pct)} />
      </box>
    </button>
  )
}

function Stream({ st, speakers }: { st: Wp.Stream; speakers: () => Wp.Endpoint[] }) {
  const name = st.get_pw_property("application.name") || st.description || st.name || "app"
  const media = st.get_pw_property("media.name") ?? ""
  const mute = createBinding(st, "mute")
  const target = createBinding(st, "targetSerial")((serial) => {
    const ep = speakers().find((s) => s.serial === serial) ?? st.targetEndpoint
    return short(ep?.description ?? "default", 14)
  })
  const cycle = () => {
    const sp = speakers()
    if (!sp.length) return
    const i = sp.findIndex((s) => s.serial === st.targetSerial)
    st.targetSerial = sp[(i + 1) % sp.length].serial
  }
  return (
    <box cssClasses={["stream"]} orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      <box spacing={8}>
        <label cssClasses={["app"]} label={short(name, 18)} xalign={0} />
        <label cssClasses={["dim", "sm"]} label={short(media, 30)} hexpand xalign={0} ellipsize={Pango.EllipsizeMode.END} />
        <button cssClasses={["act"]} onClicked={cycle} tooltipText="output: click to cycle"><label label={target} /></button>
        <button cssClasses={mute((m) => ["act", ...(m ? ["red"] : [])])} onClicked={() => (st.mute = !st.mute)}>
          <label label={mute((m) => (m ? "muted" : "mute"))} />
        </button>
      </box>
      <box spacing={8}>
        <Slider node={st} />
        <label cssClasses={["dim"]} label={createBinding(st, "volume")(pct)} widthChars={4} xalign={1} />
      </box>
    </box>
  )
}

export default function Audio() {
  const wp = Wp.get_default()!
  const audio = wp.audio
  const speakers = createBinding(audio, "speakers")
  const mics = createBinding(audio, "microphones")
  const streams = createBinding(audio, "streams")
  // The default-speaker endpoint object is stable across default changes in AstalWp (it is
  // the "default" pseudo-node), so bind its fields rather than the object.
  const speaker = wp.defaultSpeaker!
  const sDesc = createBinding(speaker, "description")
  const sMute = createBinding(speaker, "mute")
  const sVol = createBinding(speaker, "volume")

  return (
    <box orientation={Gtk.Orientation.VERTICAL} widthRequest={420}>
      <Panel title="OUTPUT" spacing={2}>
        <box cssClasses={["row"]} spacing={8}>
          <label label={sDesc((d) => short(d ?? "no output"))} hexpand xalign={0} ellipsize={Pango.EllipsizeMode.END} />
          <button cssClasses={sMute((m) => ["act", ...(m ? ["red"] : [])])} onClicked={() => (speaker.mute = !speaker.mute)}>
            <label label={sMute((m) => (m ? "muted" : "mute"))} />
          </button>
        </box>
        <box spacing={8}>
          <Slider node={speaker} />
          <label cssClasses={["dim"]} label={sVol(pct)} widthChars={4} xalign={1} />
        </box>
        <RuleH />
        <For each={speakers}>{(ep) => <Device ep={ep} />}</For>
      </Panel>
      <Panel title="INPUT" spacing={2}>
        <For each={mics}>{(ep) => <Device ep={ep} />}</For>
        <label cssClasses={["dim"]} label="no input" visible={mics((m) => m.length === 0)} xalign={0} />
      </Panel>
      <Panel title="APPS" spacing={6}>
        <For each={streams}>{(st) => <Stream st={st} speakers={() => audio.get_speakers()} />}</For>
        <label cssClasses={["dim"]} label="nothing playing" visible={streams((s) => s.length === 0)} xalign={0} />
      </Panel>
    </box>
  )
}
