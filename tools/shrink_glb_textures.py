"""Shrinks the textures embedded in .glb files (e.g. to 256x256).

    python3 tools/shrink_glb_textures.py models/characters 256

Needs Pillow. Rebuilds each file's binary chunk with the smaller images.
"""
import io
import json
import struct
import sys
from pathlib import Path

from PIL import Image


def pad4(b, fill=b"\0"):
    return b + fill * ((4 - len(b) % 4) % 4)


def shrink(path, size):
    data = path.read_bytes()
    jlen = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + jlen])
    bin_start = 20 + jlen + 8
    blob = data[bin_start:]
    views = gltf["bufferViews"]
    chunks = [blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]] for v in views]
    for img in gltf.get("images", []):
        if "bufferView" not in img:
            continue
        i = img["bufferView"]
        pic = Image.open(io.BytesIO(chunks[i]))
        if max(pic.size) > size:
            pic = pic.resize((size, size), Image.LANCZOS)
            out = io.BytesIO()
            pic.save(out, "PNG", optimize=True)
            chunks[i] = out.getvalue()
            img["mimeType"] = "image/png"
    new_bin = b""
    for v, c in zip(views, chunks):
        v["byteOffset"] = len(new_bin)
        v["byteLength"] = len(c)
        new_bin += pad4(c)
    gltf["buffers"][0]["byteLength"] = len(new_bin)
    j = pad4(json.dumps(gltf, separators=(",", ":")).encode(), b" ")
    total = 12 + 8 + len(j) + 8 + len(new_bin)
    path.write_bytes(
        struct.pack("<III", 0x46546C67, 2, total)
        + struct.pack("<II", len(j), 0x4E4F534A) + j
        + struct.pack("<II", len(new_bin), 0x004E4942) + new_bin)
    print(f"{path.name}: {len(data) // 1024} KB -> {total // 1024} KB")


if __name__ == "__main__":
    folder, size = Path(sys.argv[1]), int(sys.argv[2])
    for p in sorted(folder.glob("*.glb")):
        shrink(p, size)
