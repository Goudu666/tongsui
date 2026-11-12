#!/usr/bin/env python3
"""把微缩模型线程导出的主角 glb 瘦身后放进客户端：client/art3d/figures/<role>_<stage>.glb

- 去掉法线贴图（布纹、发丝、皮肤刷痕；侧视镜头隔着两三米看不出来，占了一半多体积），只留脸的贴图；
- 去掉 KHR_materials_sheen（Godot 不认），绒面感由客户端换上的材质补；
- 除了脸，别的部件不要 UV；
- 头发（一个人五万多三角面，占全身三分之二）用二次误差减面到 HAIR_TRIS 以内，法线重算；
- 重新打包 buffer，只留还用得着的数据。

减面要 fast-simplification（pip install fast-simplification numpy），没有就报错退出。

用法：python3 tools/art/realtime3d/slim_glb.py 源目录 [目标目录]
源目录默认 /mnt/project-files/tongsui/art/diorama/real/glb（tools/art/diorama/real/make.py glb figures 的输出）。
"""
import json
import os
import struct
import sys

import numpy as np
import fast_simplification

HAIR_TRIS = 7000      # 头发减到多少三角面以内
BIG_TRIS = 6000       # 别的部件超过这么多面也减（现在都不到）

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


def _acc_array(j, binary, ai):
    a = j["accessors"][ai]
    v = j["bufferViews"][a["bufferView"]]
    comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a["componentType"]]
    start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = v.get("byteStride", 0)
    item = np.dtype(dt).itemsize * comps
    if stride and stride != item:
        raw = np.frombuffer(binary, np.uint8, count=stride * a["count"], offset=start).reshape(a["count"], stride)[:, :item]
        return np.frombuffer(raw.tobytes(), dt).reshape(a["count"], comps)
    return np.frombuffer(binary, dt, count=a["count"] * comps, offset=start).reshape(a["count"], comps)


def _append(j, blob, data, target, acc):
    blob.extend(b"\0" * (-len(blob) % 4))
    j["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
    blob.extend(data)
    acc["bufferView"] = len(j["bufferViews"]) - 1
    j["accessors"].append(acc)
    return len(j["accessors"]) - 1


def decimate(j, binary):
    """面太多的部件（头发）减面：每个 primitive 单独焊点、减面、重算平滑法线，写成新的 accessor。"""
    blob = bytearray(binary)
    hair_mats = {i for i, m in enumerate(j.get("materials", [])) if m.get("name") == "hair"}
    for mesh in j["meshes"]:
        for pr in mesh["primitives"]:
            if "indices" not in pr:
                continue
            idx = _acc_array(j, binary, pr["indices"]).reshape(-1, 3).astype(np.int64)
            limit = HAIR_TRIS if pr.get("material") in hair_mats else BIG_TRIS
            if len(idx) <= limit:
                # 小部件却挂在一大块共用的顶点上（头绳挂在头发的顶点里）：只留自己用到的顶点
                count = j["accessors"][pr["attributes"]["POSITION"]]["count"]
                used = np.unique(idx)
                if len(used) * 2 < count:
                    remap = np.zeros(count, np.int64)
                    remap[used] = np.arange(len(used))
                    attrs = {}
                    for k, ai in pr["attributes"].items():
                        arr = np.ascontiguousarray(_acc_array(j, binary, ai)[used])
                        acc = {kk: vv for kk, vv in j["accessors"][ai].items() if kk not in ("bufferView", "byteOffset", "min", "max")}
                        acc["count"] = len(used)
                        if k == "POSITION":
                            acc["min"] = arr.min(0).tolist()
                            acc["max"] = arr.max(0).tolist()
                        attrs[k] = _append(j, blob, arr.tobytes(), 34962, acc)
                    pr["attributes"] = attrs
                    pr["indices"] = _append(j, blob, remap[idx].astype(np.uint16).reshape(-1).tobytes(), 34963,
                                            {"componentType": 5123, "count": int(idx.size), "type": "SCALAR"})
                continue
            pos = _acc_array(j, binary, pr["attributes"]["POSITION"]).astype(np.float64)
            used = np.unique(idx)
            # 焊点：同一位置的顶点（硬边拆开的）并成一个，减面时不撕开
            key = np.round(pos[used] * 1e5).astype(np.int64)
            _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
            remap = np.zeros(pos.shape[0], np.int64)
            remap[used] = inv.reshape(-1)
            pts = pos[used][first]
            faces = remap[idx]
            faces = faces[(faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 0] != faces[:, 2])]
            red = 1.0 - limit / len(faces)
            p2, f2 = fast_simplification.simplify(pts.astype(np.float32), faces.astype(np.int32), target_reduction=red, agg=5)
            p2 = np.asarray(p2, np.float64)
            f2 = np.asarray(f2, np.int64)
            # 平滑法线（按面积加权）；glTF 正面逆时针
            fn = np.cross(p2[f2[:, 1]] - p2[f2[:, 0]], p2[f2[:, 2]] - p2[f2[:, 0]])
            vn = np.zeros_like(p2)
            for k in range(3):
                np.add.at(vn, f2[:, k], fn)
            vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
            p32 = p2.astype(np.float32)
            n32 = vn.astype(np.float32)
            pa = _append(j, blob, p32.tobytes(), 34962, {"componentType": 5126, "count": len(p32), "type": "VEC3",
                                                         "min": p32.min(0).tolist(), "max": p32.max(0).tolist()})
            na = _append(j, blob, n32.tobytes(), 34962, {"componentType": 5126, "count": len(n32), "type": "VEC3"})
            it = np.uint16 if len(p32) < 65535 else np.uint32
            ia = _append(j, blob, f2.astype(it).reshape(-1).tobytes(), 34963,
                         {"componentType": 5123 if it == np.uint16 else 5125, "count": int(f2.size), "type": "SCALAR"})
            pr["attributes"] = {"POSITION": pa, "NORMAL": na}
            pr["indices"] = ia
            print(f"    减面 {mesh.get('name', '?')}：{len(idx)} → {len(f2)} 三角")
    j["buffers"][0]["byteLength"] = len(blob)
    return j, bytes(blob)


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
            j, b = slim(*decimate(*read_glb(src)))
            dst = os.path.join(DST, f"{role}_{st}.glb")
            write_glb(dst, j, b)
            sz = os.path.getsize(dst)
            total += sz
            print(f"{role}_{st}: {os.path.getsize(src) / 1e6:.2f} MB → {sz / 1e6:.2f} MB")
    print(f"一共 {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
