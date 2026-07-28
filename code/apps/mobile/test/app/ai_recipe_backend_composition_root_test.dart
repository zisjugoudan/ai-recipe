import 'dart:io';

import 'package:ai_recipe/app/ai_recipe_backend_composition_root.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_manifest.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_package.dart';
import 'package:ai_recipe/domain/ocr/ocr_models.dart';
import 'package:ai_recipe/providers/ocr/platform_ocr_runtime_bridge.dart';
import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_recipe_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_app_access_dependencies.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'composition root owns an injected database and preserves data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ai-recipe-backend-root-',
      );
      final databasePath = path.join(directory.path, 'backend.db');
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      final root = AiRecipeBackendCompositionRoot.device(
        database: database,
        sessionRepository: FakeAppSessionRepository(),
        llmConfigRepository: MemoryLlmConfigRepository(),
        capabilityRuntimeRepository: FakeAppCapabilityRuntimeRepository(
          runtime: AppCapabilityRuntime(),
        ),
        idGenerator: () => 'persistent-recipe',
        clock: () => DateTime.utc(2026, 7, 28, 23),
      );

      AppDatabase? reopened;
      try {
        final created = await root.backend.recipes.createRecipe(
          RecipeDraftInput(title: '持久化菜谱'),
        );
        expect(created.id, 'persistent-recipe');

        await root.close();
        await root.close();

        reopened = AppDatabase(
          factory: databaseFactoryFfi,
          databasePath: databasePath,
        );
        final saved = await SqliteRecipeRepository(
          reopened,
        ).getRecipeById(created.id);
        expect(saved, isNotNull);
        expect(saved!.title, '持久化菜谱');
      } finally {
        await root.close();
        await reopened?.close();
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );

  test(
    'local OCR capability is not installed without an active model',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ai-recipe-ocr-capability-',
      );
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: path.join(directory.path, 'backend.db'),
      );
      final root = AiRecipeBackendCompositionRoot.device(
        database: database,
        sessionRepository: FakeAppSessionRepository(),
        llmConfigRepository: MemoryLlmConfigRepository(),
        localOcrModelPackageService: FakeOcrModelPackageService(),
        localOcrRuntimeBridge: FakeOcrRuntimeBridge(
          probeResult: const OcrRuntimeProbe(
            runtimeAvailable: true,
            recognitionSupported: false,
          ),
        ),
      );

      try {
        final snapshot = await root.backend.loadCapabilities();
        final decision = snapshot.decisionFor(AppCapability.localOcr);

        expect(decision.isAvailable, isFalse);
        expect(decision.reason, AppCapabilityReason.componentNotInstalled);
      } finally {
        await root.close();
        if (directory.existsSync()) await directory.delete(recursive: true);
      }
    },
  );

  test(
    'local OCR capability stays unavailable until recognition is ready',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ai-recipe-ocr-capability-',
      );
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: path.join(directory.path, 'backend.db'),
      );
      final activeDirectory = Directory(path.join(directory.path, 'model'))
        ..createSync(recursive: true);
      final activePackage = OcrInstalledModelPackage(
        manifest: sampleOcrModelManifest(),
        rootDirectory: activeDirectory,
      );
      final bridge = FakeOcrRuntimeBridge(
        probeResult: const OcrRuntimeProbe(
          runtimeAvailable: true,
          recognitionSupported: false,
          runtimeVersion: 'onnxruntime-android',
        ),
      );
      final root = AiRecipeBackendCompositionRoot.device(
        database: database,
        sessionRepository: FakeAppSessionRepository(),
        llmConfigRepository: MemoryLlmConfigRepository(),
        localOcrModelPackageService: FakeOcrModelPackageService(
          activePackage: activePackage,
        ),
        localOcrRuntimeBridge: bridge,
      );

      try {
        final snapshot = await root.backend.loadCapabilities();
        final decision = snapshot.decisionFor(AppCapability.localOcr);

        expect(bridge.probeCount, 1);
        expect(decision.isAvailable, isFalse);
        expect(decision.reason, AppCapabilityReason.serviceUnavailable);
      } finally {
        await root.close();
        if (directory.existsSync()) await directory.delete(recursive: true);
      }
    },
  );
}

class MemoryLlmConfigRepository implements LlmConfigRepository {
  @override
  Future<void> clearApiKey(String secretRef) async {}

  @override
  Future<LlmConnectionConfig?> load() async => null;

  @override
  Future<String> readApiKey(String secretRef) async => '';

  @override
  Future<void> save(LlmConnectionConfig config, {String? apiKey}) async {}
}

OcrModelManifest sampleOcrModelManifest() {
  return OcrModelManifest(
    schemaVersion: 1,
    packageId: 'paddleocr-ppocrv5-mobile-zh',
    version: '1.0.0',
    engine: 'onnxruntime',
    platforms: const <OcrRuntimePlatform>{OcrRuntimePlatform.android},
    languages: const <String>['zh-Hans', 'en'],
    minAppVersion: '0.1.0',
    license: 'Apache-2.0',
    files: <OcrModelFile>[
      OcrModelFile(
        role: 'detector',
        path: 'det.onnx',
        downloadUrl: 'https://models.example.invalid/ocr/det.onnx',
        sha256: '0' * 64,
        sizeBytes: 1,
      ),
    ],
  );
}

class FakeOcrModelPackageService implements OcrModelPackageService {
  FakeOcrModelPackageService({this.activePackage});

  OcrInstalledModelPackage? activePackage;

  @override
  Future<OcrModelPackageStatus> getStatus(String packageId) async {
    final active = activePackage;
    return OcrModelPackageStatus(
      packageId: packageId,
      state: active == null
          ? OcrModelInstallState.notInstalled
          : OcrModelInstallState.installed,
      progress: active == null ? 0 : 1,
      installedVersion: active?.version,
    );
  }

  @override
  Future<OcrInstalledModelPackage?> getActivePackage(String packageId) async {
    return activePackage;
  }

  @override
  Future<OcrModelPackageStatus> install(
    OcrModelManifest manifest, {
    void Function(OcrModelPackageStatus status)? onStatusChanged,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String packageId) async {}

  @override
  Future<void> recoverInterruptedInstallations() async {}
}

class FakeOcrRuntimeBridge implements OcrRuntimeBridge {
  FakeOcrRuntimeBridge({required this.probeResult});

  final OcrRuntimeProbe probeResult;
  var probeCount = 0;

  @override
  Future<OcrRuntimeProbe> probe() async {
    probeCount += 1;
    return probeResult;
  }

  @override
  Future<void> healthCheck(OcrInstalledModelPackage package) async {}

  @override
  Future<OcrDocument> recognize({
    required OcrImageInput input,
    required OcrInstalledModelPackage package,
  }) {
    throw UnimplementedError();
  }
}
