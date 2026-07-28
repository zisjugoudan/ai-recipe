import 'package:ai_recipe/application/backend/import_execution_plan.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default execution plan uses public import and custom LLM', () {
    expect(const ImportExecutionPlan().requiredCapabilities, <AppCapability>{
      AppCapability.publicContentImport,
      AppCapability.customLlm,
    });
  });

  test('managed LLM maps to managed capability', () {
    expect(
      const ImportExecutionPlan(
        llm: ImportLlmRoute.managed,
      ).requiredCapabilities,
      containsAll(<AppCapability>[
        AppCapability.publicContentImport,
        AppCapability.managedLlm,
      ]),
    );
  });

  test('local and cloud OCR map to their own capabilities', () {
    expect(
      const ImportExecutionPlan(ocr: ImportOcrRoute.local).requiredCapabilities,
      contains(AppCapability.localOcr),
    );
    expect(
      const ImportExecutionPlan(ocr: ImportOcrRoute.cloud).requiredCapabilities,
      contains(AppCapability.cloudOcr),
    );
  });

  test('managed ASR maps to managed ASR capability', () {
    expect(
      const ImportExecutionPlan(
        asr: ImportAsrRoute.managed,
      ).requiredCapabilities,
      contains(AppCapability.managedAsr),
    );
  });
}
