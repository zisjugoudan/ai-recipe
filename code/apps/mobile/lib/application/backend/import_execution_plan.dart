import '../../domain/access/app_capability.dart';

enum ImportLlmRoute { custom, managed }

enum ImportOcrRoute { disabled, local, cloud }

enum ImportAsrRoute { disabled, managed }

class ImportExecutionPlan {
  const ImportExecutionPlan({
    this.llm = ImportLlmRoute.custom,
    this.ocr = ImportOcrRoute.disabled,
    this.asr = ImportAsrRoute.disabled,
  });

  final ImportLlmRoute llm;
  final ImportOcrRoute ocr;
  final ImportAsrRoute asr;

  Set<AppCapability> get requiredCapabilities => <AppCapability>{
    AppCapability.publicContentImport,
    switch (llm) {
      ImportLlmRoute.custom => AppCapability.customLlm,
      ImportLlmRoute.managed => AppCapability.managedLlm,
    },
    if (ocr == ImportOcrRoute.local) AppCapability.localOcr,
    if (ocr == ImportOcrRoute.cloud) AppCapability.cloudOcr,
    if (asr == ImportAsrRoute.managed) AppCapability.managedAsr,
  };
}
