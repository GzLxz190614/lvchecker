# 连章进度（lvchecker）设计文档

> 给国服《中二节奏 2027》的连章（Linked VERSE）门解锁进度记录工具。
>
> **本文档是讨论稿，尚未开始写代码。**
>
> 文档版本：**v0.2**（已吸收 2026-09-11 第三轮反馈） ｜ 目标版本：中二节奏 2027（CN1.40，2026-09-10 稼働）

---

## 目录

1. [项目定位与范围](#1-项目定位与范围)
2. [已核实的事实](#2-已核实的事实)
3. [总体架构](#3-总体架构)
4. [数据模型](#4-数据模型)
5. [十三个门的数据](#5-十三个门的数据)
6. [通关条件缓和（Link LEVEL / Class）配置设计](#6-通关条件缓和配置设计)
7. [AIR 门：段位（CLASS）数据](#7-air-门段位class数据结构)
8. [落雪查分器导入](#8-落雪查分器导入)
9. [在线数据同步](#9-在线数据同步)
10. [UI 设计](#10-ui-设计)
11. [GitHub Actions 构建 APK](#11-github-actions-构建-apk)
12. [仓库文件结构](#12-仓库文件结构)
13. [你的操作流程与上传指令](#13-你的操作流程与上传指令)
14. [开发阶段划分](#14-开发阶段划分)
15. [风险与已知缺口](#15-风险与已知缺口)
16. [待定/需要你拍板](#16-待定需要你拍板)

---

## 1. 项目定位与范围

**做什么**：记录《中二节奏 2027》连章模式**每个门的解锁条件**完成进度，避免忘记「还差哪几首没打」。

**明确不做**（按你的要求砍掉）：

| 不做 | 原因 |
|---|---|
| 多服务器（日服/亚服）支持 | 只做国服 |
| 进度导出/导入、多存档 | 不需要 |
| 通关（打 BOSS）的成败记录 | 只记录**解锁条件** |
| 联机、账号系统、云端同步 | 不需要 |
| `localOnly` / `survivorsRequired` | 国服与亚服都是**单人挑战** |
| 「今天建议打哪几首」 | v2 再说 |

**定位**：单人本地工具，离线优先，数据存手机本地。自用 + 朋友用，不上架。

---

## 2. 已核实的事实

### 2.1 版本与门

| 事实 | 来源 |
|---|---|
| 国服《中二节奏 2027》(CN1.40) 稼働日 **2026-09-10**，机制基于 X-VERSE-X，连章首发，官方译名**连章** | [RemyWiki 中二节奏2027](https://silentblue.remywiki.com/CHUNITHM:2027_(China)) |
| 国服 2027 上线日新增曲含 `Linked GATE ORIGIN`（神鳴）与 `Linked GATE AIR`（Tru'nembra） | 同上 |
| 日服连章最终 **12 个门**（Stage 1 十个 + Stage 2 两个） | [SEGA 官方情报](https://info-chunithm.sega.jp/12052/) |
| 国服初版只有 Stage 1 的 10 个门 | [RemyWiki Linked VERSE](https://silentblue.remywiki.com/CHUNITHM:Linked_VERSE) |
| 连章进入门槛：**Rating ≥ 5.00** | SEGA 官方情报 |
| 国服 = 亚服汉化 + 删减；国服/亚服均为**单人挑战** | 用户说明 |

### 2.2 亚服/国服与日服的关键差异

| 项目 | 日服 | 亚服 / 国服 |
|---|---|---|
| Link GAUGE 初始 Life | 1000～5000 | **300～3000** |
| 回血机制 | 有；100 连击给**其他玩家**回血 | **完全没有** |
| 匹配 | 全国匹配 | **单人挑战**（亚服跳过匹配界面） |
| 门通关判定 | 任一玩家存活则全员解锁 | 需**自己**剩余生命超过阈值 |

> 结论：国服不能靠队友回血、也不能靠「别人活下来」混过关。**「还差哪几首」的清单比日服更重要**——这正是本工具的价值。

### 2.3 落雪查分器 API（实测）

| 事实 | 来源 |
|---|---|
| 三种鉴权：开发者 / **个人** / OAuth | [开发者入驻指南](https://maimai.lxns.net/docs/developer-guide) |
| 开发者 API **拿不到完整成绩** | 同上 |
| **个人 API** 用请求头 `X-User-Token`，可访问**自己的**全部数据 | 同上 |
| 曲目 ID 与游戏内 ID **是同一套**（`music0051` = `id:51` = My First Phone / cubesato） | 实测公开接口 |
| **曲绘在线可用**：`https://assets2.lxns.net/chunithm/jacket/{song_id}.png`（实测 id=180 / id=2802 均返回 PNG） | 实测 |
| 返回时间均为 **UTC** | 开发者入驻指南 |

### 2.4 `lx_test.txt` 实测分析（**推翻了原始自动打勾方案**）

你的导出：**639 条记录 / 569 首曲**。

| 观察 | 数据 |
|---|---|
| 返回**全部有成绩的谱面**，非单曲 best | 569 曲 → 639 条 |
| 包含**未通关**记录 | `clear`：`clear` 428 / `hard` 192 / `failed` 16 / `brave` 2 / `absolute` 1 |
| `play_time` 与 `last_played_time` **语义不同** | 不一致 **29 条** |
| `last_played_time` 覆盖率更高 | 有值 297；`play_time` 267；**两者都空 342** |

**两个时间字段的真实语义**（由数据推出）：

- `play_time` = **取得该成绩的那一次**游玩时间
- `last_played_time` = **最近一次**游玩该谱面的时间

实例 `id=2326`（U&iVERSE -銀河鸞翔-）：

```
play_time        = 2025/8/27 9:28:00   ← 这个成绩是这时打的
last_played_time = 2026/9/3 8:28:00    ← 最近一次打是这时
```

**决定性发现**：ORIGIN 的 30 首里 **21 首的两个时间字段全空**，例如：

| 曲目 | id | 有成绩？ | 有时间？ |
|---|---|---|---|
| Gate of Fate | 63 | ✅ 1003696 | ❌ |
| Anemone | 65 | ✅ 999017 | ❌ |
| The wheel to the right | 69 | ✅ 987407 | ❌ |
| リリーシア | 74 | ✅ 999386 | ❌ |
| luna blu | 76 | ✅ 993985 | ❌ |
| 閃鋼のブリューナク | 141 | ✅ 999768 | ❌ |
| Gustav Battle | 152 | ✅ 1004563 | ❌ |
| …共 21 首 | | | |

➡️ **`scores` 接口无法可靠判断「2026-09-10 之后是否打过」**，必须靠 `/recents`（见第 8 节）。

---

## 3. 总体架构

```
┌──────────────────────────────────────────────────────────┐
│  Flutter App（Android，minSdk 29 = Android 10）            │
│                                                           │
│  内置默认数据 assets/data/*.json  ← 冷启动/离线兜底         │
│           ↓ 首次运行加载                                   │
│  本地缓存 JSON（可被同步覆盖）                              │
│           ↑ 自动同步（启动时）/ 手动同步按钮                │
│  在线源：raw.githubusercontent.com/.../data/*.json         │
│                                                           │
│  ProgressStore（本地存档，永不联网）                        │
│  ImportService（LxnsImporter / ManualTextImporter）        │
└──────────────────────────────────────────────────────────┘
                  ↑ 源码
        GitHub repo: GzLxz190614/lvchecker
                  ↓ GitHub Actions
            flutter build apk --release
                  ↓
         GitHub Release（APK 下载链接）
                  ↓
              手机安装
```

**技术选型：Flutter**

| 理由 | 说明 |
|---|---|
| 本地磁盘零负担 | Android SDK 只在 CI 装，你本地 21GB 剩余空间不用动 |
| 单 codebase 出 APK | 无需 Java/Kotlin/Gradle 本地环境 |
| 中文 + 日文曲名混排 | Flutter 在 Android 上字体回退正常 |
| 内置资源 + 在线同步 | 离线可用，同时支持不更新 APK 就更新数据 |

**关键兼容性要求（你提出）**：

| 项目 | 值 | 说明 |
|---|---|---|
| `minSdkVersion` | **29**（Android 10） | Flutter 默认 minSdk 21，**必须显式抬到 29** 以满足你的常用机 |
| `targetSdkVersion` | Flutter 默认 | 无需特殊处理 |
| APK 形式 | **通用单包**（不加 `--split-per-abi`） | 一个 APK 兼容所有架构 |

---

## 4. 数据模型

### 4.1 只读数据层 `data/gates.json`

```jsonc
{
  "schemaVersion": 1,
  "dataVersion": "2026.09.11-1",
  "region": "cn",
  "gameVersion": "中二节奏 2027 (CN1.40)",
  "updatedAt": "2026-09-11",
  "gates": [
    {
      "id": "origin",
      "order": 1,
      "stage": 1,
      "name": "Linked GATE ORIGIN",
      "boss": { "songId": 8001, "title": "神鳴", "artist": "Rígr feat. 光吉猛修" },

      // ---- 门的开放状态 ----
      "releaseDate": "2026-09-10T10:00:00",   // 无时区，按手机本地时间比较
      "releaseStatus": "open",                 // open | notYetOpen
      "conditionSource": "official",           // official | user | estimated
      "releaseNote": "",                       // 例：CRYSTAL 的「国服条件待确认」

      // ---- 解锁条件的跟踪方式 ----
      "tracking": "songs",                     // songs | manual
      "conditionText": "2026-09-10 更新后把这 30 首各打一次",

      // ---- tracking = songs ----
      "requirement": {
        "type": "playAll",                     // playAll | playAnyOfEach | clearAllPrev
        "songIds": [51, 53, 59, 63, 64, 65, 67, 69, 70, 71, 74, 75, 76, 79, 80,
                    82, 95, 100, 101, 105, 107, 108, 140, 141, 147, 148, 151, 152, 163, 180]
      },

      // ---- tracking = manual ----
      "manualItems": null,
      "prerequisites": []
    }
  ]
}
```

**字段存在理由**

| 字段 | 为什么需要 |
|---|---|
| `releaseDate` | 时间过滤的阈值。不是装饰——它决定哪些旧成绩**不算数** |
| `releaseStatus` | 未开放的门显示「未更新」，不让用户误以为能打 |
| `conditionSource` | 区分「官方确认」和「我自己填的」。`user`/`estimated` 时 UI 显示小标记 |
| `tracking` | `songs` / `items` / `class` / `auto` / `universe` / `manual` —— **唯一区分门类型的开关**（见下表） |
| `conditionText` | 条件描述直接写 JSON 里（你要求），UI 默认折叠、可展开 |
| `prerequisites` | X-VERSE / RE:VERSE 的「通关前面所有门」 |

> **时区处理**：`releaseDate` **不带时区后缀**，按**手机本地时间**解析（你要求）。
> 落雪 API 返回的 UTC 时间会转成手机本地时间后再比较。

**`tracking` 六种取值的含义**

| tracking | 用于哪些门 | 用户要做什么 | UI 主体 |
|---|---|---|---|
| `songs` | ORIGIN / AMAZON / PARADISE / SUN / VERSE / RE:VERSE | 给每首歌打勾 | 曲目卡片网格 |
| `items` | STAR / NEW / LUMINOUS | 给每个条目打勾 | 图片+名称卡片网格 |
| `class` | AIR | 给每个组曲打勾 | 双层折叠框（第 7 节） |
| `auto` | X-VERSE | **什么都不用做**，前置门全解锁就自动达成 | 只显示前置门列表 |
| `universe` | UNIVERSE | 手动确认「已达成剩余血量」 | 单个大勾选框 + 血量要求表 |
| `manual` | CRYSTAL（条件未知） | 手动确认 | 单个大勾选框 + 待确认提示 |

### 4.2 `playAnyOfEach` 类型（PARADISE 门专用）

```jsonc
{
  "id": "paradise",
  "order": 6,
  "name": "Linked GATE PARADISE",
  "tracking": "songs",
  "conditionText": "五位曲师，从每个人自己作曲的所有乐曲中，各选一首乐曲打一次",
  "releaseDate": null,
  "releaseStatus": "notYetOpen",
  "requirement": {
    "type": "playAnyOfEach",
    "groups": [
      { "key": "光吉猛修", "songIds": [180, 384, 483, 2355, 2493] },
      { "key": "穴山大輔", "songIds": [407, 2353] },
      { "key": "Kai",      "songIds": [629, 788] },
      { "key": "水野健治", "songIds": [2704] },
      { "key": "大国奏音", "songIds": [2050, 2354] }
    ]
  }
}
```

UI：显示「3/5 位曲师已完成」，每组内打勾任一即算该组完成。

### 4.3 `clearAllPrev` 类型（X-VERSE 门）

```jsonc
{
  "id": "xverse",
  "order": 11,
  "stage": 2,
  "name": "Linked GATE X-VERSE",
  "tracking": "auto",                 // ← 第三种 tracking：无需用户操作，纯前置推导
  "conditionText": "通关前面 10 个门后自动解锁",
  "releaseDate": null,
  "releaseStatus": "notYetOpen",
  "prerequisites": ["origin","air","star","amazon","crystal",
                    "paradise","new","sun","luminous","verse"]
}
```

### 4.4 用户存档（本机，永不联网）

```jsonc
{
  "schemaVersion": 1,
  "ticked": {                        // 门 id → 曲 id → 打勾时间
    "origin": { "51": "2026-09-11T20:31:00" }
  },
  "groupTicked": {                   // playAnyOfEach：门 id → 组 key → 已选曲 id
    "paradise": { "光吉猛修": 180 }
  },
  "manualDone": {                    // 角色/服装/地图等通用勾选框：门 id → 条目 key → 时间
    "star":   { "chara024320": "2026-09-12T01:00:00" },
    "new":    { "avatarAccessory06104401": "...", "avatarAccessory06204401": "..." },
    "luminous": { "cmission0350": "..." }
  },
  "classDone": {                     // AIR 门专用：课程 key → 时间
    "air": { "III-course-1": "2026-09-12T01:00:00" }
  },
  "universeHp": { "universe": 1000 } // UNIVERSE 门的剩余血量要求（见 6.4）
}
```

**关键设计**：用户存档**与曲目清单完全分离**。以后更新 JSON（开新门、曲目变动）**不会覆盖进度**。存档通过 `门 id + 曲 id` 关联，不用数组下标。

### 4.5 通用「勾选条目」结构 + 本地图片资源

因为大量内容都是「**图片 + 名称**」（乐曲、角色、服装、段位的组曲），所以统一成一种**卡片**：

```
┌──────────┐
│          │   ← 图片（正方形，铺满卡片宽度）
│   图片    │
│          │
├──────────┤
│ 曲名/名称 │   ← 最多 2 行
│ 副标题    │   ← 1 行（曲师 / 说明）
└──────────┘
```

**交互（你要求）**：**点一下卡片就算完成**（不需要额外的勾选框）。
- 完成后：加半透明白色遮罩 + 居中「已完成」文字，并移到列表末尾
- 再点一下：取消完成，移回原位

**图片全部本地化**（你要求）：把 `condition/` 里的 `.dds` 转成图片文件，按 **ID 分文件夹**存放，并在每个文件夹里放一个**新的元数据文件**（不用原来的 XML）。

#### 资源目录结构

```
assets/img/
├── music/
│   └── 51/
│       ├── jacket.png          # 由 CHU_UI_Jacket_0051.dds 转出（300×300）
│       └── meta.json           # { id, title, artist, genre, works, levels }
├── chara/
│   └── 24320/
│       ├── image.png           # 由 CHU_UI_Character_2432_00_00.dds 转出（1080×1080）
│       └── meta.json           # { id, title, works }
└── avatar/
    └── 6104401/
        ├── icon.png            # 由 CHU_UI_Avatar_Icon_06104401.dds 转出（256×256）
        ├── tex.png             # 由 CHU_UI_Avatar_Tex_06104401.dds 转出（516×436，详情页用）
        └── meta.json           # { id, title, slot }
```

> ⚠️ 角色的 dds 文件名是 `CHU_UI_Character_2432_00_00`——前 4 位 `2432` **不是**完整角色 id（`24320`）。
> 脚本不靠猜：读同目录（或子目录）的 `Chara.xml` 拿 `name/id` 的真实值。


`meta.json` 示例：

```jsonc
// assets/img/music/51/meta.json
{ "id": 51, "title": "My First Phone", "artist": "cubesato",
  "genre": "ORIGINAL", "works": "[ORIGINAL] Ver. CHUNITHM" }

// assets/img/chara/24320/meta.json
{ "id": 24320, "title": "観音寺 にこる／Mermaid♡Moment", "works": "CHUNITHM VERSE" }

// assets/img/avatar/6104401/meta.json
{ "id": 6104401, "title": "淀川 沙音瑠の服", "slot": "wear" }
```

**为什么这样切**：

| 好处 | 说明 |
|---|---|
| 图片和它的名字**不分离** | 加一个新条目只需丢一个文件夹进去 |
| **构建时就把名字拼好** | `gen_gates.py` 生成 `gates.json` 时顺便 `title` 写死，app 运行**不需要**读 meta.json，零解析开销 |
| 去重天然安全 | 已核查：71 个 dds 里只有 `CHU_UI_Jacket_0180` 重复（同时出现在 origin 和 paradise），**且内容完全一致**，按 `music/180/` 归并无冲突 |
| 不用原来的 XML | 你要求「不能用原来的 xml」，`meta.json` 是新生成的精简格式 |

#### `gates.json` 里的条目写法

```jsonc
"tracking": "items",
"items": [
  { "key": "chara024320",
    "title": "観音寺 にこる／Mermaid♡Moment",   // ← 构建时从 Chara.xml 拼好
    "subtitle": "角色 · 需升到 RANK 15",
    "image": "assets/img/chara/24320/icon.png" }
]
```

乐曲条目同理：

```jsonc
"songs": [
  { "id": 51, "title": "My First Phone", "artist": "cubesato",
    "image": "assets/img/music/51/jacket.png" }
]
```

段位组曲里的 3 首歌也用同一个结构（见第 7 节）。

#### 图片资源的三种来源

| 情况 | 处理 |
|---|---|
| 本地有 `.dds` | ✅ **转 PNG 内置**（全部乐曲/角色/服装都属这类） |
| 地图 / Mission 没有对应图 | `"image": null` → UI 用纯文字卡片 |
| 以后加了新曲但没 `dds` | 可回退到在线曲绘（`assets2.lxns.net/chunithm/jacket/{id}.png`），**但 v1 不实现** |

> 你已明确「图片资源不用去落雪那边拿」，所以**整个 v1 不依赖任何在线图片**，纯离线可用。

#### `.dds` 转换可行性（已实测）

| 项 | 结果 |
|---|---|
| 格式 | **DXT1**（fourCC `DXT1`），无 mipmap |
| 曲绘尺寸 | 300 × 300 |
| 服装尺寸 | 256 × 256（Icon 版）／另有 Tex 版立绘 |
| Pillow 11.2.1 | ✅ **可直接解码**（`Image.open` → `RGBA`，实测成功） |
| 数量 | 71 个 dds：63 曲绘 + 4 服装 Icon + 4 服装 Tex |
| 预计 PNG 体积 | 每张约 30～80 KB → 63 张曲绘约 **2～5 MB** |


---

## 5. 十三个门的数据

**全部来自你的 `condition/` 目录**，开放日期以你的 `日期.txt` 为准。

| # | 门 | 开放日 | tracking | 条件摘要 |
|---|---|---|---|---|
| 1 | ORIGIN | **2026-09-10** | `songs` | 更新后把 30 首各打一次 |
| 2 | AIR | **2026-09-10** | `class` | 获得一个段位缎带（**完成任一 CLASS 内所有组曲**） |
| 3 | STAR | 未更新 | `items` | 角色 観音寺 にこる／Mermaid♡Moment 升到 RANK 15 |
| 4 | AMAZON | 未更新 | `songs` | 2 首加收藏后各打一次 |
| 5 | CRYSTAL | 未更新 | `manual` | ⚠️ **国服条件未知**（日服需队伍功能，国服无） |
| 6 | PARADISE | 未更新 | `songs` | 5 位曲师各打一首（13 首候选） |
| 7 | NEW | 未更新 | `items` | 更新后 Mission 获得 3 件企鹅服装并穿上 |
| 8 | SUN | 未更新 | `songs` | 更新后把 5 首各打一次 |
| 9 | LUMINOUS | 未更新 | `items` | 集 100 气球 → 解锁隐藏地图 → 跑完 |
| 10 | VERSE | 未更新 | `songs` | 从推荐乐曲文件夹打这 3 首一次 |

**Stage 2**（国服尚未开放，条件文本已从你的 `condition/` 读到）：

| # | 门 | 开放日 | tracking | 条件摘要 |
|---|---|---|---|---|

| 11 | X-VERSE | 未更新 | `auto` | 通关前面 10 个门后自动解锁 |
| 12 | RE:VERSE | 未更新 | `songs` | 完成 X-VERSE → 解锁 Secret AREA: MUSIC GAME EX → 完成地图拿全 11 首 |
| 13 | UNIVERSE | 未更新 | `universe` | 通关 RE:VERSE 时剩余血量 ≥ 指定血量（按日期缓和） |

### 5.1 ORIGIN — 30 首（完整）

| 曲 id | 曲名 | 曲师 |
|---|---|---|
| 51 | My First Phone | cubesato |
| 53 | Teriqma | owl＊tree |
| 59 | Invitation | れるりり feat.ろん |
| 63 | Gate of Fate | Godspeed |
| 64 | 今ぞ♡崇め奉れ☆オマエらよ！！～姫の秘メタル渇望～ | あべにゅうぷろじぇくと feat.佐倉 紗織 produced by ave;new |
| 65 | Anemone | ESTi |
| 67 | 昵懇レファレンス | halyosy |
| 69 | The wheel to the right | Sampling Masters MEGA |
| 70 | STAR | SEXY-SYNTHESIZER |
| 71 | Infantoon Fantasy | t+pazolite |
| 74 | リリーシア | TaNaBaTa |
| 75 | Counselor | DECO*27 feat.echo |
| 76 | luna blu | WASi303 |
| 79 | ＧＯ！ＧＯ！ラブリズム♥ | 片霧烈火オンザみんマンション |
| 80 | Grab your sword | 古代 祐三 |
| 82 | Memories of Sun and Moon | Aiko Oi |
| 95 | 砂漠のハンティングガール♡ | 海田 明里 |
| 100 | After the rain | 霜月はるか |
| 101 | Tango Rouge | Yoko Shimomura |
| 105 | overcome | 景山 将太 |
| 107 | We Gonna Journey | Queen P.A.L. |
| 108 | The ether | 浜渦 正志 |
| 140 | Guilty | MintJam |
| 141 | 閃鋼のブリューナク | sasakure.UK |
| 147 | こころここから | ふわりP |
| 148 | Theme of SeelischTact | 植松 伸夫 |
| 151 | Alma | 光田 康典 |
| 152 | Gustav Battle | 伊藤 賢治 |
| 163 | 幾四音-Ixion- | M.S.S Project |
| 180 | 怒槌 | 光吉猛修 |

> 30 首 `worksName` 全为 `[ORIGINAL] Ver. CHUNITHM`，genre 全为 `ORIGINAL`；与日服官方条件表逐首核对**完全一致**。

### 5.2 AMAZON — 2 首

| 曲 id | 曲名 | 曲师 |
|---|---|---|
| 712 | Climax | USAO |
| 777 | Killing Rhythm | DJ Myosuke |

### 5.3 PARADISE — 5 位曲师 / 12 首候选

**条件：每位曲师的所有乐曲中挑一首，所以最少要打 5 首（每人一首）。**

| 曲师 | 曲 id | 曲名 |
|---|---|---|
| 光吉猛修（5 首可选） | 180 | 怒槌 |
| | 384 | キュアリアス光吉古牌　－祭－ |
| | 483 | Burning Hearts ～炎のANGEL～ |
| | 2355 | 「四季」より「冬」 |
| | 2493 | マツケンサンバⅡ |
| 穴山大輔（2 首可选） | 407 | 混沌を越えし我らが神聖なる調律主を讃えよ |
| | 2353 | 幻想即興曲 |
| Kai（2 首可选） | 629 | Candyland Symphony |
| | 788 | Rebellion |
| 水野健治（1 首） | 2704 | ≠彡"/了→ |
| 大国奏音（2 首可选） | 2050 | 封焔の135秒 |
| | 2354 | 月の光 |

**合计 12 首候选，5 个组。** 每组打勾任一即算该组完成。

> `マツケンサンバⅡ` 的 `artistName` 是 `松平健 [covered by 光吉猛修]`，但日服官方把它归在光吉猛修组，按官方归组。


### 5.4 SUN — 5 首

| 曲 id | 曲名 | 曲师 | genre |
|---|---|---|---|
| 2266 | I'm so Happy | Ryu☆ | VARIETY |
| 2326 | U&iVERSE -銀河鸞翔- | Kai VS 大国奏音 VS 水野健治 | ゲキマイ |
| 2327 | RELOAD | sky_delta | ゲキマイ |
| 2556 | Mutation | Laur | ゲキマイ |
| 2597 | Stardust:RAY | kanone vs. BlackY | ゲキマイ |

### 5.5 VERSE — 3 首

| 曲 id | 曲名 | 曲师 |
|---|---|---|
| 2705 | メッちゅう殴打 | STEAKA feat.山田じぇみ子 |
| 2712 | Theatore Creatore | Toby Fox & かめりあ |
| 2802 | Crossmythos Rhapsodia | Acotto vs Potwi |

### 5.6 RE:VERSE — 11 首（传導乐曲）

| 曲 id | 曲名 | 曲师 |
|---|---|---|
| 2968 | PANDORA PARADOXXX | 削除 |
| 2969 | μ3 | 水野健治 VS 穴山大輔 |
| 2970 | †渚の小悪魔ラヴリィ～レイディオ† | 夏色ビキニのPrim |
| 2971 | 聖者の息吹 | 世阿弥 vs Tatsh |
| 2972 | 超MANJIラッシュ | Massive New Krew |
| 2973 | Lips XTC -Sorist Remix- | from PACA PACA PASSION Special |
| 2974 | Marigold | M2U |
| 2975 | glory MAX -to the MAXimum- | TAK |
| 2976 | DESTRUCTION 3,2,1 | Normal1zer vs. Broken Nerdz |
| 2977 | Ré：Ré | モリモリあつし vs. uma |
| 2978 | ALTER EGO | Yuta Imai vs Qlarabelle |

### 5.7 角色 / 服装 / 地图条目

| 门 | 条目 key | 标题 | 图片 |
|---|---|---|---|
| STAR | `chara:24320` | 観音寺 にこる／Mermaid♡Moment（作品 CHUNITHM VERSE） | ✅ `assets/img/chara/24320/image.png`（1080×1080） |
| NEW | `avatar:6104401` | 淀川 沙音瑠の**服**（ウェア） | ✅ icon + tex |
| NEW | `avatar:6204401` | 淀川 沙音瑠の**頭**（ヘッド） | ✅ icon + tex |
| NEW | `avatar:6704401` | 淀川 沙音瑠の**ランドセル**（バック） | ✅ icon + tex |
| LUMINOUS | `mission:350` | Mission「2603_カイナン・メルヴィアス」→ 集 100 气球拿称号 MISSION still in progress | ⬜ 无图（纯文字卡片） |
| LUMINOUS | `map:3020815` | 隐藏地图 Secret AREA：LUMINOUS | ⬜ 无图 |
| CRYSTAL | — | ⚠️ 国服条件未知，仅手动确认 | — |

> ✅ **NEW 门要哪 3 件已确认**（原 Q9 已解决）：
> 你的数据里有 **4** 个 avatar 条目，但官方条件只要 **3 件**（ウェア / ヘッド / バック）：
>
> | key | 名称 | 要不要 |
> |---|---|---|
> | `avatarAccessory06104401` | 淀川 沙音瑠の服 | ✅ 要 |
> | `avatarAccessory06204401` | 淀川 沙音瑠の頭 | ✅ 要 |
> | `avatarAccessory06504401` | 淀川 沙音瑠の**アイス**（冰淇淋） | ❌ **不要** |
> | `avatarAccessory06704401` | 淀川 沙音瑠のランドセル | ✅ 要 |
>
> 第 4 件是「冰淇淋」，不在解锁条件里，**已排除**。

### 5.8 各门 BOSS 曲（**全部来自本地游戏数据**）

`condition/boss/` 下 13 首，难度直接从 `Music.xml` 的 `level` + `levelDecimal` 读（`14` + `50` = **14.5**）：

| 门 | BOSS 曲 | 曲师 | BASIC | ADV | EXP | MAS | ULT |
|---|---|---|---|---|---|---|---|
| ORIGIN | 神鳴 | Rígr feat. 光吉猛修 | 6 | 10.5 | 14.5 | 15.6 | — |
| AIR | Tru'nembra | Team Grimoire & 穴山大輔 | 5 | 10 | 14.4 | 15.6 | — |
| STAR | Everything Will Be One | void (Mournfinale) | 6 | 10 | 13.8 | 15.4 | — |
| AMAZON | OUTRAGE | USAO vs DJ Myosuke | 6 | 10.4 | 14 | 15.4 | — |
| CRYSTAL | 輪廻玲々 | suzu | 6 | 11 | 14.3 | 15.4 | — |
| PARADISE | 創 -汝ら新世界へ歩む者なり- | BlackY VS Yooh VS siromaru VS xi VS モリモリあつし | 7 | 12 | 14.8 | 15.7 | — |
| NEW | 轆轤首 | かねこちはる | 5 | 9 | 13.9 | 15.4 | — |
| SUN | Sweet & Sour | Sakuzyo or Sobrem | 5 | 10 | 14.4 | 15.6 | — |
| LUMINOUS | Phantom Crisis | t+pazolite vs Yuta Imai | 6 | 11.9 | 14.1 | 15.5 | — |
| VERSE | 月葬 | 黒魔 × rintaro soma | 5 | 9 | 14.3 | 15.5 | — |
| X-VERSE | YOUNITHM | 大国奏音 | 8 | 12.6 | 14.8 | 15.5 | **15.8** |
| RE:VERSE | YOUNITHM | 大国奏音 | 8 | 12.6 | 14.8 | 15.5 | **15.8** |
| UNIVERSE | Melodiniq | onoken a.k.a. owl＊tree | 8.5 | 13 | 14.9 | 15.6 | **16** |
| **奖励** | **Linked Tune** | 水野健治 | 2 | 6 | 10.7 | 13.5 | — |

> ✅ **CRYSTAL 的 BOSS 确认了**：`輪廻玲々` / `suzu`（曲 id 2880），从此不用再靠猜测。
> 之前 RemyWiki 上 STAR / AMAZON / CRYSTAL / PARADISE 的难度是缺的，现在**全部有精确值**。
> `linkedId` 用 `music:2880` 形式，与 `meta.json` 统一。

**BOSS 的显示规则（你要求）**：

- 位于**每页最下方**
- **达成解锁条件后才显示**；未达成就**不显示**（不是灰掉，是整个不显示）
- 显示内容：曲名 / 曲师 / 四个难度等级

### 5.9 奖励乐曲（第 14 页）

`Linked Tune` 是全部门通关后的奖励乐曲，**单独一页**，只显示这一首。

| 字段 | 值 |
|---|---|
| `id` | `reward` |
| `order` | 14（排在最后） |
| `kind` | `"reward"`（用于 UI 区分：不进「解锁条件门」的计数） |
| `name` | 奖励乐曲 |
| `releaseStatus` | `"locked"`（第 4 种状态，区别于 open / notYetOpen） |
| `tracking` | `auto` |
| `conditionText` | 通关全部 13 个门后自动显示 |
| `prerequisites` | 全部 13 个门 |
| BOSS | Linked Tune / 水野健治 / B2 A6 E10.7 M13.5 |

**这页的特殊性**：

- 它在门列表（左右滑动）里是**第 14 页**，但在「已解锁门数 / 进度」里**不计数**
- 只有 13 个门全部「已解锁」后，这一页才出现（之前滑不到）
- 页内**不显示任何需要勾选的条目**，直接显示 BOSS 区块


---

## 6. 通关条件缓和配置设计

### 6.1 三段状态

| 状态 | 条件 | UI 显示 |
|---|---|---|
| `notYetOpen` | `releaseDate` 为 null，或今天 < `releaseDate` | 「**未更新**」灰色 |
| `noRelaxation` | 门开了，但缓和日期未知 | 「**缓和未开始**」+ 按最严档显示 |
| `relaxed` | 处于某个已生效等级 | 该档高亮，已过时档**灰色** |

### 6.2 `data/linklevels.json`

```jsonc
{
  "schemaVersion": 1,
  "dataVersion": "2026.09.11-1",
  "region": "cn",
  "note": "国服缓和周期未完全公布。已知的填日期，未知的留 null（不猜）。",
  "defaultLevel": 5,

  "judges": {
    "JUSTICE":         { "damage": -5,  "color": "#FF6A00" },
    "ATTACK":          { "damage": -10, "color": "#00FF00" },
    "MISS":            { "damage": -20, "color": "#000000" },
    "JUSTICE_CRITICAL":{ "damage": -1,  "color": "#F6E80D" }
  },

  "gates": {
    "origin": {
      "levels": [
        { "level": 5, "from": "2026-09-10T10:00:00", "minDifficulty": "MASTER",
          "life": 300,  "judges": ["JUSTICE","ATTACK","MISS"], "source": "official" },
        { "level": 4, "from": null, "minDifficulty": "MASTER",
          "life": 1000, "judges": ["JUSTICE","ATTACK","MISS"], "source": "user" },
        { "level": 3, "from": null, "minDifficulty": "MASTER",
          "life": 2000, "judges": ["JUSTICE","ATTACK","MISS"], "source": "user" },
        { "level": 2, "from": null, "minDifficulty": "EXPERT",
          "life": 3000, "judges": ["JUSTICE","ATTACK","MISS"], "source": "user" },
        { "level": 1, "from": null, "minDifficulty": "BASIC",
          "life": 3000, "judges": ["JUSTICE","ATTACK","MISS"], "source": "user" }
      ]
    },
    "universe": {
      "levels": [
        { "level": 0, "label": "∞", "from": null, "minDifficulty": "ULTIMA",
          "life": 2000, "judges": ["JUSTICE_CRITICAL","JUSTICE","ATTACK","MISS"],
          "requiredHp": null, "source": "user" }
      ],
      "note": "解锁要求：通关 RE:VERSE 时剩余血量 ≥ requiredHp（按日期缓和）"
    }
  }
}
```

### 6.3 `confirmed` → 改名 `source`

你问的 `confirmed` 字段，本意是「这个日期到底是官方公布的、还是我填的/推测的」，用来在 UI 上挂一个「待确认」小标记。

但既然你定的策略是「**未知就留 null，不猜**」，那 `confirmed: true/false` 就有点多余了——因为**留 null 本身就代表未知**。所以我把语义挪成更直白的 `source`：

| `source` | 含义 | UI |
|---|---|---|
| `official` | 游戏内/官方公告能看到 | 正常显示 |
| `user` | 我按你给的资料填的 | 正常显示 |
| `estimated` | 推测值 | 挂「待确认」小标记 |

如果你觉得没必要，直接删掉也行——**我倾向保留 `source`，因为它能防止以后自己忘了哪条是猜的**。

### 6.4 `∞` 档的表示（Q6）

你问我 `level: 0` 和 `label: "∞"` 哪个好。我的建议是**两个都要**：

```jsonc
{ "level": 0, "label": "∞", ... }
```

- `level: 0` —— 用于**排序**（∞ 排在 I 前面，符合游戏内顺序）和代码里的**数值比较**
- `label: "∞"` —— 用于**显示**

只用字符串的话，排序和比较都得写特例；只用数字的话，UI 上会显示成 `0`，很难看。

### 6.5 `releaseDate` 与 `revision`（Q3 回答）

Q3 你问的这两个词条是这么回事：

| 字段 | 含义 | 为什么要分开 |
|---|---|---|
| `releaseDate` | **门什么时候开放**（可以开始挑战） | 决定 UI 显示「未更新」还是「已开放」 |
| `revision` | **条件的「更新后」指的是哪个时间点**——歌曲必须在这个时间之后打过才算数 | 决定时间过滤阈值 |

**为什么曾经想分成两个**：RE:VERSE 门在日服是 2026-04-23 开放的，但它的 11 首传導曲是 2026-08-20 才加进游戏的。理论上可能出现「门先开、条件后生效」。

**但你的数据里 `日期.txt` 只有一个日期**，而且目前每个门都是「开放日 = 条件生效日」。所以：

**我的建议：合并成一个 `releaseDate`，不加 `revision`。** 理由是「只有一个日期」才是真实的游戏机制，多一个字段只会让人填错。哪天真出现分离的情况，再加不迟。

### 6.6 为什么不自动算等级

日服 ORIGIN 的 V 档是 2025/07/16、I 档是 2025/08/14，而国服 2026-09-10 才上线，**晚了一整年**。照抄必然算错。

所以原则是：**跨服通用的数值（等级→难度/生命/判定）写死；日期部分留 null**。
你把国服的缓和日期告诉我（机台公告/官方微博/别人整理的表），我改 JSON 即可，**不用改代码**。

### 6.7 判定颜色（你提供）

除 UNIVERSE 门外，所有门都是：

| 判定 | 伤害 | 颜色 |
|---|---|---|
| JUSTICE | -5 | `#FF6A00` |
| ATTACK | -10 | `#00FF00` |
| MISS | -20 | `#000000` |

UNIVERSE 门**多一条**：

| 判定 | 伤害 | 颜色 |
|---|---|---|
| JUSTICE CRITICAL | -1 | `#F6E80D` |

（其余三条与上表相同）

> 注：`MISS` 的颜色是纯黑 `#000000`，在深色背景下会看不见。UI 里我会给它加描边或用浅色卡片底。

---

## 7. AIR 门：段位（CLASS）数据结构

### 7.1 游戏机制（按你的说明）

- 段位有 **6 个等级**：I / II / III / IV / V / ∞
- 每个等级内有**多个组曲（COURSE）**
- 每个组曲内有 **3 首歌**
- **获得段位勋章（MEDAL）**：完成当前等级内**任一组曲**即可
- **获得段位缎带（RIBBON）**：完成当前等级内**所有组曲**
- AIR 门的解锁条件 = **获得一个缎带** = **把任一等级内的所有组曲通关**

### 7.2 ⚠️ 一个需要你确认的点

你的 `condition/2-air/条件.txt` 原文写的是：

> 获得一个段位缎带
> 即，把当前任一等级（I，II，III，IV，V和∞）下的所有段位通关一遍即可获得，除了Extra等级

**关键词是「任一等级」**——所以只需要**某一个等级**的全部组曲通关即可，不是所有等级。

而你在本轮的 UI 描述里写的是「**检测到一个等级所有组曲完成后就可以标记为"已解锁"了**」——和 `条件.txt` 一致 ✅。

所以设计是：**6 个等级中任意一个的组曲全勾满 → AIR 门显示「已解锁」**。我会按这个做，并在此确认没理解错。

### 7.3 数据来源与生成方式（**已落地，不再是占位符**）

段位课程数据的来源一开始是缺失的（`condition/2-air/` 里只有 `条件.txt` 和 `日期.txt`），
最初的方案是「先写占位数据、拿到 XML 再换」。**这个方案已经废弃**，
因为后来在 `condition/class/` 下找到了完整的段位数据：

```
condition/class/course/<id>/Course.xml    36 个组曲（6 个 CLASS）
condition/class/music/<id>/Music.xml      组曲用到的 76 首曲目
condition/class/random/cover.png          「?」——曲池随机的封面
condition/class/random in range/cover.png 「!」——等级随机的封面
```

生成方式：

| 文件 | 负责什么 |
|---|---|
| `tools/gen_classes.py` | 解析 36 个 `Course.xml` → `data/classes.json`；转换两张封面 |
| `tools/build.py` | 把 `condition/class/music` 下的曲目登记进 `meta.json`（曲名/曲师/曲绘） |
| `tools/check_classes.py` | 校验引用 + **等级换算的回归测试**（见 7.5） |

`build.py` 会自动调用 `gen_classes.py`，也可以单独跑 `python tools\gen_classes.py`。

### 7.4 `data/classes.json` 实际结构

```jsonc
{
  "schemaVersion": 1,
  "dataVersion": "2026.09.11-2",     // 与 meta/gates/linklevels 共用同一个值
  "placeholder": false,
  "region": "cn",
  "gateId": "air",
  "unlockRule": {
    "type": "anyClassAllCourses",
    "text": "完成任一 CLASS 内的所有组曲，即可获得缎带"
  },
  "levelIdMapping": { "note": "...", "baseId": 19, "baseDifficulty": "Lv10" },
  "classes": [
    {
      "key": "I", "label": "I", "level": 1, "color": "#3D66F2",
      "classRawName": "CLASS Ⅰ",
      "courses": [
        {
          "key": "course00040021",      // 来自 Course.xml 的 dataName，也是存进存档的进度 key
          "title": "CLASS认定 - I - Random",
          "songs": [
            // ① 固定曲目：有 linkId + 难度
            { "order": 1, "kind": "fixed", "linkId": "music:802", "difficulty": "MASTER" },

            // ② 等级随机：有内部 ID、显示等级、封面
            { "order": 1, "kind": "randomRange",
              "levelFromId": 19, "levelToId": 19,       // 内部 ID，保留下来便于核对
              "levelFrom": "10", "levelTo": "10",
              "display": "10",                          // UI 直接用这个
              "image": "assets/img/class/range_cover.png" },

            // ③ 曲池随机：只有池大小，不列具体曲目
            { "order": 1, "kind": "randomPool", "poolSize": 10,
              "display": "范围内随机选择",
              "image": "assets/img/class/random_cover.png" }
          ]
        }
      ]
    }
  ]
}
```

**等级颜色**（你提供，转成 HEX 去掉末尾 `FF`）：

| 等级 | 颜色 |
|---|---|
| I | `#3D66F2` |
| II | `#0DB991` |
| III | `#F2AA00` |
| IV | `#E13C29` |
| V | `#4A0973` |
| ∞ | `#FCDBEF` |

### 7.5 ⚠️ `fromLevel` 内部 ID 与游戏内等级的换算（**最容易写错的地方**）

`Course.xml` 里等级随机的槽只给了一个内部 ID（`selectLevel/fromLevel/id`），
而界面上要显示的是游戏内等级。这两者的对应关系是：

```
ID_19 = Lv10    ID_20 = Lv10+   ID_21 = Lv11
ID_22 = Lv11+   ID_23 = Lv12    ID_24 = Lv12+
ID_25 = Lv13    ID_26 = Lv13+   ID_27 = Lv14
ID_28 = Lv14+   ID_29 = Lv15    ID_30 = Lv15+
```

也就是 `Lv = (ID - 19) / 2 + 10`，**每 2 个 ID 涨 1 级**，奇数偏移是 `.5`（显示成 `+`）。

> ⚠️ 不要写成「等级 = ID − 9」。那样 ID_19 → 10 看着是对的（巧合），
> 但 ID_20 会变成 11，而实际是 10+。这是本设计里唯一一个「错了也看不出来」的地方，
> 所以 `tools/check_classes.py` 把下面这张表硬编码成了回归测试：

| 等级 | 随机槽允许出现的内部 ID | 对应等级 |
|---|---|---|
| I | 19 / 20 / 21 | 10 / 10+ / 11 |
| II | 22 / 23 / 24 | 11+ / 12 / 12+ |
| III | 24 / 25 / 26 | 12+ / 13 / 13+ |
| IV | 26 / 27 / 28 | 13+ / 14 / 14+ |
| V | 27 / 28 / 29 | 14 / 14+ / 15 |
| ∞ | 28 / 29 / 30 | 14+ / 15 / 15+ |

定这个换算的**依据**是你确认过的一句话：

> 「CLASS认定 - Ⅰ - Random 不是『等级 19 / 20 / 21』，19/20/21 是 id，真正的等级是 Lv10」

而 `condition/class/course` 里 `CLASS认定 - I - Random` 那三个槽的 `fromLevel`
正好是 `ID_19 / ID_20 / ID_21`。另一条独立佐证：`混沌を越えし我らが神聖なる調律主を讃えよ`（id 407）
在本地数据里是 ADVANCED Lv10，而它所在的组曲槽位就是 `ID_19`。

### 7.6 进度计算

```
每个组曲：classDone["air"]["III-1"] 存在 → 该组曲已完成
每个等级：该等级下所有组曲都完成 → 显示「已达成缎带条件」
AIR 门解锁：任意一个等级的所有组曲完成 → 已解锁
```

UI 同时显示两个状态：

- 组曲级：勾选框（点一下标记完成，再点取消）
- 等级级：折叠框标题右侧显示「3/5 组曲」+ 全部完成时显示「已达成缎带条件」
- 门级：顶栏显示「已解锁」（任一等级全完成）

**进度粒度是「组曲」而不是「单曲」**：缎带条件是通关整个组曲，
组曲里的 3 首只是告诉你这个组曲要打什么，所以它们是**只读展示**，不能逐首打勾。

### 7.7 随机槽的显示（你指定的写法）

| 槽类型 | 封面 | 大字 | 小字 |
|---|---|---|---|
| 等级随机 `randomRange` | `random in range/cover.png`（`!`） | 游戏内等级，如 `11+`、`13+ ~ 14` | 等级随机 |
| 曲池随机 `randomPool` | `random/cover.png`（`?`） | `范围内随机选择` | `10 选 1` |

「`シビュラ精霊記 Random Set`」属于曲池随机，按你的要求只写「范围内随机选择」，不列具体曲目。

### 7.8 已废弃：占位符方案（保留记录，别再走一遍）

最初的方案是在 `condition/2-air` 为空时写一份假数据（每级 2 个组曲、每曲 3 首假歌），
并用 `placeholder: true` 让 UI 显示提醒。**已经删除**：

- `build.py` 里的 `build_classes_placeholder()` 和 `CLASS_COLORS` 字典都没了
- `classes.json` 现在只由 `gen_classes.py` 从真实 XML 生成
- 保留 `placeholder` 字段只是为了让「同步到旧数据」这种情况能被 UI 识别出来

教训：占位数据会制造「看起来有数据其实是假的」的假象。宁可让页面空着，
也不要填假数据——`check_classes.py` 现在会把 `placeholder: true` 视为异常。

---

## 8. 落雪查分器导入

### 8.1 结论先行

**手动打勾是唯一可信来源；落雪导入是「尽力而为的辅助建议」。**

理由见 2.4：ORIGIN 的 30 首里 21 首在 `scores` 接口中**没有任何时间信息**。

### 8.2 三个接口的实际能力

| 接口 | 能否判断「更新后打过」 | 说明 |
|---|---|---|
| `GET /player/{fc}/recents`（最近 50 首） | ✅ **可以** | 有 `play_time`，真实游玩流水。但**只有最近 50 首** |
| `GET /player/{fc}/score/history` | ✅ 可以 | 按 `upload_time` 倒序的上传历史，含无 `play_time` 的成绩更新 |
| `GET /user/chunithm/player/scores`（个人 API） | ⚠️ **只能判断「从未打过」** | 每谱面汇总后的成绩 |

### 8.3 导入流程（**按你的新要求修订**）

**关键修订：只检查门要求的那几首歌，其他歌全部不管。**

```
遍历【当前门 requirement 里列出的 songId 列表】：
  （playAnyOfEach 则遍历所有分组的全部候选曲；
    items / class / auto / manual 类型的门不参与导入）

  ① 在 /recents（最近50首）里出现，且 play_time >= releaseDate
        → ✅ 「确认已达成」，可直接打勾

  ② 在 /scores 里完全没有任何记录
        → ❌ 「确认未达成」，保持未打勾

  ③ 在 /scores 里有记录，但 play_time 和 last_played_time 都为空
        → ❓ 记入「无法判断」列表

  ④ 在 /scores 里有记录，但时间戳都早于 releaseDate
        → ❓ 记入「无法判断」列表
```

**全部检查完成后，一次性弹提示**（你要求「全部检查完后一起弹即可」）：

```
┌────────────────────────────────────────────┐
│  导入结果                                   │
├────────────────────────────────────────────┤
│  ✅ 确认已达成      2 首                     │
│  ❌ 确认未达成      9 首                     │
│  ❓ 无法判断       19 首                     │
│                                            │
│  以下 19 首在查分器里查不到游玩时间，         │
│  无法确认是否在 2026-09-10 之后打过。        │
│  请自己确认后手动打勾：                      │
│                                            │
│   · Gate of Fate            （有成绩）      │
│   · Anemone                 （有成绩）      │
│   · The wheel to the right  （有成绩）      │
│   · ...                                    │
│   · After the rain          （无成绩）      │
│                                            │
│           [ 应用可确认的 2 首 ]  [ 关闭 ]   │
└────────────────────────────────────────────┘
```

**明确不做**：不自动把「无法判断」的曲子打勾。宁可让你多看一眼。

### 8.4 时间处理

- API 返回 **UTC**，转成**手机本地时间**再和 `releaseDate` 比较（你要求按手机时间判断）
- `releaseDate` 无时区后缀，按手机本地时间解析
- 比较用 `>=`（含边界）

### 8.5 密钥处理（安全铁律）

| 规则 | 实现 |
|---|---|
| 密钥**不进** APK、不进仓库、不进 CI | CI 完全不碰密钥 |
| 每个用户填自己的 | 「从落雪查分器获取数据」**点下去才弹窗索要** |
| 加密存储 | `EncryptedSharedPreferences` |
| 可清除 | 设置页「清除密钥」按钮 |
| 不打印 | 日志永远打码 |

**调用**：`GET https://maimai.lxns.net/api/v0/user/chunithm/player/scores`，Header `X-User-Token: <个人 API 密钥>`
密钥生成入口：[账号详情页](https://maimai.lxns.net/user/profile)（app 内写成可点击说明）

---

## 9. 在线数据同步

### 9.1 需求（你提出）

> json 可以设为自动从 github 仓库中获得，确保不用更新 apk 就能更新 json，同时保存到本地，没网时直接用本地的 json，加个手动同步的按钮

### 9.2 仓库已转 public ✅

在线同步的来源是 `raw.githubusercontent.com`。**私有仓库的 raw 链接需要 token 才能访问**（我不建议把 token 编进 APK——你朋友装了就拿到你的 token）。

**你已把 `lvchecker` 转成 public**（API 实测 `"private": false`），所以直接可用。

附带好处：

1. 这个仓库里**没有任何隐私内容**——只有 Flutter 源码、`data/*.json` 和 82 张图
2. 你的**进度存档永远不上传**（只存手机本地）
3. 你的落雪密钥**不进仓库**
4. **朋友装 APK 后也能直接同步更新**
5. 顺带解决了「朋友怎么下载 APK」——public 仓库的 Release 无需登录

### 9.3 同步地址（**顺序即优先级，GitHub 优先、Gitee 兜底**）

| # | 源 | 实际地址（以 `gates.json` 为例） | 备注 |
|---|---|---|---|
| 1 | GitHub Pages | `https://gzlxz190614.github.io/lvchecker/data/gates.json` | 需手动启用一次 Pages |
| 2 | GitHub Contents API | `https://api.github.com/repos/GzLxz190614/lvchecker/contents/data/gates.json?ref=main` | 匿名 60 次/小时/IP |
| 3 | jsDelivr | `https://cdn.jsdelivr.net/gh/GzLxz190614/lvchecker@main/data/gates.json` | |
| 4 | raw | `https://raw.githubusercontent.com/GzLxz190614/lvchecker/main/data/gates.json` | 国内常被拦 |
| 5 | githack | `https://raw.githack.com/GzLxz190614/lvchecker/main/data/gates.json` | 国内常被拦 |
| 6 | **Gitee 镜像** | `https://gitee.com/gzlxz190614/lvchecker/raw/main/data/gates.json` → 302 → `https://raw.giteeusercontent.com/...` | 国内兜底，无配额 |

同样的 4 个文件：`meta.json` / `gates.json` / `linklevels.json` / `classes.json`。

> **分支名是 `main`**（Gitee 建仓库的传统默认是 `master`，但这个仓库在网页上改过）。
> 实测 `raw.giteeusercontent.com/gzlxz190614/lvchecker/raw/main/data/gates.json`
> 返回 200 且 `dataVersion` 正确。分支名写错的表现是**稳定的 404**，不是偶尔失败。
>
> Gitee 那条会**先 302 到独立域名**，所以 `GiteeSource` 把两条路都试一遍，
> 并把各自的原因都报出来——这样能区分「404 = 忘了推镜像」和「域名不通」。见 Q16。

### 9.4 同步逻辑

```
App 启动
  ├─ 立即加载「本地缓存的 JSON」
  │    └─ 若本地缓存不存在（首次运行）→ 加载「APK 内置的默认 JSON」
  │
  └─ 后台尝试自动同步（不阻塞 UI）
       ├─ 成功 → 校验 schemaVersion
       │         ├─ 相同 → 覆盖本地缓存，UI 静默刷新
       │         └─ 更高 → 提示「数据格式已更新，请下载新版 APK」
       │                  （保留旧缓存继续用，不崩）
       └─ 失败（无网/超时）→ 静默忽略，继续用本地缓存
```

**不会发生的事**：同步**永远不会**碰 `ProgressStore`（用户的打勾记录）。数据更新和进度是完全隔离的两层。

**手动同步按钮**：设置页一个「立即同步数据」按钮，显示上次同步时间、本地缓存的数据版本、
每个文件的**来源与版本**、以及失败原因。

**版本漂移检测**（Q16）：每个文件的结果都记录「哪个源提供的 + 那份数据的 `dataVersion`」。

- 与缓存里的版本号**相同** → 记「无变化」，不写盘。所以 Gitee 上的旧镜像**不会**被当成新数据。
- 设置页的连通性测试会列出**每个源返回的版本号**；出现两个不同版本就标红提示。
  这是「某个仓库忘了推」唯一的可见信号——那种情况下源是通的、只是内容旧。

**首次运行体验**：APK 内置的 JSON 就是我这次生成的那份，所以**装上就能用，不需要联网**。

---

## 10. UI 设计

### 10.1 整体结构

**每个门一页，左右滑动换页**（`PageView`）。

```
← 滑动 →  ①ORIGIN  ②AIR  ③STAR  ...  ⑬UNIVERSE  ⑭奖励乐曲
```

页面顺序按 `order` 字段（1～14）。**第 14 页（奖励乐曲）只有前 13 个门全部已解锁后才出现。**

### 10.2 单页布局（自上而下）

```
┌────────────────────────────────────────────────┐
│  Linked GATE ORIGIN                   已解锁    │ ← ①标题（左）+ 状态（右对齐）
├────────────────────────────────────────────────┤
│  ▸ 解锁条件                                     │ ← ②可折叠，默认折叠
├────────────────────────────────────────────────┤
│  需要完成的曲目                        9 / 30   │
│  ┌────────┐ ┌────────┐ ┌────────┐              │
│  │  曲绘   │ │  曲绘   │ │  曲绘   │              │ ← ③图片 + 名称 卡片
│  │        │ │        │ │        │              │    点一下=完成
│  ├────────┤ ├────────┤ ├────────┤              │
│  │My First│ │Teriqma │ │Invitat.│              │
│  │ Phone  │ │        │ │        │              │
│  │cubesato│ │owl＊tree│ │れるりり │              │
│  └────────┘ └────────┘ └────────┘              │
│  ...（未完成在前，已完成沉底）                    │
├────────────────────────────────────────────────┤
│  BOSS  神鳴 / Rígr feat. 光吉猛修                │ ← ④达成解锁条件后才显示
│  BASIC 6   ADV 10.5   EXP 14.5   MAS 15.6       │    未达成则整块不显示
│  · Link LEVEL V   MASTER  Life 300    ← 已过时灰 │
│  · Link LEVEL IV  MASTER  Life 1000   ← 当前高亮 │
└────────────────────────────────────────────────┘
```

**四个区块的规则**：

| # | 区块 | 默认状态 | 显示条件 |
|---|---|---|---|
| ① | 门名 + 状态 | 常驻 | 总是 |
| ② | 解锁条件描述 | **折叠** | 总是（可展开看全文） |
| ③ | 勾选卡片 | 展开 | 总是 |
| ④ | BOSS + 通关条件 | **折叠** | **仅当解锁条件已达成**；未达成则**整块不显示** |

第 ④ 块「未达成就不显示」是你明确要求的——不是灰掉，是**根本不渲染**。

### 10.3 解锁条件区块：折叠样式

你要求「类似 mkdocs-material 的 admonitions」。所以：

```
折叠时：
  ▸ 解锁条件

展开后：
  ┌─ 解锁条件 ─────────────────────────────┐
  │ 2026-09-10 更新后，把这 30 首各打一次    │
  │ （难度与分数不限）                       │
  │                                        │
  │ [待确认]  ← 仅当 conditionSource ≠ official
  │ ▸ 查看游戏原文（conditionOriginal）      │ ← 二级折叠
  └────────────────────────────────────────┘
```

- 用**左侧色条 + 浅色底 + 标题**的样式（admonition 风格）
- 默认**折叠**
- 标题前的三角图标旋转动画
- **长文本可滚动**（你要求）：内容超过 6 行时内部滚动，不截断

### 10.4 卡片与「已完成」效果

**卡片样式**：图片（曲绘/角色图/服装图）+ 名字的通用卡片，网格排列。
**图片在上、文字在下**；点一下卡片 = 标记完成（不需要额外的勾选框）。

> ⚠️ **文字排版要求（M0 预览时发现的坑）**：长曲名/长曲师名**绝不能按固定字符数截断**。
> 实测 `今ぞ♡崇め奉れ☆オマエらよ！！～姫の秘メタル渇望～` 和
> `あべにゅうぷろじぇくと feat.佐倉 紗織　produced by ave;new` 这类名字，
> 按字符数截断要么读不全、要么溢出到相邻卡片。
> **必须用 `TextPainter` / `LayoutBuilder` 按真实可用宽度测量。**
> 曲名允许 2 行，曲师名 1 行截断。
> 实测数据里最长的曲名是 **22 个全角字符**，最长的曲师名是 **44 个字符**（半角混合）。

**点击行为**：

| 状态 | 表现 |
|---|---|
| 未完成 | 正常显示 |
| 完成后 | 加**半透明白色遮罩** + 居中「**已完成**」文字 + **移到列表最后** |
| 再次点击 | 恢复为未完成，移回原处 |

**列表规则（已定稿）**：

- **默认显示全部条目**，不做筛选标签
- 排序：**未完成的在前，已完成的在后**（同组内保持原顺序）
- 所以第一屏永远是「还差什么」，已完成的沉到底部

**排序稳定性**：勾选/取消勾选时用**带动画的列表重排**（`AnimatedList` 或 `implicit animation`），
避免条目瞬间跳走导致误触到相邻项。


### 10.5 通关条件区块：三态显示

你问「未开启的条件你觉得怎么样好」。我的方案：

| 档位状态 | 显示 |
|---|---|
| **已过时**（`from` 早于今天） | **灰色**文字 + 灰色左边框，可点开看历史 |
| **当前**（今天落在该档区间内） | **彩色**（用该档判定色的强调色）+ 加粗 + 左侧实心竖条 + 右侧「当前」标签 |
| **未开启**（`from` 为 null 或晚于今天） | 虚线边框 + 灰色文字 + `from` 位置显示「**日期未公布**」 |

**关键**：未开启的档位**不隐藏**，因为你能看到「以后会放宽到什么程度」，这对规划很有用。但视觉上要明显弱于当前档，避免误读。

默认**所有档位折叠**，展开后按 V→I（或 ∞→I）倒序显示，当前档自动滚动到可见位置。

### 10.6 AIR 门专用 UI（段位）

**双层折叠框**（沿用「图片 + 名称」卡片，点一下 = 该组曲完成）：

```
┌─ ▸ Ⅰ   #3D66F2                     0/5 组曲 ─┐   ← 等级折叠框（左侧竖条用等级色）
├─ ▾ Ⅱ   #0DB991                     2/4 组曲 ─┤
│  ┌─ ▸ 组曲标题 A                              ┐ │
│  ├─ ▾ 组曲标题 B                              ┤ │
│  │   ┌────┐ ┌────┐ ┌────┐                     │ │   ← 3 张卡片（图 + 名），只读
│  │   │曲绘│ │曲绘│ │曲绘│                     │ │
│  │   ├────┤ ├────┤ ├────┤                     │ │
│  │   │曲名│ │曲名│ │曲名│                     │ │
│  │   └────┘ └────┘ └────┘                     │ │
│  │   ┌──────────────────────────────────────┐ │ │
│  │   │     点一下整块 = 该组曲已完成          │ │ │   ← 完成目标 = 整个组曲
│  │   └──────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────┘ │
├─ ▸ Ⅲ   #F2AA00                     0/6 组曲 ─┤
├─ ▸ Ⅳ   #E13C29                              ─┤
├─ ▸ Ⅴ   #4A0973                              ─┤
└─ ▸ ∞   #FCDBEF                              ─┘
```

- **所有折叠框默认折叠**
- 等级折叠框标题：等级符号（用等级色）+ 「n/m 组曲」进度
- **组曲内的 3 首歌是只读展示**（告诉你这个组曲要打哪三首），
  **点击完成的目标是「整个组曲」**——因为缎带条件是「通关组曲」，不是「逐首打勾」
- 某等级全部组曲完成 → 标题右侧显示「**已达成缎带条件**」徽章
- **任一等级**全完成 → 门页顶栏显示「**已解锁**」（= 拿到缎带）
- 组曲完成后：整行前面变成绿色勾 + 标题变绿；按钮变成「取消标记」

**组曲内部的槽渲染**（对应 7.7）：

| 槽 | 渲染 |
|---|---|
| `fixed` 固定曲 | 和门页其它地方一样的曲目卡（曲绘 + 曲名 + 曲师），**只读** |
| `randomRange` 等级随机 | `random in range/cover.png` 封面 + 压在下半部的**等级大字**（`11+`），小字「等级随机」 |
| `randomPool` 曲池随机 | `random/cover.png` 封面 + 「范围内随机选择」，小字「10 选 1」 |

实现上有两个坑，代码里都写了注释：

1. **不能用 `Wrap` 混排固定曲卡和随机卡**：`ItemCard` 内部用 `Expanded`，
   而 `Wrap` 给子项的纵向约束是 unbounded，`Expanded` 会直接抛异常。
   所以两类卡都走网格布局（`ItemGrid` / `_RandomSlotGrid`），由 `childAspectRatio` 定高。
2. **不能用 `ItemGrid` 直接排组曲**：它会把「未完成」的排到前面，
   而组曲的槽是**有顺序的**（槽 1→2→3）。这里传入的 `isDone` 永远返回 false，
   让它的分组结果等于原始顺序。

### 10.7 奖励乐曲页（第 14 页）

```
┌────────────────────────────────────────────────┐
│  奖励乐曲                              锁定     │
├────────────────────────────────────────────────┤
│  ▸ 解锁条件                                     │
│  BOSS  Linked Tune / 水野健治                    │
│  BASIC 2   ADV 6   EXP 10.7   MAS 13.5          │
└────────────────────────────────────────────────┘
```

- **单独一页**，只显示 `Linked Tune` 这一首
- 排在第 14 页；**前 13 个门全部已解锁后才出现**（之前滑不到）
- 页内**没有任何勾选卡片**——不需要用户操作，纯粹展示
- **不计入**「已解锁 n/13」的进度统计

### 10.8 顶栏「已解锁」的判定逻辑（各门通用）

| tracking | 「已解锁」条件 |
|---|---|
| `songs`（playAll） | 所有 `songKeys` 都已打勾 |
| `songs`（playAnyOfEach） | 每组都至少勾了一首 |
| `items` | 所有 `itemKeys` 都已打勾 |
| `class` | **任一**等级的课程全部完成 |
| `auto` | 所有 `prerequisites` 门都「已解锁」 |
| `universe` | 手动确认（剩余血量条件由用户自己判断） |
| `manual` | 手动确认勾选框 |

**这个判定同时驱动两件事**：① 顶栏显示「已解锁」；② 第 ④ 区块（BOSS）是否渲染。

### 10.9 其他交互细节

| 设计 | 理由 |
|---|---|
| 卡片**点一下即完成**，立即落盘 | 无需保存按钮，避免忘记 |
| 提供**撤销**上一勾 | 手滑保护 |
| 完全离线可用 | 街机厅信号差；同步和导入都是主动操作 |
| 长按卡片看详情（曲师/难度/ID） | 万一歌名重名或记不清 |
| **不做**「今天建议打哪几首」 | 你说了不用 |

---

## 11. GitHub Actions 构建 APK

### 11.1 限额（GitHub Free，官方文档）

| 项目 | 私有仓库 | 公开仓库 |
|---|---|---|
| 计算分钟 | **2,000 / 月** | **免费不计** |
| Artifacts 存储 | **500 MB**（与 Packages 共用） | 不计 |
| Actions 缓存 | 10 GB / 仓库 | 同 |

来源：[GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)、[included quotas](https://raw.githubusercontent.com/github/docs/main/data/reusables/billing/actions-included-quotas.md)

- Ubuntu 2-core runner 按 **Linux 1 倍** 计费
- 一次构建 5～10 分钟 → 2,000 分钟 ≈ **每月 200～400 次构建**，用不完

> ✅ **仓库已转 public**，所以**计算分钟和存储都免费不计**（下表仅作参考）。

### 11.2 APK 只发 Release，不发 Artifacts

Flutter release APK 约 20～30 MB，Artifacts 默认保留 90 天，会吃掉那 500 MB 共享额度（推 20 次就爆）。

**做法**：APK 直接发 **GitHub Release**——Release 附件**不计入** Actions 存储，且给你一个固定下载链接。

### 11.3 触发方式：只手动

```yaml
on:
  workflow_dispatch:        # 网页点「Run workflow」
  push:
    tags: ['v*']            # 打 tag 时发 Release
```

**不配 `on: push` 到分支**——避免每次推代码都烧额度、失败还发邮件。

### 11.4 workflow 草稿

```yaml
name: Build APK

on:
  workflow_dispatch:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.35.1'    # ← 锁死版本，不用 channel: stable
          channel: stable
          cache: true

      - name: Get dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze

      - name: Build universal release APK
        run: flutter build apk --release      # ← 通用单包，兼容 Android 10

      - name: Upload to Release
        if: startsWith(github.ref, 'refs/tags/')
        uses: softprops/action-gh-release@v2
        with:
          files: build/app/outputs/flutter-apk/app-release.apk

      - name: Upload artifact (手动触发时)
        if: github.event_name == 'workflow_dispatch'
        uses: actions/upload-artifact@v4
        with:
          name: apk
          path: build/app/outputs/flutter-apk/app-release.apk
          retention-days: 7            # ← 缩短保留期，省额度
```

**两个刻意的选择**：

1. `flutter-version` **锁死具体版本**，不写 `channel: stable`。否则上游发新版可能让你的构建在最不方便的时候突然红。
2. **不加 `--split-per-abi`**（你选通用单包），保证 Android 10 老机也能装。

### 11.5 Android 10 兼容（必须显式配置）

`android/app/build.gradle.kts`：

```kotlin
android {
    defaultConfig {
        applicationId = "io.github.gzlxz190614.lvchecker"
        minSdk = 29          // ← Android 10。Flutter 默认 21，必须显式抬到 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
```

### 11.6 签名

release APK 必须签名才能安装。

- **v1～v2（自用/朋友用）**：CI 里用生成的 keystore 签名。安装时点「允许安装未知来源」。
- **要长期升级不丢数据**：签名必须**固定不变**（换签名 = 必须卸载重装 = 进度丢失）→ 需要把 keystore 存成 GitHub Secret。**v1 不做**，需要时再加。

---

## 12. 仓库文件结构

```
lvchecker/
├── .github/
│   └── workflows/
│       ├── build-apk.yml             # 手动触发 / tag 触发 → 出 APK
│       └── publish-pages.yml         # 把 data/*.json 发布到 GitHub Pages（可选源）
├── data/                            # ← 在线同步的源（各源的直链指向这里）
│   ├── meta.json                    # 全局条目元数据（157 条：曲名/曲师 + 图片路径）
│   ├── gates.json                   # 13 个门 + 1 个奖励页
│   ├── linklevels.json              # 缓和配置 + 判定色
│   └── classes.json                 # AIR 段位课程（6 CLASS / 36 组曲）
├── assets/
│   └── img/                         # 160 张 WebP / 4.13 MB
│       ├── music/{id}/jacket.webp         # 曲绘（含 WE 曲）
│       ├── chara/{id}/image.webp          # × 1（1080×1080）
│       ├── avatar/{id}/icon.webp + tex.webp # × 3
│       └── class/                         # 段位随机槽封面 × 2
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── entry.dart               # meta.json
│   │   ├── gate.dart                # gates.json
│   │   ├── link_level.dart          # linklevels.json
│   │   └── class_course.dart        # classes.json（含等级显示换算）
│   ├── data/
│   │   ├── data_loader.dart         # 内置 → 缓存 两级加载
│   │   ├── data_sync.dart           # 多源同步（UrlSource / ApiSource / GiteeSource）
│   │   ├── gate_status.dart         # 每个门是否已解锁
│   │   └── progress_store.dart      # 存档读写（SharedPreferences）
│   ├── import/
│   │   ├── progress_importer.dart   # 接口
│   │   ├── lxns_importer.dart
│   │   └── manual_text_importer.dart
│   ├── pages/
│   │   ├── gate_pager.dart          # PageView，左右滑动
│   │   ├── gate_page.dart           # 单个门的页面
│   │   └── settings_page.dart
│   └── widgets/
│       ├── item_card.dart           # 图片 + 名字 通用卡片（ItemGrid / MarqueeText）
│       ├── admonition.dart          # 折叠条件区块
│       ├── link_level_list.dart     # 通关条件三态列表
│       └── class_section.dart       # AIR 门双层折叠 + 随机槽卡片
├── tools/                           # 只在本地/CI 跑，不进 APK
│   ├── build.py                     # condition/ → data/ + assets/img/
│   ├── gen_classes.py               # condition/class/course → data/classes.json
│   ├── gen_asset_list.py            # 重新生成 pubspec 的 assets 列表（必须逐文件列）
│   ├── patch_android_manifest.py    # APK 显示名 + **INTERNET 权限**（见 Q17）
│   ├── check_dart.py                # 无本地 Flutter 时的 Dart 静态自查
│   ├── check_assets.py              # pubspec 声明 ↔ 磁盘图片双向校验（格式无关）
│   ├── check_classes.py             # 段位数据 + 等级换算回归
│   ├── check_image_format.py        # 图片格式：Pillow 能力 + 扩展名一致性
│   ├── validate.py                  # 跨文件引用完整性
│   └── preview.py                   # 生成验收预览图
├── preview/                         # 只在本地看，不进 APK
├── condition/                       # 你的原始游戏数据（只读输入，不入 git）
├── test/                            # CI 里 flutter test 跑这些
├── pubspec.yaml
├── README.md                        # 给朋友看的：怎么装、怎么用、怎么配密钥
└── DESIGN.md                        # 本文档
```

> `android/` **故意不进 git**：由 CI 里的 `flutter create --platforms=android` 现场生成，
> 再用 `sed` 改 `applicationId` / `minSdk` / 应用名。原因是手写的 gradle/AGP/Kotlin/wrapper
> 版本必须和 Flutter 版本严格配套，提交进仓库等于给自己埋一颗「某天突然构建失败」的雷。

**本地/CI 脚本一览**：

| 脚本 | 作用 |
|---|---|
| `tools/build.py` | 解析 `condition/` 的 XML → 生成 `data/*.json`；同时把 `.dds` 转成 **WebP** 并按 ID 归档。**拿到新版本游戏数据重跑即可，不用手抄曲名** |
| `tools/gen_classes.py` | 解析 36 个 `Course.xml` → `data/classes.json`，并转换两张随机封面 |
| `tools/gen_asset_list.py` | 按磁盘现状重建 `pubspec.yaml` 的 `assets:` 列表。**Flutter 的 assets 声明不是递归的**，必须逐文件列出，少一行就是「图片全部丢失」 |
| `tools/patch_android_manifest.py` | 给 `flutter create` 生成的 manifest 补应用显示名与 **`INTERNET` 权限**。漏权限时 release APK 完全不能联网，且**没有任何编译期报错**（见 Q17） |
| `tools/check_dart.py` | 本地没有 Flutter SDK，拿它做有限的静态自查（未定义类型、成员访问、展开语法、可空传参）。**它不能替代 `flutter analyze`** |
| `tools/check_assets.py` | `pubspec` 声明 ↔ 磁盘图片双向校验（声明了但没文件、有文件但没声明都报）。**扫描不写死扩展名**，换图片格式后不会静默失效 |
| `tools/check_image_format.py` | 图片格式前置条件：Pillow 是否支持 WebP、仓库里的图扩展名与实际格式是否一致（见 Q18） |
| `tools/check_classes.py` | 段位引用完整性 + **等级换算回归**（见 7.5） |
| `tools/validate.py` | 跨文件 `linkId` 引用完整性 |
| `tools/preview.py` | 生成验收预览图（`preview/*.png`），用来肉眼检查曲绘和条件文本渲染是否正常 |

---

## 13. 你的操作流程与上传指令

### 13.1 方案 A：纯网页（**推荐，不需要 SSH、不需要 Git**）

1. 打开 `https://github.com/GzLxz190614/lvchecker`
2. **Add file → Upload files**
3. 把文件/文件夹拖进去 → Commit

限制：单文件 ≤ 25 MB、单次 ≤ 100 个文件。源码几百 KB，**但 63 张曲绘可能超 100 个文件**，需要分两次传，或用方案 B。

### 13.2 方案 B：命令行 + SSH（你已验证 SSH 通）

```bash
cd /path/to/lvchecker

git init
git branch -M main
git remote add origin git@github.com:GzLxz190614/lvchecker.git
git config user.name  "GzLxz190614"
git config user.email "2075614293@qq.com"

git add .
git commit -m "feat: 连章进度 app 初版"
git push -u origin main
```

SSH 没配好时：

```bash
ssh-keygen -t ed25519 -C "2075614293@qq.com"
cat ~/.ssh/id_ed25519.pub        # 贴到 GitHub → Settings → SSH and GPG keys
ssh -T git@github.com            # 验证
```

**Gitee 镜像（国内兜底，见 Q16）**：

```bash
# 一次性添加
git remote add gitee git@gitee.com:gzlxz190614/lvchecker.git

# Gitee 也用同一套 SSH key；首次连接会问 fingerprint，答 yes
ssh -T git@gitee.com

# 首次推全量
git push -u gitee main
```

> 两个仓库的默认分支名**都是 `main`**（Gitee 侧在网页上改过默认分支）。
> 如果哪天又改回 `master`，`lib/data/data_sync.dart` 里
> `GiteeSource('gzlxz190614/lvchecker', 'main', ...)` 的第二个参数必须一起改，
> 否则 app 会一直 404。

之后每次改完数据：

```bash
git push origin main && git push gitee main
```

> ⚠️ 两个「别这么干」：
>
> - `git remote set-url --add --push origin <gitee>`：一个失败 = 整体报错，
>   而另一个其实已经推成功，会误导排查方向。
> - `git config branch.main.merge refs/heads/main` 之类去「绑定」上游：
>   `branch.<name>.merge` **同时就是上游分支的定义**，改了会让 `git pull`
>   和不带参数的 `git push` 都跑到 Gitee 去。
>
> 显式写 `git push gitee main` 最不容易出错。

### 13.3 发版拿 APK

```bash
git tag v0.1.0
git push origin v0.1.0
```

→ Actions 自动构建 → 到 `https://github.com/GzLxz190614/lvchecker/releases` 下载

或**不打 tag**：仓库页 → Actions → Build APK → Run workflow → 构建完在当次运行的 Artifacts 里下（private 仓库需登录）。

### 13.4 我这边怎么交付

**我的环境连不上 GitHub**（实测 `github.com`/`api.github.com`/`registry.npmjs.org` 全部 TLS 握手失败，`curl` 返回 `000`）。所以我**不能**帮你 push。交付方式：

1. 我把完整源码写到本地工作区
2. 打成 `lvchecker-src.zip`
3. 你按 13.1 或 13.2 上传

---

## 14. 开发阶段划分

| 阶段 | 内容 | 产物 | 可否独立交付 |
|---|---|---|---|
| **M0** | `tools/build.py` + `data/*.json`（13 个门）+ `assets/img/`（68 张图 + meta.json） | 纯 JSON + 图片，你能直接读并验证 | ✅ **已完成** |
| **M1** | Flutter 骨架 + ORIGIN 门 + 打勾存档 + PageView 翻页 | 可装 APK，ORIGIN 能用 | ✅ **核心价值达成** |
| **M2** | 其余 12 个门（`items` / `auto` / `universe` / `manual`） | 全部 Stage 1 + Stage 2 可用 | ✅ |
| **M3** | 在线同步 + 设置页 + README | 不用重发 APK 就能更新数据 | ✅ |
| **M4** | 落雪导入（只查门要求的歌 + 汇总弹窗） | 自动辅助 | ✅ |
| **M5** | AIR 段位 UI + 真实课程数据（36 个组曲 / 86 首固定曲） | 完整 | ✅ |
| **M6** | 曲绘/图片资源接入各卡片 | 观感 | ✅ |

**建议先做 M0 + M1**：M0 你能立刻检查数据对不对（纯 JSON + 图片，不用装任何东西），M1 让 ORIGIN 立刻能用。

> ✅ **M0 已完成**（2026-09-11）。验收方式见 `preview/*.png` 两张预览图。

**M0 的具体产出清单**（✅ 已生成，脚本：`tools/build.py`）：

> ⚠️ 下面是 **M0 完成时**的快照（81 条 meta / 82 张 PNG）。之后陆续接入了
> 段位课程曲目、奖励曲等，**当前实际数字是 157 条 meta / 160 张 WebP / 4.13 MB**
> （图片格式在 Q18 从 PNG 换成了 WebP，原本是 19.31 MB）。
> 每次重新生成后以 `tools/validate.py` 的输出为准。

```
data/meta.json            81 个条目的元数据（music 75 / chara 1 / avatar 3 / mission 1 / map 1）
data/gates.json           14 个页（13 个解锁条件门 + 1 个奖励乐曲页）
data/linklevels.json      13 个门的 Link LEVEL 表 + 4 个判定色
data/classes.json         6 个 CLASS / 36 个组曲（真实数据，来自 condition/class/course）
assets/img/music/{id}/jacket.png + meta.json      × 75（含 13 首 BOSS + 奖励曲）
assets/img/chara/24320/image.png + meta.json      × 1（1080×1080）
assets/img/avatar/{id}/icon.png + tex.png + meta.json  × 3
tools/build.py            数据生成 + dds→png 转换
tools/preview.py          验收预览图
tools/validate.py         数据校验
```

**最终统计**：PNG 82 张 / 10.97 MB。

**校验结果**（`tools/validate.py` + 生成时内建，全部通过）：

| 检查项 | 结果 |
|---|---|
| linkId 悬空引用 | **0** |
| 声明的图片缺失 | **0** |
| ORIGIN 30 首逐首核对 | **30/30 有图** |
| 孤儿 PNG | 0（3 个 `tex.png` 是详情页用的补充立绘，不在 `meta.json` 的 `image` 字段里，属预期） |
| 跨门重复引用 | 仅 `music:180`（同时属于 ORIGIN 和 PARADISE/光吉猛修），符合预期 |
| 被排除的「アイス」 | 未生成任何 PNG，无孤儿资源 |
| 13 首 BOSS 全部解析出精确难度 | ✅ |
| 角色立绘转出（1080×1080） | ✅ |
| 生成警告数 | **0** |

#### 修掉的 4 个数据/脚本 bug（记录备查）

| # | 问题 | 原因 | 修法 |
|---|---|---|---|
| 1 | `gates.json` 里裸数字 `51`，`meta.json` 键是 `music:51` | 两套 id 混用 | 全部统一为 `linkId` |
| 2 | 被排除的「冰淇淋」仍生成 PNG | 先转图后判归属 | 先查 meta 再用图 |
| 3 | SUN 门显示「所有乐曲游玩一遍即可」 | 直接抄了速记文本，会误导（实际 5 首） | 正式描述单列 `CONDITION_TEXT`，速记存 `conditionOriginal` |
| 4 | 角色图显示「无图」 | `dds` 在 `3-star/` 根目录，`Chara.xml` 在子目录 `chara024320/` | 查同目录 + 递归子目录 |


### 4.6 数据文件的分工（避免重复）

`gates.json` **不重复存曲名/曲绘图**，只存 `linkId` 引用；名称和图在 `meta.json` 里查一次：

```jsonc
// data/gates.json —— 只有引用
"requirement": { "type": "playAll", "songKeys": ["music:51", "music:53", ...] }

// data/meta.json —— 真正的名称与图片
"music:51": { "type": "music", "id": 51, "title": "My First Phone",
              "artist": "cubesato", "genre": "ORIGINAL",
              "works": "[ORIGINAL] Ver. CHUNITHM",
              "image": "assets/img/music/51/jacket.png" }
```

好处：

| | 说明 |
|---|---|
| 不用把 `meta.json` 的内容再抄进 `gates.json` | 避免两处不一致 |
| `"id": 51` **显式保留** | 这是**落雪查分器的 song_id**，导入功能要拿它匹配成绩 |
| 同一曲被多个门引用只存一份 | 已确认 `music:180` 被 ORIGIN 和 PARADISE 共用 |



---

## 15. 风险与已知缺口

| # | 风险/缺口 | 影响 | 应对 |
|---|---|---|---|
| R1 | ~~段位课程数据完全缺失~~ | — | ✅ **已解决**：在 `condition/class/` 下找到了 36 个 `Course.xml`，真实数据已接入（见 7.3）；旧的占位符方案已删除（见 7.8） |
| R2 | 国服门开放日期未知（除 ORIGIN/AIR） | 日期判断不准 | `releaseStatus: notYetOpen`，不猜 |
| R3 | 国服缓和日期表未知 | 无法自动算当前 Link LEVEL | 用户手动选；JSON 留 null 等填 |
| R4 | `scores` 接口时间信息缺失（21/30 首） | 自动打勾不可靠 | 只查门要求的歌 + 三态 + 汇总弹窗（见 8.3） |
| R5 | CRYSTAL 门国服条件未知 | 无法给准确条件 | 标「条件待确认」+ 手动确认 |
| R6 | ~~私有仓库的 raw 链接需 token~~ | — | ✅ **已解决**：仓库已转 public |
| R7 | ~~NEW 门有 4 个 avatar 条目，官方只要 3 件~~ | — | ✅ **已解决**：第 4 件是「アイス」，已排除 |
| R8 | Flutter 版本更新导致 CI 挂 | 构建失败 | workflow 锁死 Flutter 版本 |
| R9 | Release APK 签名不固定 | 换签名要卸载重装（丢进度） | v1 接受；需要时加 keystore Secret |
| R10 | 图片文件数超网页上传 100 文件限制 | 上传麻烦 | 用 SSH 推送；或分两批 |
| R11 | `MISS` 判定色是纯黑 `#000000` | 深色背景下看不见 | UI 加描边或浅色卡片底 |
| R12 | 预览图的字体回退 | 仅影响本地预览图，不影响 APK | 已实现逐字回退（见 14 节 M0 说明） |
| R13 | ~~RE:VERSE 的 11 首是「游玩」还是「拿到」~~ | — | ✅ **已解决**：见 Q15 |
| R14 | ~~release APK 没有 `INTERNET` 权限，导致热更新全部失败~~ | — | ✅ **已解决**：见 Q17。构建期补权限 + **用 aapt 查成品 APK** 断言 |

### Q17 结论：release APK 必须显式声明 `INTERNET`（**最隐蔽的一个坑**）

**现象**：手机上浏览器能正常打开 raw 链接，但 app 里「测试各数据源的连通性」
显示 **6 个源全部「域名解析失败」**，连国内域名 Gitee 都不通。

**根因**：`flutter create` 生成的模板里，`INTERNET` 权限**只写在 debug/profile 的
`AndroidManifest.xml`** 里（那是给 Flutter 工具连 VM Service / 热重载用的），
**主 manifest 里没有**。而 release APK 用的是主 manifest → **完全不能联网**。

而它的表现**非常像「被墙」**：

| | 缺权限 | 真被墙 |
|---|---|---|
| 失败范围 | **所有域名一起失败**（包括国内域名） | 只有部分域名失败 |
| 错误信息 | `Failed host lookup: 'xxx'` | 同左 |
| 浏览器能否打开 | **能**（浏览器不受 app 权限限制） | 可能能，可能不能 |

**「所有域名一起失败 + 浏览器正常」就是缺权限的指纹。** 当时第一反应是
「国内网络把 githubusercontent 拦了」，于是花了不少工夫加 Gitee 镜像 ——
方向虽然不算错（Gitee 确实有独立价值：绕开 Contents API 的 60 次/小时配额），
但**它解决不了这个 bug**，因为根本原因是权限，不是域名。

**修法**（`tools/patch_android_manifest.py` + workflow 两步）：

1. `flutter create` 之后，给主 manifest 插入
   `<uses-permission android:name="android.permission.INTERNET" />`，并改显示名
2. **构建出 APK 后用 `aapt dump permissions` 查成品**，没有这个权限就让构建失败

`INTERNET` 是 normal 权限，安装时即授予，**不需要**运行时申请。

#### 由此得到的两个通用教训

1. **构建成功 ≠ 功能可用。** 这个 bug 全程没有任何编译期报错，
   `flutter analyze`、`flutter test`、`flutter build` 全部通过。
   凡是有「运行时才有意义的配置」（权限、proguard、签名、manifest 合并），
   都应该**对最终产物做断言**，而不是只对源文件做断言。
2. **补丁脚本要能在本地跑。** 这一步最初是用 `sed -i` 内联写在 workflow 里的，
   但 `sed` 的插入命令在本地没法验证（Windows 上跑不起来），只能推到 CI 试错。
   而它失败时 APK 照样能构建成功 —— 又是一个「假绿勾」。
   改成 Python 之后可以在本地跑真实模板验证（含幂等性和失败路径）。

> 同类风险提醒：`publish-pages.yml` 的 `enablement: true` 那个失败也是同一类问题——
> 构建/部署流水线「看起来跑了」，但产物其实不对。这类问题只能靠**验证产物**发现。

### Q18 结论：图片格式改为 WebP（省 15 MB），质量用 PSNR 量化过

**动机**：图片占了 APK 的绝大部分体积（19.31 MB / 约 56 MB）。

**实测数据**（160 张图）：

| 格式 | 体积 | 相对 |
|---|---|---|
| PNG | 19.31 MB | — |
| **WebP q=82** | **4.13 MB** | **省 78.6%** |

**质量不能凭感觉说「差不多」**，所以做了量化对比（对同一张图做
「编码成 WebP → 解码回来」与原图逐像素比较，算 PSNR）：

| quality | 平均 PSNR | 最低 PSNR | 体积 |
|---|---|---|---|
| 75 | 37.83 dB | 32.43 dB | 304 KB |
| **82** | **42.33 dB** | **35.48 dB** | **358 KB** |
| 90 | 42.39 dB | 36.72 dB | 423 KB |
| 95 | 43.86 dB | 37.24 dB | 482 KB |

判据：**PSNR > 40 dB 基本看不出差别**；35~40 dB 静态图仔细看能察觉；< 35 dB 可能在
渐变/噪点处看到块状。q=82 过了 40 dB 这条线，而 q=90/95 只多 0.1~1.5 dB
却要多占 18~34% 空间 —— **q=82 是明显的最优解**。

**兼容性**：Android 4.0+ 原生支持解码 WebP（本项目 minSdk 29）。但注意
**Flutter 的 `Image.asset` 是按文件扩展名选解码器的**，所以路径里的扩展名
必须一起改 —— 这正是下面那条「改格式时容易漏的地方」。

**实现方式**：`tools/build.py` 里的 `IMG_EXT = "webp"` 是**唯一**的格式开关，
`gen_classes.py` / `gen_asset_list.py` 都从它 import，避免多处各写一份而漂移。
换回 PNG 只需改这一个常量 + 删掉旧图重跑。

**改格式时容易漏的地方**（第一次改就踩了两个）：

| 漏掉的地方 | 后果 |
|---|---|
| `data/*.json` 里的 `"image"` 路径 | 路径指向不存在的 .png（由 build.py 生成，会跟上） |
| `pubspec.yaml` 的 assets 列表 | 同上（由 gen_asset_list.py 重建） |
| `tools/check_assets.py` 的 `rglob("*.png")` | **变成假绿勾**：换格式后它扫不到任何图，于是「全部已声明」永远成立。已改成按已知图片后缀集合过滤 |
| `tools/validate.py` 的图片统计 | 体积统计恒为 0（同样已改成格式无关） |
| 仓库根目录的 `icon.png` | **绝对不要动**：那是 `flutter_launcher_icons` 的输入，它按扩展名找文件 |

**顺带加了 `tools/check_image_format.py`**，挡住两类编译期发现不了的问题：

1. **CI 的 Pillow 没编 WebP 支持** → `build.py` 会写不出图。官方 wheel 一般都带，
   但不能假定；脚本会真的编一张 8×8 验证。
2. **扩展名与实际格式不符**（手工放错文件、改格式没清干净）→ Flutter 解不开。

> 这个脚本最初写成「抽查前 12 张」，结果故意放一张「扩展名 .webp 实际是 PNG」
> 的坏图进去，**它通过了** —— 因为坏图排在第 51 个。改成全量检查（实测 160 张
> 只要 0.9 秒），并把这句教训写进了代码注释。
> **抽查省下的时间远不值得漏报，而这个检查存在的唯一意义就是别漏报。**

---

## 16. 待定/需要你拍板

> **当前状态：无待定项。** 全部问题已定稿，可以直接开工 M1。

| # | 问题 | 状态 |
|---|---|---|
| ~~Q9~~ | ~~NEW 门到底要哪 3 件服装？~~ | ✅ **已解决**：要 61（服）/ 62（頭）/ 67（ランドセル）；65（アイス）排除 |
| Q10 | 曲目区默认显示全部还是只未完成？ | ✅ **已定稿**：**显示全部**，未完成在前、已完成在后，不做筛选标签 |
| Q11 | 采纳**方案 A（现在就转 public）**吗？ | ✅ **已完成**：仓库已是 public（实测 `"private": false`） |
| ~~Q12~~ | ~~AIR 门在没有段位数据前怎么办？~~ | ✅ **已解决**：占位符方案已废弃；`condition/class/course` 里找到了真实的 36 个组曲，直接接入（见 7.3） |
| Q13 | 要不要把图片内置进 APK？ | ✅ **已定稿**：要。**不用在线曲绘**，全部本地 dds 转换（见 Q18：格式已从 PNG 换成 WebP） |
| Q14 | `source` 字段（原 `confirmed`）保留吗？ | ✅ **保留**，防止以后忘了哪条日期是猜的 |
| ~~Q15~~ | ~~RE:VERSE 的 11 首要「打过」还是「拿到」？~~ | ✅ **已解决**（见下） |

### Q16 结论：加 Gitee 镜像做国内兜底（GitHub 优先）

**背景**：你手机上实测 `raw.githubusercontent.com` / `raw.githack.com` 全部 DNS 解析失败，
jsDelivr 在助手侧可用但你手机上不通，只有 `github.com` 与 `api.github.com` 能解析。

**核实过的事实**（都会影响方案选择）：

| 事实 | 来源 | 影响 |
|---|---|---|
| Gitee 公开仓库的 raw **会被强制重定向**到独立域名 `raw.giteeusercontent.com` | [Gitee 帮助中心](https://help.gitee.com/repository/file-operate/raw) | 和 `raw.githubusercontent.com` 是**同构**的独立域名。所以「Gitee 通不通」本质上要测的是那个域名 |
| Gitee **Pages 已下线** | [蓝点网](https://www.landian.news/archives/103754.html)、[php.cn](https://www.php.cn/faq/505484.html) | 不能拿它替代 GitHub Pages，只有 raw 一条路 |
| GitHub Contents API 匿名限额 **60 次/小时/IP** | [GitHub Docs](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) | 手机在运营商 NAT 后是共享 IP，4 文件/次很容易把额度磨光 → 这才是加 Gitee 的**主要**理由，不只是换域名 |
| Gitee raw 是普通 GET + CDN 缓存（60~300 秒），无匿名配额 | 同上 Gitee 文档 | Gitee 源可以被反复请求而不会「用着用着就 403」 |

**定稿**：

1. **源顺序 GitHub 优先，Gitee 排最后**（第 6 位）。理由是数据以 GitHub 那份为准
   （开发和发 APK 都在那边），Gitee 只做兜底。
2. **Gitee 用独立 remote + 手动 `git push`，不配任何 CI 密钥。**
   - 自动镜像需要存 `GITEE_TOKEN`，而 token 会过期，过期后表现为「镜像悄悄停了」——
     这种静默腐烂比手动推的「忘了推」更难排查
   - 手动推保持仓库「零密钥」的干净状态（这正是当前仓库的真实优势）
3. **全仓库镜像**（含 `assets/img/` ~4 MB）。只镜像 `data/` 看似干净，但会把
   「一条 push」变成「一个需要维护的同步动作」，把自动化的复杂度又请回来了。
4. **必须做版本漂移检测**，否则两个仓库必然悄悄分叉。手段：
   - `SyncResult` / `SourceProbe` 都带上源的 `dataVersion`
   - 同步时比对缓存里的 `dataVersion`：版本相同就记「无变化」（所以旧镜像不会被当成新数据写入）
   - 设置页显示「本地缓存」版本
   - 连通性测试里若有多个不同版本，直接标红「各源数据版本不一致」——
     这是「Gitee 忘了推」**唯一的可见信号**

**明确不做**：`git remote set-url --add --push` 那种「一次推到两个仓库」的配法。
它会让「一个失败 = 整体报错」，而另一个其实已经推成功，容易误导排查方向。

**代码位置**：`lib/data/data_sync.dart` 的 `GiteeSource`（会分别试
`gitee.com/.../raw/...` 与 `raw.giteeusercontent.com`，并把两条通路各自的原因都报出来，
这样能区分「404 = 忘了推镜像」和「域名不通」）。

### Q15 结论：RE:VERSE 按「全部游玩过」处理

你的说明解决了这个疑问：

> 解锁 RE:VERSE 要跑的地图为 Secret AREA: MUSIC GAME EX，其中到达乐曲后，
> 要想获得乐曲需要通关课题曲，也就是该乐曲，所以要是能完成地图就说明所有乐曲都玩过一遍了

**也就是说：拿到歌 ⟺ 通关了该歌。两种理解结果相同。**

所以实现上：

- 保持 `tracking: "songs"`，列 11 首让用户打勾
- `conditionText` 已改成完整说明：

  > 通关 X-VERSE 后解锁地图 Secret AREA: MUSIC GAME EX。卡内每首乐曲都要通关课题曲才能获得，
  > 所以跑完地图拿全 11 首即等于全部游玩过一遍

- **UI 上额外给一个「整张地图已完成」的快捷勾选**：一次把 11 首全勾上（因为实际拿到地图全清就等于全打了）

---

## 附：参考来源

- [RemyWiki — 中二节奏 2027 (China)](https://silentblue.remywiki.com/CHUNITHM:2027_(China)) — 国服稼働日、新增曲、门信息
- [RemyWiki — Linked VERSE](https://silentblue.remywiki.com/CHUNITHM:Linked_VERSE) — 全部门条件、Link GAUGE 表
- [RemyWiki — CHUNITHM X-VERSE-X (Asia)](https://silentblue.remywiki.com/CHUNITHM:X-VERSE-X_(Asia)) — 亚服信息（国服基础）
- [SEGA 官方 — Linked VERSE のゲート解放条件とストーリーを公開！](https://info-chunithm.sega.jp/12052/) — 日服官方条件表
- [落雪查分器 — 开发者入驻指南](https://maimai.lxns.net/docs/developer-guide) — 三种鉴权
- [落雪查分器 — 中二节奏 API 文档](https://maimai.lxns.net/docs/api/chunithm) — 接口与曲绘资源
- [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) — 免费额度
- 本地 `condition/`（13 个门）— 你提供的游戏数据
- 本地 `lx_test.txt` — 落雪 API 实际返回样本（639 条）
