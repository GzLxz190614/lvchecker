# lvchecker · 连章进度

《中二节奏 2027》**连章（Linked VERSE）**门解锁进度记录工具。

用来解决一个问题：**「这门还差哪几首歌没打？」**

站在机台前翻菜单找歌很不方便，还容易忘记哪首打过。这个 app 把每个门需要的曲目/角色/服装列成卡片，打过的点一下勾掉，自动记住进度。

> ⚠️ **当前状态：数据层完成（M0），App 首次可用（M1）。**
> 已经有可安装的 APK，但只实现了 ORIGIN 门；其余门会陆续补上。

---

## 安装 APK

APK 由 GitHub Actions 在云端构建（**本地不需要装 Flutter 或 Android SDK**）。

### 方式一：下载 Release（推荐）

打 tag 后会自动发布到 Releases：

```
https://github.com/GzLxz190614/lvchecker/releases
```

手机浏览器直接点开下载安装即可。

### 方式二：手动触发构建

仓库页 → **Actions** → **Build APK** → **Run workflow**。
构建完（约 5～10 分钟）在该次运行的 **Artifacts** 里下载 `lvchecker-apk`。

> `workflow_dispatch` 有个 `skip_tests` 开关：万一 analyze/test 本身出问题卡住构建，
> 勾上它能跳过检查直接出包。

### 安装注意

- APK 用调试签名，安装时需要允许「**未知来源应用**」
- 兼容 **Android 10 及以上**（`minSdk = 29`）
- 包名：`io.github.gzlxz190614.lvchecker`

### 自己构建

```bash
flutter create --platforms=android --org io.github.gzlxz190614 .
flutter pub get
flutter build apk --release
```

> ⚠️ `android/` 目录**不在仓库里**，由上面第一条命令生成。
> 这样做是为了避免在仓库里维护 gradle / AGP / Kotlin / wrapper 四个版本号——
> 它们必须和 Flutter 版本严格配套，手写极易导致 CI 失败。
> 详见 `.github/workflows/build-apk.yml` 的注释。

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
├── data/                  ← 在线同步的源（直链指向这里）
│   ├── meta.json          157 个条目的元数据（曲名/曲师/图片路径/难度）
│   ├── gates.json         14 页的完整定义
│   ├── linklevels.json    Link LEVEL 缓和配置 + 判定色
│   └── classes.json       AIR 段位课程（6 个 CLASS / 36 个真实组曲）
├── assets/
│   └── img/               160 张 WebP / 4.13 MB（曲绘 / 角色立绘 / 服装 / 段位封面）
│       ├── music/{id}/    jacket.webp
│       ├── chara/{id}/    image.webp
│       ├── avatar/{id}/   icon.webp + tex.webp
│       └── class/         段位随机槽的封面 × 2
├── tools/                 ← 只在本地/CI 跑，不进 APK
│   ├── build.py           从 condition/ 生成 data/ 与 assets/img/
│   ├── gen_classes.py     从 condition/class/course 生成 classes.json
│   ├── gen_asset_list.py  重建 pubspec 的 assets 列表（必须逐文件列）
│   ├── check_dart.py      没有本地 Flutter 时的 Dart 静态自查
│   ├── check_assets.py    pubspec 声明 ↔ 磁盘图片双向校验
│   ├── check_classes.py   段位数据 + 等级换算回归
│   ├── check_image_format.py  图片格式（Pillow 能力 + 扩展名一致性）
│   ├── validate.py        数据完整性校验
│   └── preview.py         生成验收预览图（本地用）
├── lib/                   ← Flutter 源码
│   ├── main.dart
│   ├── theme.dart
│   ├── models/            entry.dart / gate.dart / link_level.dart / class_course.dart
│   ├── data/              data_loader.dart / data_sync.dart / progress_store.dart / gate_status.dart
│   ├── pages/             gate_pager.dart / gate_page.dart / settings_page.dart
│   └── widgets/           item_card.dart / admonition.dart / boss_section.dart / class_section.dart
├── test/                  模型解析单测（含段位等级换算回归）
├── .github/workflows/     build-apk.yml（APK 只在这里构建）
├── DESIGN.md              设计文档（数据模型 / UI / CI / 全部决策）
└── .gitignore
```

**未纳入版本控制的目录**（见 `.gitignore`）：

| 目录 | 为什么不提交 |
|---|---|
| `condition/` | 从游戏解包出来的原始资源（谱面 `.c2s`、曲绘与立绘 `.dds`、定义 `.xml`）。**美术与谱面资源版权属于 SEGA，不适合在公开仓库二次分发。** |
| `preview/` | 本地验收预览图，可用 `tools/preview.py` 随时重新生成 |
| `android/` | 由 CI 用 `flutter create` 按当前 Flutter 版本生成，避免手写 gradle 版本号 |

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
  "image": "assets/img/music/51/jacket.webp"
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
python tools/build.py          # 重新生成 data/ 与 assets/img/
python tools/gen_classes.py    # 只重生成段位数据（build.py 也会自动调用）
python tools/validate.py       # 跨文件引用完整性
python tools/check_classes.py  # 段位数据 + 等级换算
python tools/check_assets.py   # pubspec 声明 ↔ 磁盘图片
python tools/check_image_format.py  # 图片格式（Pillow 是否支持 WebP 等）
python tools/preview.py        # 生成预览图到 preview/（本地用，不入库）
```

`build.py` 会自动：解析 XML → 生成 JSON → 把 `.dds` 转成 **WebP** → 按 ID 归档 →
写 `meta.json` → **重建 `pubspec.yaml` 的 assets 列表**。

> **图片为什么是 WebP**：160 张图实测 **19.31 MB → 4.13 MB（省 78.6%）**。
> 质量用 PSNR 量过：WebP q=82 平均 **42.3 dB**（>40 dB 基本看不出差别），
> 而 q=90/95 只多 0.1~1.5 dB 却要多占 18~34% 空间，所以定在 82。
> 想换回 PNG：把 `tools/build.py` 的 `IMG_EXT` 改成 `"png"`，删掉旧图重跑即可。

> ⚠️ 最后一步（`gen_asset_list.py`）不能跳过。Flutter 的 `assets:` 声明**不是递归的**，
> 写 `assets/img/music/` 一个目录**不等于**声明了里面的文件。少声明任何一张图，
> app 里那张图就会显示「图片丢失」——这个坑踩过三次，所以现在由脚本按磁盘现状生成。

### 段位（CLASS）课程数据

AIR 门的解锁条件是「获得一个段位缎带」，即**任一 CLASS 内所有组曲通关**。
课程数据来自 `condition/class/course/*/Course.xml`（36 个组曲，6 个 CLASS），
由 `tools/gen_classes.py` 生成 `data/classes.json`。

组曲里的槽有三种：

| 槽 | 显示 |
|---|---|
| 固定曲目 | 曲绘 + 曲名 + 曲师（只读，告诉你这组要打哪几首） |
| 等级随机 | `!` 封面 + 游戏内等级（例 `11+`） |
| 曲池随机 | `?` 封面 + 「范围内随机选择」 |

**进度粒度是「组曲」而不是「单曲」**：点组曲标题即标记该组曲通关，
因为缎带条件本来就是「通关整个组曲」。

> ⚠️ 一个容易搞错的地方：XML 里等级随机槽只给内部 ID（`fromLevel = 19/20/21`），
> 而游戏内显示的是 `Lv10 / Lv10+ / Lv11`（换算：`Lv = (ID-19)/2 + 10`，**每 2 个 ID 涨 1 级**）。
> 写成「ID − 9」在 `ID_19` 上看着是对的，但 `ID_20` 会算成 11 而不是 10+。
> 这个错误肉眼看不出，所以 `tools/check_classes.py` 和 `test/class_course_test.dart`
> 都把这张对应表钉死成了回归测试。

`classes.json` 里的 `placeholder` 字段正常情况下是 `false`。
APP 只有在它变成 `true` 时才会在 AIR 门顶部弹一条警告——那说明同步到的是旧数据或生成失败了。

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

## 在线数据更新（热更新）

数据文件通过 GitHub 同步，**不用重发 APK 就能更新**：门的开放日期、解锁条件、
缓和表、段位课程——这些全在 `data/*.json` 里，改完推上去即可。

### 同步机制

启动时若本机缓存超过 12 小时，会在后台拉一次（**带 12 秒超时，绝不会卡住启动**）。
设置页也有「立即同步数据」按钮，会显示每个文件的结果。

**多源回退**（按优先级，任一成功即生效。**GitHub 优先，Gitee 兜底**）：

```
1. https://gzlxz190614.github.io/lvchecker/data/          ← GitHub Pages
2. https://api.github.com/repos/.../contents/data/...     ← Contents API
3. https://cdn.jsdelivr.net/gh/GzLxz190614/lvchecker@main/data/
4. https://raw.githubusercontent.com/GzLxz190614/lvchecker/main/data/
5. https://raw.githack.com/GzLxz190614/lvchecker/main/data/
6. https://gitee.com/gzlxz190614/lvchecker/raw/main/data/    ← Gitee 镜像（国内兜底）
```

> ⚠️ **关于「国内连不上」**：实测在部分国内网络下，`githubusercontent` 系域名整体不可达
> （`raw.githubusercontent.com` / `raw.githack.com` / `cdn.jsdelivr.net` 全部 DNS 解析失败）。
> 所以准备了三条不依赖这些域名的通路：
>
> - **GitHub Pages**（`*.github.io`，另一个域名 + 另一套 CDN）
> - **GitHub Contents API**（只用 `api.github.com`，内容走 base64 解码）
> - **Gitee 镜像**（国内域名，基本必然可达）
>
> 全部源都不通时，**热更新用不了，但 app 完全正常**——会一直用 APK 内置数据。
> 设置页有「测试各数据源的连通性」按钮，逐个显示哪个域名可用。

### Gitee 镜像（国内兜底）

仓库镜像在 <https://gitee.com/gzlxz190614/lvchecker>，内容与 GitHub 完全一致。

**为什么要有它**：不只是「换个域名试试」。GitHub 的 Contents API 有**匿名 60 次/小时/IP**
的限制（[官方文档](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)），
手机在运营商 NAT 后面时这个 IP 是很多人共用的，**4 个文件一次同步就吃掉 4 次**，
很容易「用着用着就 403」。Gitee 的 raw 是普通 GET + CDN 缓存，**没有这个配额问题**。

**推送方式**：Gitee 是**独立 remote，手动推**，没有配任何 CI 密钥。

```bash
# 一次性添加 remote
git remote add gitee git@gitee.com:gzlxz190614/lvchecker.git

# 以后每次改完数据，两个都推
git push origin main && git push gitee main
```

两个仓库的默认分支名都是 `main`，所以命令是对称的。

> ❌ **不要**用 `git remote set-url --add --push origin <gitee>` 的方式配「一次推两个」。
> 那样只要有一个失败，`git push` 就整体报错，而另一个其实**已经推成功了** ——
> 你会以为失败去重试，实际上是在做多余的事。两个独立 remote、失败一目了然。
>
> ❌ **也不要**用 `git config branch.main.merge refs/heads/main` 之类的方式去「绑定」上游。
> `branch.<name>.merge` 同时就是**上游分支**的定义，改了它会让 `git pull` 和不带参数的
> `git push` 都跑到 Gitee 去。显式写 `git push gitee main` 最不容易出错。

**漂移怎么发现**：两个仓库是独立的，很容易出现「GitHub 推了新数据、Gitee 还是旧的」。
这时 Gitee 源是**通的、只是内容旧**，光看「成功/失败」根本看不出来。所以：

- 设置页的「本地缓存」和「关于 → 数据版本」都会显示 `dataVersion`
- 「测试各数据源的连通性」会显示**每个源返回的版本号**；只要有两个不同的版本，
  就会直接标红提示「各源的数据版本不一致 → 有仓库没推最新数据」
- 同步时会比对 `dataVersion`，版本没变就算「无变化」，所以旧镜像**不会**被当成新数据写进缓存

> 如果 Gitee 上默认分支不是 `main`（比如当初建仓库时用了 `master`），要改
> `lib/data/data_sync.dart` 里 `GiteeSource('gzlxz190614/lvchecker', 'main', ...)`
> 的第二个参数。**分支名写错的表现是稳定的 404，不是偶尔失败**，所以排查时先确认这个。

### 启用 GitHub Pages（一次性，可选）

Pages 让热更新更快，但需要**手动启用一次**（`GITHUB_TOKEN` 无权创建 Pages 站点，
所以 CI 里的 `enablement: true` 也会失败，报 `Resource not accessible by integration`）：

1. 打开 `Settings` → `Pages`
2. `Source` 选 **GitHub Actions**
3. 保存

启用后，`data/` 每次变更都会由 `.github/workflows/publish-pages.yml` 自动发布。
**不启用也没关系**——Contents API 那条通路不依赖 Pages。

### 排查同步问题

设置页 → 数据同步：

- 「立即同步数据」会列出**每个文件**的结果；失败时会把**每个源各自的原因**都写出来
  （域名解析失败 / 超时 / HTTP 状态码），而不是只留最后一个。
- 「测试各数据源的连通性」逐个源探测，一眼看出是全部域名都不通，还是只有某一个。

**⚠️ 如果所有源都报「域名解析失败」（连 Gitee 也不通），先怀疑不是网络问题。**

这是本项目踩过的一个大坑：`flutter create` 生成的主 manifest 里**没有 `INTERNET` 权限**
（它只写在 debug/profile 的 manifest 里，给 Flutter 工具连 VM Service 用的），
所以 release APK 默认**完全不能联网**。表现和「被墙」几乎一样 ——
所有域名一起解析失败，但浏览器打开同一个链接却正常。

| | 缺权限 | 真被墙 |
|---|---|---|
| 失败范围 | **所有域名一起失败**（含国内域名） | 只有部分域名失败 |
| 浏览器 | **能**打开 | 不一定 |

已修复（构建期补权限 + 用 `aapt` 查成品 APK 断言），见 `tools/patch_android_manifest.py`。
**判断依据：浏览器能打开、但 app 里所有源一起失败 → 就是权限问题，不是网络。**

---

## 存档安全

**同步永远不会碰你的打勾记录。** 数据层（`data/*.json`）和存档层
（`SharedPreferences`）完全隔离，同步只覆盖前者。

---

### 三级加载

```
① 本机缓存（热更新下来的，最新）
② APK 内置（首次安装，或缓存损坏时兜底）
```

每一级都先验证能解析成 JSON，解析失败就降级到下一级——所以即使缓存文件坏了
（例如写到一半断网），app 也能正常启动。写入用「先写 .tmp 再改名」的原子方式。

### 哪些能热更新，哪些不能

| 内容 | 能否热更新 | 原因 |
|---|---|---|
| 曲目与条件、开放日期、缓和表、段位课程 | ✅ 能 | 都是 `data/*.json` |
| 曲绘 / 角色立绘 / 服装图 / 段位封面 | ❌ 不能 | 图片在 APK 内（160 张，走网络得不偿失） |
| UI 与逻辑 | ❌ 不能 | 要重新构建 APK |

所以「加了新曲目」需要重发 APK（因为要带新曲绘），
但「给某个门填上开放日期」「修正缓和表」「修正段位等级」这类改数据**不用重装**。

> 数据版本号是 `data/*.json` 里的 `dataVersion`，四个文件共用同一个值
> （由 `tools/build.py` 的 `DATA_VERSION` 统一定义，`gen_classes.py` 直接 import 它，
> 避免两个脚本写出不一样的版本号）。改数据时记得把它 +1。

---

## 开发进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| **M0** | 数据生成脚本 + `data/*.json` + 图片资源 | ✅ **完成** |
| **M1** | Flutter 工程 + ORIGIN 门 + 打勾存档 + 翻页 | ✅ **完成**（首次 APK） |
| **M2** | 其余 12 个门（items / auto / universe / manual） | ✅ **完成** |
| **M3** | 在线同步（多源回退）+ 设置页 + 连通性探测 | ✅ **完成** |
| **M4** | 落雪导入（只查门要求的歌 + 三态 + 汇总弹窗） | ✅ **完成** |
| **M5** | AIR 段位课程 UI + 36 个真实组曲 | ✅ **完成** |
| **M6** | 视觉打磨（跑马灯曲名 / 曲绘 / 段位随机槽卡片） | ✅ **完成** |

### 主要功能

- 每个门一页，**左右滑动切换**；顶部页码条可看到滑到哪、还剩几个门
- 页面自上而下：门名 + 状态 → 解锁条件（默认折叠，可展开看游戏原文）→ 待完成卡片 → **BOSS（仅解锁后显示）**
- 卡片「**点一下 = 已完成**」，半透明白遮罩 + 居中「已完成」，再点取消
- 长曲名**自动左右滚动**（跑马灯），不用点开也能看全
- AIR 门：6 个 CLASS 折叠框 → 组曲折叠框 → 组曲内 3 个槽（固定曲 / 等级随机 / 曲池随机）
- 进度**立即落盘**（`shared_preferences`），只存手机本地
- 奖励乐曲页在前 13 门全解锁后才出现

### 已知缺口

| 缺口 | 影响 | 应对 |
|---|---|---|
| 国服门开放日期未知（除 ORIGIN/AIR） | 日期判断 | 显示「未更新」，**不猜日期** |
| 国服缓和日期表未知 | 无法自动算当前 Link LEVEL | 用户手动选等级；JSON 留 `null` 等填 |
| CRYSTAL 条件未知 | 无法给准确条件 | 标「条件待确认」+ 手动确认 |
| 段位随机槽的具体曲目无法预知 | 只知道等级，不知道会抽到哪首 | 按设计只显示等级 / 「范围内随机选择」 |
| 落雪 `scores` 缺时间信息 | 不能全自动判断「更新后是否打过」 | 三态显示 + 手动确认（见上文） |
| 部分国内网络屏蔽 `githubusercontent` 系域名 | 热更新可能不可用 | 多源回退（Pages / Contents API / jsDelivr / raw / githack）+ 连通性探测 |

---

## 参考来源

- [RemyWiki — 中二节奏 2027 (China)](https://silentblue.remywiki.com/CHUNITHM:2027_(China))
- [RemyWiki — Linked VERSE](https://silentblue.remywiki.com/CHUNITHM:Linked_VERSE)
- [SEGA 官方 — Linked VERSE のゲート解放条件](https://info-chunithm.sega.jp/12052/)
- [落雪查分器 — 开发者入驻指南](https://maimai.lxns.net/docs/developer-guide)
- [落雪查分器 — 中二节奏 API 文档](https://maimai.lxns.net/docs/api/chunithm)

完整设计决策（数据模型、UI 规范、CI 配置、踩过的坑）见 [`DESIGN.md`](DESIGN.md)。
