import 'import_cancellation_token.dart';
import 'import_content.dart';
import 'import_task.dart';

enum ImportContentAdapterErrorKind {
  unsupportedPlatform,
  contentUnavailable,
  authorizationRequired,
  networkUnavailable,
  timeout,
  invalidPayload,
  cancelled,
  unknown,
}

class ImportContentAdapterException implements Exception {
  const ImportContentAdapterException({
    required this.kind,
    required this.message,
    required this.retryable,
  });

  final ImportContentAdapterErrorKind kind;
  final String message;
  final bool retryable;

  @override
  String toString() => 'ImportContentAdapterException(${kind.name}): $message';
}

class ImportContentAdapterRegistrationException implements Exception {
  const ImportContentAdapterRegistrationException(this.message);

  final String message;

  @override
  String toString() => 'ImportContentAdapterRegistrationException: $message';
}

abstract interface class ImportContentAdapter {
  ImportSourcePlatform get platform;

  Future<ImportContent> fetch(
    ImportSourceLink source, {
    ImportCancellationToken? cancellationToken,
  });
}

class ImportContentAdapterRegistry {
  ImportContentAdapterRegistry(Iterable<ImportContentAdapter> adapters)
    : _adapters = _buildRegistry(adapters);

  final Map<ImportSourcePlatform, ImportContentAdapter> _adapters;

  Set<ImportSourcePlatform> get supportedPlatforms =>
      Set<ImportSourcePlatform>.unmodifiable(_adapters.keys);

  ImportContentAdapter adapterFor(ImportSourcePlatform platform) {
    final adapter = _adapters[platform];
    if (adapter == null) {
      throw ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.unsupportedPlatform,
        message: 'No content adapter is registered for ${platform.name}.',
        retryable: false,
      );
    }
    return adapter;
  }

  static Map<ImportSourcePlatform, ImportContentAdapter> _buildRegistry(
    Iterable<ImportContentAdapter> adapters,
  ) {
    final registry = <ImportSourcePlatform, ImportContentAdapter>{};
    for (final adapter in adapters) {
      if (registry.containsKey(adapter.platform)) {
        throw ImportContentAdapterRegistrationException(
          'Duplicate adapter registration for ${adapter.platform.name}.',
        );
      }
      registry[adapter.platform] = adapter;
    }
    return Map<ImportSourcePlatform, ImportContentAdapter>.unmodifiable(
      registry,
    );
  }
}
