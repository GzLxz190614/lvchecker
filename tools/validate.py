import json
import os
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

meta = json.load(open("data/meta.json", encoding="utf-8"))["entries"]
gates = json.load(open("data/gates.json", encoding="utf-8"))["gates"]
cls = json.load(open("data/classes.json", encoding="utf-8"))

print("=== 1. class 字段是否被移除（统一用 linkId）===")
txt = Path("data/gates.json").read_text(encoding="utf-8")
for old in ("songIds", "songKeys"):
    print(f"  出现 {old!r}: {txt.count(old)} 次")
print(f"  出现 'linkId': {txt.count('linkId')} 次")

print("\n=== 2. BOSS 曲（含精确难度）===")
for g in gates:
    b = g.get("boss")
    if not b:
        print(f"  {g['id']:<10} 无 BOSS")
        continue
    lv = " ".join(f"{k[:1].upper()}={v}" for k, v in b["levels"].items())
    ult = " [ULT]" if b.get("hasUltima") else ""
    print(f"  {g['id']:<10} {b['title'][:32]:<34} {b['artist'][:24]:<26} {lv}{ult}")

print("\n=== 3. 角色图片 ===")
for k, v in meta.items():
    if v["type"] == "chara":
        img = v.get("image")
        ok = img and os.path.exists(img)
        print(f"  {k} {v['title']}")
        print(f"    image = {img}  存在={ok}")
        if ok:
            from PIL import Image
            with Image.open(img) as im:
                print(f"    尺寸 = {im.size} 模式 = {im.mode}")

print("\n=== 4. 奖励页 ===")
rw = [g for g in gates if g["id"] == "reward"]
if rw:
    g = rw[0]
    print(f"  name={g['name']} kind={g['kind']} order={g['order']} stage={g['stage']}")
    print(f"  releaseStatus={g['releaseStatus']}  tracking={g['tracking']}")
    print(f"  conditionText={g['conditionText']}")
    print(f"  前置门数={len(g['prerequisites'])} -> {g['prerequisites']}")
    print(f"  BOSS={g['boss']['title']} / {g['boss']['artist']} / {g['boss']['levels']}")
else:
    print("  ✗ 没有奖励页")

print("\n=== 5. 引用完整性 ===")
bad = 0


def ck(ids, where):
    global bad
    for i in ids:
        if i not in meta:
            print("  ✗ 悬空", i, where)
            bad += 1


for g in gates:
    r = g.get("requirement", {})
    ck(r.get("songKeys", []), g["id"])
    ck(r.get("itemKeys", []), g["id"])
    for grp in r.get("groups", []):
        ck(grp["songKeys"], g["id"] + "/" + grp["key"])
    b = g.get("boss")
    if b:
        ck([b["linkId"]], g["id"] + "/boss")
for c in cls["classes"]:
    for co in c["courses"]:
        # 段位组曲的槽有三种 kind：
        #   fixed       固定曲目，有 linkId
        #   randomRange 按等级随机，只有 levelFrom/levelTo
        #   randomPool  按曲池随机，只有 poolSize
        for s in co["songs"]:
            if s.get("kind", "fixed") == "fixed":
                ck([s["linkId"]], "classes/" + co["key"])
print(f"  悬空引用: {bad}")

print("\n=== 6. 图片统计 ===")
declared = {v["image"] for v in meta.values() if v.get("image")}
missing = [i for i in declared if not os.path.exists(i)]
allpng = list(Path("assets/img").rglob("*.png"))
allpng_s = {str(p).replace("\\", "/") for p in allpng}
orphan = allpng_s - declared
print(f"  meta 声明图片: {len(declared)}   缺失: {len(missing)}")
print(f"  实际 PNG: {len(allpng)}   非主图(tex/立绘): {len(orphan)}")
print(f"  合计体积: {sum(p.stat().st_size for p in allpng)/1024/1024:.2f} MB")
