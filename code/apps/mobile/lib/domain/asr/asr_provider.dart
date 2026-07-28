import '../importing/import_cancellation_token.dart';
import 'asr_models.dart';

abstract interface class AsrProvider {
  AsrProviderKind get kind;

  Future<AsrTranscript> transcribe(
    AsrMediaInput input, {
    ImportCancellationToken? cancellationToken,
  });
}
