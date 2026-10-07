"""Generate fixed 29-point clipboard icons without external packages."""
import pathlib, struct, zlib

def generate(path, scale):
    size = 29 * scale
    rows = bytearray()
    for py in range(size):
        rows.append(0)
        for px in range(size):
            x, y = (px + .5) / scale, (py + .5) / scale
            dx, dy = max(4 - x, 0, x - 25), max(4 - y, 0, y - 25)
            alpha = 255 if dx * dx + dy * dy <= 16 else 0
            rgb = (25, int(120 + y * 2), 230)
            paper = 8 <= x <= 21 and 7 <= y <= 24
            clip = 11 <= x <= 18 and 5 <= y <= 10
            line = 11 <= x <= 18 and (13 <= y <= 14.3 or 17 <= y <= 18.3 or 21 <= y <= 22)
            if paper or clip: rgb = (255, 255, 255)
            if line: rgb = (25, 150, 230)
            rows.extend((*rgb, alpha))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))

if __name__ == '__main__':
    root = pathlib.Path(__file__).resolve().parents[1] / 'Preferences' / 'Resources'
    for scale in (1, 2, 3):
        generate(root / ('Icon' + (f'@{scale}x' if scale > 1 else '') + '.png'), scale)
