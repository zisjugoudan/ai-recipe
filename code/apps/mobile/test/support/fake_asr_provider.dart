import 'package:ai_recipe/domain/asr/asr_models.dart';
import 'package:ai_recipe/domain/asr/asr_provider.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';

class FakeAsrProvider implements AsrProvider {
  FakeAsrProvider(this.handler, {this.kind = AsrProviderKind.localPlugin});

  final Future<AsrTranscript> Function(
    AsrMediaInput input,
    ImportCancellationToken? cancellationToken,
  )
  handler;

  @override
  final AsrProviderKind kind;

  final List<AsrMediaInput> inputs = <AsrMediaInput>[];

  @override
  Future<AsrTranscript> transcribe(
    AsrMediaInput input, {
    ImportCancellationToken? cancellationToken,
  }) {
    inputs.add(input);
    return handler(input, cancellationToken);
  }
}

AsrTranscript sampleAsrTranscript({
  String text = 'ASR recipe text',
  String providerId = 'whisper-local',
  String modelVersion = '1.0.0',
  String language = 'zh-Hans',
  double? confidence = 0.9,
  int startMs = 0,
  int endMs = 1000,
  String? speakerLabel,
}) {
  return AsrTranscript(
    providerId: providerId,
    modelVersion: modelVersion,
    language: language,
    durationMs: endMs,
    segments: text.trim().isEmpty
        ? const <AsrTranscriptSegment>[]
        : <AsrTranscriptSegment>[
            AsrTranscriptSegment(
              text: text,
              startMs: startMs,
              endMs: endMs,
              confidence: confidence,
              speakerLabel: speakerLabel,
            ),
          ],
  );
}
