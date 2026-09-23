/// 落雪查分器的**玩家信息**（`GET /api/v0/user/chunithm/player`）。
///
/// 为什么需要它：AIR 门的解锁条件是「获得一个段位缎带」。这个信息在
/// `Player.class_emblem` 里：
///
/// ```jsonc
/// "class_emblem": { "base": 3, "medal": 3 }
/// ```
///
/// 官方文档对这两个字段的说明：
///   `base`  (int) 缎带（**通关该组别全部课题组**），默认值为 0
///   `medal` (int) 勋章（通关任意一组），默认值为 0
///
/// ## 实测（2026-09，国服 1.40）
///
/// 用户通关 CLASS Ⅲ 的全部 5 个组曲后，`class_emblem` 从 `{0, 0}` 变成 `{3, 3}`。
/// 从 `condition/class/course/*/Course.xml` 抽出的游戏内部段位编号是：
///
///     Ⅰ=10  Ⅱ=11  Ⅲ=12  Ⅳ=13  Ⅴ=14  ∞=20
///
/// 所以 `base = 3` **不是**内部 id（没有段位的 id 是 3），而是**段位序号**
/// （Ⅰ=1 … Ⅴ=5、∞=6）。
///
/// ## 我们只用「有没有缎带」，不解释具体是哪个段位
///
/// AIR 的条件是「**任一** CLASS 内所有组曲通关」= 「至少有一个缎带」。
/// 所以判据只需要回答有没有，不需要知道是哪个：
///
///     base > 0  → 有缎带 → AIR 门解锁
///
/// ## 还没确定的部分（不要假装知道）
///
/// 只有一个观测，所以区分不了 `base` 是「最近通关的段位」还是
/// 「最高段位」。**这两者对 `> 0` 的判定没有影响**，所以不影响功能；
/// 但如果以后想在界面上显示「你的缎带是哪个段位」，就需要第二个观测
/// （再通一个不同的段位，看它怎么变）。
///
/// 另外 `base` 是否为位掩码也**无法**从单个观测排除 —— 同样不影响 `> 0`。
library;

/// `Player.class_emblem`
class LxnsClassEmblem {
  const LxnsClassEmblem({required this.base, required this.medal});

  /// 缎带：通关某组别**全部**课题组。默认 0（没有）。
  final int base;

  /// 勋章：通关**任意一**组。默认 0（没有）。
  final int medal;

  /// 是否已获得缎带 —— AIR 门的判定就靠这一条。
  ///
  /// 用 `> 0` 而不是 `== 1`：文档说默认值为 0，实测拿到后是段位序号（3）。
  bool get hasRibbon => base > 0;

  /// 解析失败（字段缺失/类型不对）时返回 null，**不要**猜一个 0 出来：
  /// 0 的含义是「确认没有缎带」，而「读不到」是另一回事，
  /// 混为一谈会让 AIR 门在接口变动时静默变成「未解锁」。
  static LxnsClassEmblem? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final b = (raw['base'] as num?)?.toInt();
    final m = (raw['medal'] as num?)?.toInt();
    if (b == null && m == null) return null;
    return LxnsClassEmblem(base: b ?? 0, medal: m ?? 0);
  }

  @override
  String toString() => 'class_emblem{base: $base, medal: $medal}';
}

/// `Player` 里我们关心的部分。
///
/// 刻意**不解析**身份字段（好友码 / 昵称 / QQ）—— 这个对象会存进
/// SharedPreferences，没必要把身份信息也存一份。
class LxnsPlayer {
  const LxnsPlayer({this.classEmblem, this.character});

  final LxnsClassEmblem? classEmblem;

  /// 当前设置的角色（`{id, name, level}`）。`level` 就是角色 RANK。
  /// 只包含**当前装备**的那个角色，不是全部角色。
  final LxnsCharacter? character;

  static LxnsPlayer fromJson(Map<String, dynamic> json) => LxnsPlayer(
        classEmblem: LxnsClassEmblem.fromJson(json['class_emblem']),
        character: LxnsCharacter.fromJson(json['character']),
      );
}

/// `Player.character` —— 当前角色。`level` 是角色 RANK。
class LxnsCharacter {
  const LxnsCharacter({required this.id, this.name, this.level});

  final int id;
  final String? name;
  final int? level;

  static LxnsCharacter? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] as num?)?.toInt();
    if (id == null) return null;
    return LxnsCharacter(
      id: id,
      name: raw['name'] as String?,
      level: (raw['level'] as num?)?.toInt(),
    );
  }

  @override
  String toString() => 'character{id: $id, level: $level}';
}
