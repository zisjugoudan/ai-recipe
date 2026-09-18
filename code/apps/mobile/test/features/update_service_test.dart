// UPDATE-001：Gitee version.json 在线更新服务的单元测试（MockClient 模拟）。
import 'dart:convert';

import 'package:ai_recipe/features/update/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AppUpdateService.checkForUpdate（version.json 数据源）', () {
    test('version.json 最新版本高于当前版本时提示更新', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('/raw/master/version.json'));
        return http.Response(
          jsonEncode({
            'version': 'v1.1.0',
            'note': '修复若干问题',
            'apk_url':
                'https://gitee.com/eb-Dog/delicious-food/releases/download/v1.1.0/ai_recipe.apk',
          }),
          200,
        );
      });
      const service = AppUpdateService(httpClient: client);
      final result = await service.checkForUpdate('1.0.0');
      expect(result.hasError, isFalse);
      expect(result.hasUpdate, isTrue);
      expect(result.latestRelease?.version, '1.1.0');
      expect(result.latestRelease?.body, '修复若干问题');
      expect(
        result.latestRelease?.apkDownloadUrl,
        contains('download/v1.1.0/ai_recipe.apk'),
      );
    });

    test('version.json 最新版本不高于当前版本时不提示更新', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'version': '1.0.0', 'note': '初始版本'}),
          200,
        );
      });
      const service = AppUpdateService(httpClient: client);
      final result = await service.checkForUpdate('1.0.0');
      expect(result.hasError, isFalse);
      expect(result.hasUpdate, isFalse);
      expect(result.latestRelease, isNull);
    });

    test('宽容解析：支持 latest_version / changelog / download_url 等候选键', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'latest_version': '2.0.0',
            'changelog': '全新改版',
            'download_url': 'https://example.com/app-v2.apk',
            'page_url': 'https://gitee.com/eb-Dog/delicious-food',
          }),
          200,
        );
      });
      const service = AppUpdateService(httpClient: client);
      final result = await service.checkForUpdate('1.0.0');
      expect(result.hasUpdate, isTrue);
      expect(result.latestRelease?.version, '2.0.0');
      expect(result.latestRelease?.body, '全新改版');
      expect(result.latestRelease?.apkDownloadUrl, 'https://example.com/app-v2.apk');
      expect(
        result.latestRelease?.releasePageUrl,
        'https://gitee.com/eb-Dog/delicious-food',
      );
    });

    test('404 且仓库公开存在 → 提示还没有 version.json 配置', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/raw/')) {
          return http.Response('not found', 404);
        }
        return http.Response(
          jsonEncode({'full_name': 'eb-Dog/delicious-food'}),
          200,
        );
      });
      const service = AppUpdateService(httpClient: client);
      final result = await service.checkForUpdate('1.0.0');
      expect(result.hasError, isTrue);
      expect(result.errorMessage, contains('还没有 version.json'));
    });

    test('404 且仓库不存在/私有 → 提示找不到更新仓库', () async {
      final client = MockClient((request) async {
        return http.Response('not found', 404);
      });
      const service = AppUpdateService(httpClient: client);
      final result = await service.checkForUpdate('1.0.0');
      expect(result.hasError, isTrue);
      expect(result.errorMessage, contains('找不到更新仓库'));
    });

    test('403（私有/风控）→ 提示检查更新被拒绝并建议公开或配置令牌', () async {
      final client = MockClient((request) async {
        return http.Response('forbidden', 403);
      });
      const service = AppUpdateService(httpClient: client);
      final result = await service.checkForUpdate('1.0.0');
      expect(result.hasError, isTrue);
      expect(result.errorMessage, contains('HTTP 403'));
      expect(result.errorMessage, contains('Gitee 访问令牌'));
    });

    test('master 404 但 main 200 → 分支回退解析成功', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/raw/master/version.json')) {
          return http.Response('not found', 404);
        }
        if (request.url.path.contains('/raw/main/version.json')) {
          return http.Response(jsonEncode({'version': '1.2.0'}), 200);
        }
        return http.Response('not found', 404);
      });
      const service = AppUpdateService(httpClient: client);
      final result = await service.checkForUpdate('1.0.0');
      expect(result.hasError, isFalse);
      expect(result.hasUpdate, isTrue);
      expect(result.latestRelease?.version, '1.2.0');
    });

    test('version.json 请求带浏览器 UA 头', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'version': '1.1.0'}),
          200,
        );
      });
      const service = AppUpdateService(httpClient: client);
      await service.checkForUpdate('1.0.0');
      final ua = captured?.headers['User-Agent'] ?? '';
      expect(ua, contains('Mozilla/5.0'));
    });

    test('网络异常 → 返回中文网络错误', () async {
      final client = MockClient((request) async {
        throw Exception('network down');
      });
      const service = AppUpdateService(httpClient: client);
      final result = await service.checkForUpdate('1.0.0');
      expect(result.hasError, isTrue);
      expect(result.errorMessage, contains('网络暂时不可用'));
    });

    test('无 apk 下载地址时 apkDownloadUrl 为 null（弹窗仍可显示）', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'version': 'v2.0.0', 'note': '仅说明无附件'}),
          200,
        );
      });
      const service = AppUpdateService(httpClient: client);
      final result = await service.checkForUpdate('1.0.0');
      expect(result.hasUpdate, isTrue);
      expect(result.latestRelease?.apkDownloadUrl, isNull);
    });

    test('version.json 非法 JSON → 内容无法识别', () async {
      final client = MockClient((request) async {
        return http.Response('not-json', 200);
      });
      const service = AppUpdateService(httpClient: client);
      final result = await service.checkForUpdate('1.0.0');
      expect(result.hasError, isTrue);
      expect(result.errorMessage, contains('无法识别'));
    });
  });
}
