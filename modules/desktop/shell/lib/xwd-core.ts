// The pure half of the hack preview — no gi imports, so node can test it (lib/xwd-core.test.mjs).

export type XwdFrame = { offset: number; width: number; height: number; stride: number }

/** Where the pixels are in an XWD image: Xvfb's `-fbdir` screen file, ZPixmap, 32 bits a pixel,
 * least significant byte first (B G R X in memory). Null for any other layout, or a short file. */
export function xwdFrame(b: Uint8Array): XwdFrame | null {
  if (b.length < 100) return null
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength)
  const u = (i: number) => v.getUint32(i * 4) // the header is big-endian whatever the pixels are
  const [header, format, width, height, order, bpp, stride, ncolors] = [u(0), u(2), u(4), u(5), u(7), u(11), u(12), u(19)]
  if (format !== 2 || bpp !== 32 || order !== 0) return null
  const offset = header + ncolors * 12 // each colormap entry is 12 bytes
  if (b.length < offset + stride * height) return null
  return { offset, width, height, stride }
}
