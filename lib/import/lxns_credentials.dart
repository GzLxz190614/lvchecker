/// 落雪查分器个人 API 密钥的存取。
///
/// ⚠️ **为什么用 flutter_secure_storage 而不是 SharedPreferences**：
///
///   这个密钥能读取你**全部成绩**（个人 API 的 `/player/scores`）。
///   明文存在 SharedPreferences 里，一旦手机被 root、或某个备份/清理类应用
///   读到了 app 私有目录，密钥就泄露了。而查分器那边把它当一个长期凭据。
///
///   flutter_secure_storage 在 Android 上走 **EncryptedSharedPreferences
///   （Android Keystore 加密）**，密钥本身由硬件支持的 Keystore 保护，
///   备份/拷贝文件拿不到明文。
///
/// 另外：密钥**永不进日志、永不进仓库**。仓库里也不会有任何默认值 ——
/// 没有密钥时这个功能就是明确地「未配置」。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LxnsCredentials {
  LxnsCredentials._();

  static const _key = 'lxns_user_token';

  /// Android 上开启 Keystore 加密的共享偏好。
  ///
  /// 显式写出来而不是用默认值：默认在旧版本上可能落到普通 prefs，
  /// 那这个类就白写了。这个参数在 9.x 是 `encryptedSharedPreferences`。
  static const _android = AndroidOptions(encryptedSharedPreferences: true);

  static const _storage = FlutterSecureStorage(aOptions: _android);

  /// 是否已经存过密钥
  static Future<bool> hasToken() async {
    final t = await readToken();
    return t != null && t.isNotEmpty;
  }

  /// 读取密钥；没存过或读取失败都返回 null。
  ///
  /// 故意**不抛异常**：平台通道在某些机型/异常状态下会失败，
  /// 那时应该表现为「未配置密钥」，而不是让设置页崩掉。
  static Future<String?> readToken() async {
    try {
      final v = await _storage.read(key: _key);
      if (v == null) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// 保存密钥。返回是否成功（失败时调用方提示用户）。
  static Future<bool> saveToken(String token) async {
    final t = token.trim();
    if (t.isEmpty) return false;
    try {
      await _storage.write(key: _key, value: t);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearToken() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // 删不掉也没什么可做的；下次读到的还是旧值，用户可以覆盖保存
    }
  }

  /// 显示用的打码形式：只留前 4 位和后 4 位。
  ///
  /// 设置页要显示「已配置」时用这个，避免把完整密钥显示在屏幕上
  /// （截图、旁边有人都会泄露）。
  static String mask(String token) {
    if (token.length <= 8) return '••••••••';
    return '${token.substring(0, 4)}…${token.substring(token.length - 4)}';
  }
}
