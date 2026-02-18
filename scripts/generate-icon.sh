#!/usr/bin/env bash
# Generate Vox app icon — run on macOS (uses sips for resizing)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_DIR="${1:-${SCRIPT_DIR}/../VoxApp/Sources/Assets.xcassets/AppIcon.appiconset}"
mkdir -p "${ICON_DIR}"

# Generate 1024x1024 base icon with Python
python3 -c "
import struct, zlib, math

def png(w, h, px):
    def c(t, d):
        x = t + d
        return struct.pack('>I', len(d)) + x + struct.pack('>I', zlib.crc32(x) & 0xffffffff)
    raw = b''
    for y in range(h):
        raw += b'\x00'
        raw += bytes(px[y*w*4:(y+1)*w*4])
    return b'\x89PNG\r\n\x1a\n' + c(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + c(b'IDAT', zlib.compress(raw, 6)) + c(b'IEND', b'')

S = 1024
px = bytearray(S*S*4)
cx = cy = S/2
m = S*0.08
inner = S - 2*m
cr = S*0.18

for y in range(S):
    for x in range(S):
        i = (y*S+x)*4
        rx = abs(x-cx) - (inner/2-cr)
        ry = abs(y-cy) - (inner/2-cr)
        ok = True
        if rx > 0 and ry > 0: ok = math.sqrt(rx*rx+ry*ry) <= cr
        elif rx > cr or ry > cr: ok = False
        if not ok:
            continue
        t = (y-m)/inner if inner > 0 else 0
        bg = (int(40+t*25), int(8+t*18), int(110+t*50))

        # Waveform bars
        bc = 7
        tw = S*0.55
        bw = tw/bc*0.65
        bg2 = tw/bc*0.35
        sx = cx - tw/2
        hs = [0.20, 0.35, 0.55, 0.70, 0.50, 0.30, 0.18]
        drawn = False
        for j in range(bc):
            bcx = sx + j*(bw+bg2) + bw/2
            bh = inner*hs[j]/2
            if abs(x-bcx) <= bw/2 and abs(y-cy) <= bh:
                bt = j/(bc-1)
                # Round the tops of bars
                if abs(y-cy) > bh - bw/2:
                    dy = abs(y-cy) - (bh - bw/2)
                    dx = abs(x-bcx)
                    if dx*dx + dy*dy > (bw/2)*(bw/2):
                        break
                px[i] = int(0+bt*60)
                px[i+1] = int(210-bt*20)
                px[i+2] = int(255-bt*80)
                px[i+3] = 255
                drawn = True
                break
        if not drawn:
            px[i], px[i+1], px[i+2], px[i+3] = bg[0], bg[1], bg[2], 255

with open('${ICON_DIR}/icon_1024.png', 'wb') as f:
    f.write(png(S, S, px))
print('base icon done')
"

# Resize to all needed sizes using sips (macOS)
for s in 512 256 128 64 32 16; do
    sips -z $s $s "${ICON_DIR}/icon_1024.png" --out "${ICON_DIR}/icon_${s}.png" >/dev/null 2>&1
    echo "  ${s}x${s} ✓"
done

echo "✅ All icons generated"
