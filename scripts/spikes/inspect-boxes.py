# Reports, without printing any value, whether the boxes of an MP4 file contain identifying data:
# for every box, its size, the number of nonzero and printable bytes, and the number of occurrences
# of the purchaser's account and owner strings taken from the item list. Item values are never printed.
# With a second file, the strings taken from FILE are counted in SEARCH-IN instead, which checks a
# cleaned copy against its source.
# Usage: python3 -I inspect-boxes.py FILE [SEARCH-IN]
import struct, sys
data = open(sys.argv[1], 'rb').read()
containers = {b'moov', b'trak', b'mdia', b'minf', b'stbl', b'udta', b'edts', b'dinf', b'ilst', b'pinf', b'schi', b'sinf'}
def walk(start, end, depth, parent, out):
    o = start
    while o + 8 <= end:
        size, kind = struct.unpack('>I4s', data[o:o+8]); h = 8
        if size == 1: size = struct.unpack('>Q', data[o+8:o+16])[0]; h = 16
        if size == 0: size = end - o
        if size < 8 or o + size > end: break
        out.append((depth, kind, o, size, h, parent))
        body = o + h
        if kind in containers or parent == b'ilst': walk(body, o + size, depth + 1, kind, out)
        elif kind == b'meta': walk(body + 4, o + size, depth + 1, kind, out)
        elif kind == b'stsd': walk(body + 8, o + size, depth + 1, kind, out)
        elif parent == b'stsd' and kind == b'mp4a': walk(body + 28, o + size, depth + 1, kind, out)
        o += size
boxes = []; walk(0, len(data), 0, None, boxes)
def item(key):
    for d, k, o, s, h, p in boxes:
        if k == key and p == b'ilst':
            inner = data[o+h:o+s]
            return inner[16:]  # data box header (8) + type (4) + locale (4)
    return None
secrets = {n: v for n, v in (('account', item(b'apID')), ('owner', item(b'ownr'))) if v}
for d, k, o, s, h, p in boxes:
    if p == b'ilst': continue
    body = data[o+h:o+s]
    nonzero = sum(1 for b in body if b) if len(body) < 2_000_000 else -1
    printable = sum(1 for b in body if 32 <= b < 127)
    hits = {n: body.count(v) for n, v in secrets.items() if k != b'mdat'}
    hits = {n: c for n, c in hits.items() if c}
    if k in (b'mdat',): nonzero = 'skipped'
    print(f"{'  '*d}{k.decode('latin-1')} size {s} nonzero {nonzero} printable {printable} {'contains '+str(hits) if hits else ''}")
print('identifying strings found in item list:', ', '.join(secrets) or 'none')
searched = open(sys.argv[2], 'rb').read() if len(sys.argv) > 2 else data
total = {n: searched.count(v) for n, v in secrets.items()}
print('occurrences in', 'the second file:' if len(sys.argv) > 2 else 'the whole file:', total)
