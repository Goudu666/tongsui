#!/usr/bin/env python3
"""把微缩模型线程导出的主角 glb 瘦身后放进客户端：client/art3d/figures/<role>_<stage>.glb

- 去掉法线贴图（布纹、发丝、皮肤刷痕；侧视镜头隔着两三米看不出来，占了一半多体积），只留脸的贴图；
- 去掉 KHR_materials_sheen（Godot 不认），绒面感由客户端换上的材质补；
- 除了脸，别的部件不要 UV；
- 重新打包 buffer，只留还用得着的数据。

用法：python3 tools/art/realtime3d/slim_glb.py 源目录 [目标目录]
源目录默认 /mnt/project-files/tongsui/art/diorama/real/glb（tools/art/diorama/real/make.py glb figures 的输出）。
"""
import json
import os
import struct
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "/mnt/project-files/tongsui/art/diorama/real/glb"
DST = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "../../../client/art3d/figures")


def read_glb(path):
    b = open(path, "rb").read()
    assert b[:4] == b"glTF"
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", b[off:off + 4])[0]
    return j, b[off + 8:off + 8 + bl]


def write_glb(path, j, binary):
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, total))
        f.write(struct.pack("<I", len(js)) + b"JSON" + js)
        f.write(struct.pack("<I", len(binary)) + b"BIN\0" + binary)


def slim(j, binary):
    face_mats = set()
    for i, m in enumerate(j.get("materials", [])):
        m.pop("normalTexture", None)
        ext = m.get("extensions", {})
        ext.pop("KHR_materials_sheen", None)
        if not ext:
            m.pop("extensions", None)
        if "baseColorTexture" in m.get("pbrMetallicRoughness", {}):
            face_mats.add(i)
    for mesh in j["meshes"]:
        for pr in mesh["primitives"]:
            if pr.get("material") not in face_mats:
                for k in [k for k in pr["attributes"] if k.startswith("TEXCOORD")]:
                    del pr["attributes"][k]
    # 还用得着的贴图
    used_tex = sorted({m["pbrMetallicRoughness"]["baseColorTexture"]["index"] for i, m in enumerate(j["materials"]) if i in face_mats})
    tex_map = {o: n for n, o in enumerate(used_tex)}
    textures = [j["textures"][o] for o in used_tex]
    used_img = sorted({t["source"] for t in textures})
    img_map = {o: n for n, o in enumerate(used_img)}
    for t in textures:
        t["source"] = img_map[t["source"]]
    images = [j["images"][o] for o in used_img]
    for m in j["materials"]:
        bct = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if bct:
            bct["index"] = tex_map[bct["index"]]
    j["textures"], j["images"] = textures, images
    if not textures:
        for k in ("textures", "images", "samplers"):
            j.pop(k, None)
    # 还用得着的 accessor
    used_acc = set()
    for mesh in j["meshes"]:
        for pr in mesh["primitives"]:
            used_acc.update(pr["attributes"].values())
            if "indices" in pr:
                used_acc.add(pr["indices"])
    acc_order = sorted(used_acc)
    acc_map = {o: n for n, o in enumerate(acc_order)}
    accessors = [j["accessors"][o] for o in acc_order]
    for mesh in j["meshes"]:
        for pr in mesh["primitives"]:
            pr["attributes"] = {k: acc_map[v] for k, v in pr["attributes"].items()}
            if "indices" in pr:
                pr["indices"] = acc_map[pr["indices"]]
    # 重新打包 bufferView
    views = []
    out = bytearray()
    view_map = {}

    def take(old):
        if old in view_map:
            return view_map[old]
        v = dict(j["bufferViews"][old])
        start = v.get("byteOffset", 0)
        data = binary[start:start + v["byteLength"]]
        out.extend(b"\0" * (-len(out) % 4))
        v["byteOffset"] = len(out)
        v["buffer"] = 0
        out.extend(data)
        view_map[old] = len(views)
        views.append(v)
        return view_map[old]

    index_accs = {pr["indices"] for mesh in j["meshes"] for pr in mesh["primitives"] if "indices" in pr}
    for n, a in enumerate(accessors):
        if n in index_accs and a["componentType"] == 5125:
            # 顶点不到 65536 个：下标换成 16 位
            v = j["bufferViews"][a["bufferView"]]
            st = v.get("byteOffset", 0) + a.get("byteOffset", 0)
            idx = struct.unpack("<%dI" % a["count"], binary[st:st + 4 * a["count"]])
            if max(idx) < 65535:
                out.extend(b"\0" * (-len(out) % 4))
                data = struct.pack("<%dH" % a["count"], *idx)
                views.append({"buffer": 0, "byteOffset": len(out), "byteLength": len(data), "target": 34963})
                out.extend(data)
                a["bufferView"] = len(views) - 1
                a["componentType"] = 5123
                a.pop("byteOffset", None)
                continue
        a["bufferView"] = take(a["bufferView"])
    for im in images:
        im["bufferView"] = take(im["bufferView"])
    j["accessors"], j["bufferViews"] = accessors, views
    j["buffers"] = [{"byteLength": len(out) + (-len(out) % 4)}]
    used = set()
    for m in j["materials"]:
        used.update(m.get("extensions", {}).keys())
    if used:
        j["extensionsUsed"] = sorted(used)
    else:
        j.pop("extensionsUsed", None)
    j.pop("extensionsRequired", None)
    return j, bytes(out)


def main():
    os.makedirs(DST, exist_ok=True)
    total = 0
    for role in ("qing", "mei"):
        for st in ("child", "teen", "young", "middle", "old"):
            src = os.path.join(SRC, f"{role}_{st}.glb")
            j, b = slim(*read_glb(src))
            dst = os.path.join(DST, f"{role}_{st}.glb")
            write_glb(dst, j, b)
            sz = os.path.getsize(dst)
            total += sz
            print(f"{role}_{st}: {os.path.getsize(src) / 1e6:.2f} MB → {sz / 1e6:.2f} MB")
    print(f"一共 {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
