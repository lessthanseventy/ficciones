// Filesystem usage per mount, from `df` every 30 s. Pseudo filesystems are excluded at the
// source; snapper's .snapshots and the boot/efi partitions stay (they are the ones that fill).
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"

export type Mount = { target: string; fstype: string; size: number; used: number; frac: number }

const GB = 1073741824
export const gb = (b: number) => (b >= 100 * GB ? `${(b / GB).toFixed(0)}G` : b >= GB ? `${(b / GB).toFixed(1)}G` : `${(b / 1048576).toFixed(0)}M`)

export const mounts = createPoll<Mount[]>([], 30_000, async () => {
  try {
    const out = await execAsync(["df", "-B1", "--output=target,fstype,size,used", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "squashfs", "-x", "overlay", "-x", "fuse.portal"])
    const seen = new Set<string>()
    return out.trim().split("\n").slice(1).map((l) => {
      const [target, fstype, size, used] = l.trim().split(/\s+/)
      return { target, fstype, size: Number(size), used: Number(used), frac: Number(size) > 0 ? Number(used) / Number(size) : 0 }
    })
      // btrfs subvolumes share one device: the first mount of a (size,used) pair speaks for all
      .filter((m) => m.size > 0 && !seen.has(`${m.size}:${m.used}:${m.fstype}`) && seen.add(`${m.size}:${m.used}:${m.fstype}`))
      .filter((m) => !m.target.startsWith("/nix/store") && !m.target.startsWith("/run/"))
      .sort((a, b) => a.target.length - b.target.length)
      .slice(0, 8)
  } catch {
    return []
  }
})
