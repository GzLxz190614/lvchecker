# lvchecker · 连章进度

《中二节奏 2027》**连章（Linked VERSE）**门解锁进度记录工具。

用来解决一个问题：**「这门还差哪几首歌没打？」**

站在机台前翻菜单找歌很不方便，还容易忘记哪首打过。这个 app 把每个门需要的曲目/角色/服装列成卡片，打过的点一下勾掉，自动记住进度。

> ⚠️ **当前状态：数据层已完成（M0），App 尚未构建（M1 进行中）。**
> 现在仓库里是数据与资源，还没有可安装的 APK。进度见下方「开发进度」。

---

## 这是什么

| | |
|---|---|
| **只做国服** | 中二节奏 2027（CN1.40，2026-09-10 稼働）。不做日服/亚服 |
| **只记录解锁条件** | 不记录打 BOSS 的成败 |
| **完全离线** | 数据内置，联网只在你主动同步/导入时发生 |
| **进度只存本机** | 你的打勾记录永远不上传 |
| **自用 + 朋友用** | 不上架商店 |

### 覆盖的门（14 页）

| # | 门 | 解锁条件 |
|---|---|---|
| 1 | ORIGIN | 更新后把 30 首各打一次 |
| 2 | AIR | 获得一个段位缎带（任一 CLASS 内所有组曲通关） |
| 3 | STAR | 角色 観音寺 にこる／Mermaid♡Moment 升到 RANK 15 |
| 4 | AMAZON | Climax + Killing Rhythm 加收藏后各打一次 |
| 5 | CRYSTAL | ⚠️ 国服条件未知（日服需队伍功能，国服无） |
| 6 | PARADISE | 5 位曲师各打一首（最少 5 首） |
| 7 | NEW | 获得 3 件「淀川 沙音瑠」服装并穿上 |
| 8 | SUN | 更新后把 5 首各打一次 |
| 9 | LUMINOUS | 集 100 气球 → 解锁隐藏地图 → 跑完 |
| 10 | VERSE | 从推荐乐曲文件夹打 3 首一次 |
| 11 | X-VERSE | 通关前面 10 个门后自动解锁 |
| 12 | RE:VERSE | 通关 X-VERSE → 跑完 Secret AREA: MUSIC GAME EX 拿全 11 首 |
| 13 | UNIVERSE | 通关 RE:VERSE 时剩余血量 ≥ 指定血量 |
| 14 | **奖励乐曲** | Linked Tune，全部门通关后显示 |

---

## 仓库结构

```
lvchecker/
├── data/                  ← 在线同步的源（raw 直链指向这里）
│   ├── meta.json          81 个条目的元数据（曲名/曲师/图片路径/难度）
│   ├── gates.json         14 页的完整定义
│   ├── linklevels.json    Link LEVEL 缓和配置 + 判定色
│   └── classes.json       AIR 段位课程（当前为占位符）
├── assets/
│   └── img/               82 张 PNG（曲绘 / 角色立绘 / 服装）
│       ├── music/{id}/    jacket.png + meta.json
│       ├── chara/{id}/    image.png + meta.json
│       └── avatar/{id}/   icon.png + tex.png + meta.json
├── tools/                 ← 只在本地跑，不进 APK
│   ├── build.py           从 condition/ 生成 data/ 与 assets/img/
│   ├── preview.py         生成验收预览图（本地用）
│   └── validate.py        数据完整性校验
├── DESIGN.md              设计文档（数据模型 / UI / CI / 全部决策）
└── .gitignore
```

**未纳入版本控制的目录**（见 `.gitignore`）：

| 目录 | 为什么不提交 |
|---|---|
| `condition/` | 从游戏解包出来的原始资源（谱面 `.c2s`、曲绘与立绘 `.dds`、定义 `.xml`）。**美术与谱面资源版权属于 SEGA，不适合在公开仓库二次分发。** |
| `preview/` | 本地验收预览图，可用 `tools/preview.py` 随时重新生成 |

所以本仓库只提交**派生结果**：`data/`（元数据 JSON）与 `assets/img/`（从 `.dds` 转出的 PNG）。
两者都是为「记录进度」这一用途所必需的最小集合。

**M1 之后**会加入 `lib/`（Flutter 源码）、`android/`、`pubspec.yaml`、`.github/workflows/build-apk.yml`。

---

## 数据说明

### 数据来源

| 来源 | 用途 |
|---|---|
| `condition/` 目录（**未提交，仅本地**） | 曲目、曲师、难度、曲绘、角色、服装、地图 |
| [RemyWiki](https://silentblue.remywiki.com/CHUNITHM:Linked_VERSE) | 条件文本交叉核对 |
| [SEGA 官方情报](https://info-chunithm.sega.jp/12052/) | 日服官方条件表 |
| 落雪查分器 | **可选**成绩导入（见下） |

> ⚠️ `condition/` 是从游戏解包出来的原始资源，**版权属于 SEGA，未纳入本仓库**。
> 本仓库提交的是转换后的结果（`data/` 与 `assets/img/`），供记录解锁进度这一用途使用。

### `meta.json` 的 `linkId` 体系

`gates.json` **不重复存曲名**，只用 `linkId` 引用 `meta.json`：

```jsonc
// gates.json
"requirement": { "type": "playAll", "songKeys": ["music:51", "music:53", ...] }

// meta.json
"music:51": {
  "type": "music", "id": 51,
  "title": "My First Phone", "artist": "cubesato",
  "levels": { "basic": "2", "advanced": "6", "expert": "10", "master": "14" },
  "image": "assets/img/music/51/jacket.png"
}
```

- `"id": 51` 是**落雪查分器的 song_id**，导入功能用它匹配成绩
- `linkId` 格式：`music:{id}` / `chara:{id}` / `avatar:{id}` / `mission:{id}` / `map:{id}`
- 同一首曲被多个门引用时**只存一份**（例如 `music:180` 同属 ORIGIN 和 PARADISE）

### 重新生成数据

> ⚠️ 这一步**需要本地的 `condition/` 目录**（未提交到仓库）。
> 如果没有，`build.py` 会直接退出并提示，**不会破坏已有的 `data/`**。

替换或更新 `condition/` 后：

```bash
pip install Pillow fontTools
python tools/build.py      # 重新生成 data/ 与 assets/img/
python tools/validate.py   # 校验完整性
python tools/preview.py    # 生成预览图到 preview/（本地用，不入库）
```

`build.py` 会自动：解析 XML → 生成 JSON → 把 `.dds` 转成 PNG → 按 ID 归档 → 写 `meta.json`。

---

## 关于落雪查分器导入（可选，M4）

app 支持从[落雪查分器](https://maimai.lxns.net/)导入成绩，**辅助判断哪几首已经打过**。

### 重要限制：不能全自动

查分器的 `scores` 接口是**每谱面汇总后的成绩**，实测 **ORIGIN 的 30 首里有 21 首完全没有游玩时间信息**，所以：

- ✅ 能判断「**从未打过**」
- ❌ **不能**可靠判断「更新后是否打过」

因此 app 的策略是：

1. 只检查**门要求的那些歌**，其他歌一概不管
2. 结果分三态：`确认已达成` / `确认未达成` / **`无法判断`**
3. 全部检查完后**一次性弹窗**列出「无法判断」的曲子，由你手动确认
4. **绝不**把「无法判断」的自动打勾

**手动打勾始终是唯一可信来源。**

### 密钥安全

| 规则 | 说明 |
|---|---|
| 用**个人 API 密钥**（[账号详情页](https://maimai.lxns.net/user/profile)生成） | 不是开发者密钥 |
| **不进 APK、不进仓库、不进 CI** | 每个用户填自己的 |
| 只在点击「从查分器获取数据」时弹窗索要 | 不预填 |
| 用 `EncryptedSharedPreferences` 加密存储 | 设置页可一键清除 |
| 日志永远打码 | |

> ⚠️ **不要把你的密钥提交到任何仓库或贴到聊天里。**
> 仓库根目录的 `lx_test.txt`（个人成绩导出）已被 `.gitignore` 排除，不要取消。

---

## 在线数据更新

数据文件通过 `raw.githubusercontent.com` 同步，**不用重发 APK 就能更新数据**：

```
https://raw.githubusercontent.com/GzLxz190614/lvchecker/main/data/meta.json
https://raw.githubusercontent.com/GzLxz190614/lvchecker/main/data/gates.json
https://raw.githubusercontent.com/GzLxz190614/lvchecker/main/data/linklevels.json
https://raw.githubusercontent.com/GzLxz190614/lvchecker/main/data/classes.json
```

app 启动时后台尝试同步（失败则用本地缓存，首次运行用 APK 内置副本），
设置页也有「立即同步数据」按钮。

**同步永远不会碰你的打勾记录**——数据更新和进度存档是完全隔离的两层。

---

## 开发进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| **M0** | 数据生成脚本 + `data/*.json` + 图片资源 | ✅ **完成** |
| **M1** | Flutter 工程 + ORIGIN 门 + 打勾存档 + 翻页 | ⬜ 待开始 |
| M2 | 其余 12 个门 | ⬜ |
| M3 | 在线同步 + 设置页 | ⬜ |
| M4 | 落雪导入 | ⬜ |
| M5 | AIR 段位 UI（等课程 XML） | ⬜ 待数据 |
| M6 | 曲绘接入各卡片 | ⬜ |

M0 验收材料由 `tools/preview.py` 生成到 `preview/`（**本地目录，不入库**）：
`gates_overview.png`（14 页总览）、`page_origin.png`、`page_paradise.png`、`page_star.png`、`page_reward.png`。

### 已知缺口

| 缺口 | 影响 | 应对 |
|---|---|---|
| **段位课程数据缺失** | AIR 门的段位 UI 无数据 | 先用占位符，UI 框架留好；拿到 XML 后重跑脚本即可，**不用重发 APK** |
| 国服门开放日期未知（除 ORIGIN/AIR） | 日期判断 | 显示「未更新」，**不猜日期** |
| 国服缓和日期表未知 | 无法自动算当前 Link LEVEL | 用户手动选等级；JSON 留 `null` 等填 |
| CRYSTAL 条件未知 | 无法给准确条件 | 标「条件待确认」+ 手动确认 |

---

## 参考来源

- [RemyWiki — 中二节奏 2027 (China)](https://silentblue.remywiki.com/CHUNITHM:2027_(China))
- [RemyWiki — Linked VERSE](https://silentblue.remywiki.com/CHUNITHM:Linked_VERSE)
- [SEGA 官方 — Linked VERSE のゲート解放条件](https://info-chunithm.sega.jp/12052/)
- [落雪查分器 — 开发者入驻指南](https://maimai.lxns.net/docs/developer-guide)
- [落雪查分器 — 中二节奏 API 文档](https://maimai.lxns.net/docs/api/chunithm)

完整设计决策（数据模型、UI 规范、CI 配置、踩过的坑）见 [`DESIGN.md`](DESIGN.md)。
