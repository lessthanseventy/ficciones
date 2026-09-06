// Wifi signal strength history, sampled from AstalNetwork every 2 s — the NET card's sparkline.
import Network from "gi://AstalNetwork"
import { createPoll } from "ags/time"

const HIST = 60
const hist: number[] = []
export const wifiHist = createPoll<number[]>(hist, 2000, () => {
  const w = Network.get_default().wifi
  const s = w?.ssid ? (w.strength ?? 0) / 100 : 0
  hist.push(s); if (hist.length > HIST) hist.shift()
  return [...hist]
})
