import 'package:ai_recipe/domain/llm/llm_provider_exception.dart';
import 'package:ai_recipe/providers/llm/vision_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('标准诊断图（BUG-006）', () {
    test('文字与红色方块同时正确时通过', () {
      final assertion = assertVisionProbe(
        '{"text":"AI RECIPE 314","redSquare":true}',
      );
      expect(assertion.passed, isTrue);
      expect(assertion.failureKind, isNull);
    });

    test('允许大小写与常见 OCR 分隔差异', () {
      expect(
        assertVisionProbe('{"text":"ai recipe 314","redSquare":true}').passed,
        isTrue,
      );
      expect(
        assertVisionProbe('{"text":"AIRECIPE314","redSquare":true}').passed,
        isTrue,
      );
      expect(
        assertVisionProbe('{"text":"AI RECIPE 31 4","redSquare":true}').passed,
        isTrue,
      );
    });

    test('只识别文字但未识别红色方块时失败', () {
      final assertion = assertVisionProbe(
        '{"text":"AI RECIPE 314","redSquare":false}',
      );
      expect(assertion.passed, isFalse);
      expect(assertion.failureKind, LlmProviderErrorKind.imageNotObserved);
      expect(assertion.detail, contains('红色方块'));
    });

    test('只识别红色方块但文字错误时失败', () {
      final assertion = assertVisionProbe(
        '{"text":"OK","redSquare":true}',
      );
      expect(assertion.passed, isFalse);
      expect(assertion.failureKind, LlmProviderErrorKind.imageNotObserved);
      expect(assertion.detail, contains('文字'));
    });

    test('空文本 / 通用描述不能通过', () {
      expect(assertVisionProbe('{"text":"","redSquare":true}').passed, isFalse);
      expect(
        assertVisionProbe('{"text":"一张测试图片","redSquare":true}').passed,
        isFalse,
      );
    });

    test('只回复 OK 判定为响应协议失败', () {
      final assertion = assertVisionProbe('OK');
      expect(assertion.passed, isFalse);
      expect(assertion.failureKind, LlmProviderErrorKind.invalidResponse);
    });

    test('非 JSON 对象判定为响应协议失败', () {
      final assertion = assertVisionProbe('[1,2,3]');
      expect(assertion.passed, isFalse);
      expect(assertion.failureKind, LlmProviderErrorKind.invalidResponse);
    });

    test('标准图字节可解码且为 256×256 PNG', () {
      expect(visionProbeBytes, isNotEmpty);
      // PNG 魔数。
      expect(visionProbeBytes.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
      expect(visionProbeWidth, 256);
      expect(visionProbeHeight, 256);
    });
  });
}
