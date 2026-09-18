// UPDATE-001：在线更新版本比较器与 Release 解析的单元测试。
import 'package:ai_recipe/domain/update/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareAppVersions 版本比较', () {
    test('相同版本返回 0', () {
      expect(compareAppVersions('1.0.0', '1.0.0'), 0);
    });

    test('major 升级判定为新版', () {
      expect(compareAppVersions('2.0.0', '1.0.0') > 0, isTrue);
    });

    test('minor 升级判定为新版', () {
      expect(compareAppVersions('1.1.0', '1.0.0') > 0, isTrue);
    });

    test('patch 升级判定为新版', () {
      expect(compareAppVersions('1.0.1', '1.0.0') > 0, isTrue);
    });

    test('低版本小于高版本', () {
      expect(compareAppVersions('1.0.0', '1.0.1') < 0, isTrue);
    });

    test('v 前缀不影响比较', () {
      expect(compareAppVersions('v1.1.0', '1.0.0') > 0, isTrue);
      expect(compareAppVersions('v1.0.0', '1.0.0'), 0);
    });

    test('缺省段按 0 补全', () {
      expect(compareAppVersions('1.1', '1.1.0'), 0);
      expect(compareAppVersions('2', '1.9.9') > 0, isTrue);
    });
  });

  group('AppUpdateCheckResult', () {
    test('无新版本时 hasUpdate 为 false', () {
      const result = AppUpdateCheckResult(currentVersion: '1.0.0');
      expect(result.hasUpdate, isFalse);
      expect(result.hasError, isFalse);
    });

    test('有 release 时 hasUpdate 为 true', () {
      const release = AppReleaseInfo(
        tagName: 'v1.1.0',
        version: '1.1.0',
        body: '修复若干问题',
        apkDownloadUrl: 'https://example.com/app.apk',
        releasePageUrl: 'https://example.com/releases/1',
      );
      const result = AppUpdateCheckResult(
        currentVersion: '1.0.0',
        latestRelease: release,
      );
      expect(result.hasUpdate, isTrue);
      expect(result.latestRelease?.version, '1.1.0');
    });

    test('错误结果 hasError 为 true', () {
      const result = AppUpdateCheckResult(
        currentVersion: '1.0.0',
        errorMessage: '网络不可用',
      );
      expect(result.hasError, isTrue);
    });
  });
}
