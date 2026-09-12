// 密钥打码的测试。
//
// 只测 `mask` —— 它是纯函数。读写/删除要走平台通道（Android Keystore），
// 在单元测试里没有真实实现，硬测只会变成测桩，意义不大；
// 那部分靠实际安装后手点验证。
//
// 为什么打码值得钉测试：设置页会把它显示在屏幕上，而密钥能读你全部成绩。
// 打码写错（比如短密钥被整段显示）就是直接在屏幕上泄露。

import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/import/lxns_credentials.dart';

void main() {
  group('LxnsCredentials.mask', () {
    test('正常长度的密钥只露首尾各 4 位', () {
      const token = 'KVV1nwdHG5LWl6Gm5TNqhFukwjVCz4YxzBqgYiUkCM';
      final m = LxnsCredentials.mask(token);
      expect(m, startsWith('KVV1'));
      expect(m, endsWith('kCM'));
      expect(m.contains('…'), isTrue);
    });

    test('中间部分一定不会被显示出来', () {
      // 取中段一个必然属于「中间」的片段，确认它没出现在打码结果里
      const token = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final m = LxnsCredentials.mask(token);
      expect(m.contains('KLMNOP'), isFalse, reason: '中段不能泄露');
      expect(m.contains('QRSTUV'), isFalse, reason: '中段不能泄露');
    });

    test('短密钥整段打码，不露任何字符', () {
      // 边界：<= 8 位时如果按「首尾各 4 位」切，中间就没有了，
      // 等于把整个密钥都显示出来 —— 所以这种情况必须整段打码。
      for (final short in ['abc', 'abcdefgh', '12345678']) {
        final m = LxnsCredentials.mask(short);
        expect(m, '••••••••', reason: '长度 ${short.length} 的密钥必须整段打码');
        for (final ch in short.split('')) {
          expect(m.contains(ch), isFalse, reason: '不能露出任何原字符');
        }
      }
    });

    test('9 位（刚好超过阈值）可以露首尾', () {
      final m = LxnsCredentials.mask('123456789');
      expect(m, '1234…6789');
    });

    test('空串不会崩', () {
      expect(LxnsCredentials.mask(''), '••••••••');
    });
  });
}
