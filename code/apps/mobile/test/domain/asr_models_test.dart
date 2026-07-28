import 'package:ai_recipe/domain/asr/asr_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AsrMediaInput', () {
    test('accepts HTTPS and local media inputs', () {
      final remote = AsrMediaInput(
        kind: AsrMediaKind.video,
        remoteUrl: ' https://example.com/video.mp4 ',
        mimeType: ' video/mp4 ',
        durationMs: 1200,
        languageHint: ' zh-Hans ',
        order: 2,
      );
      final local = AsrMediaInput(
        kind: AsrMediaKind.audio,
        localAssetId: ' audio-1 ',
        mimeType: 'audio/mpeg',
        order: 0,
      );

      expect(remote.remoteUrl, 'https://example.com/video.mp4');
      expect(remote.mimeType, 'video/mp4');
      expect(remote.languageHint, 'zh-Hans');
      expect(local.localAssetId, 'audio-1');
    });

    test('rejects insecure, missing and mismatched media inputs', () {
      expect(
        () => AsrMediaInput(
          kind: AsrMediaKind.video,
          remoteUrl: 'http://example.com/video.mp4',
          order: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => AsrMediaInput(kind: AsrMediaKind.audio, order: 0),
        throwsArgumentError,
      );
      expect(
        () => AsrMediaInput(
          kind: AsrMediaKind.video,
          localAssetId: 'asset',
          mimeType: 'audio/mpeg',
          order: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid duration and order', () {
      expect(
        () => AsrMediaInput(
          kind: AsrMediaKind.audio,
          localAssetId: 'asset',
          durationMs: 0,
          order: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => AsrMediaInput(
          kind: AsrMediaKind.audio,
          localAssetId: 'asset',
          order: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ASR output models', () {
    test('validates segment times and confidence', () {
      expect(
        () => AsrTranscriptSegment(text: 'bad', startMs: -1, endMs: 10),
        throwsArgumentError,
      );
      expect(
        () => AsrTranscriptSegment(text: 'bad', startMs: 10, endMs: 10),
        throwsArgumentError,
      );
      expect(
        () => AsrTranscriptSegment(
          text: 'bad',
          startMs: 0,
          endMs: 10,
          confidence: 1.1,
        ),
        throwsArgumentError,
      );
    });

    test('orders segments and calculates text and confidence', () {
      final transcript = AsrTranscript(
        providerId: ' provider ',
        modelVersion: ' model ',
        language: ' zh-Hans ',
        durationMs: 3000,
        segments: <AsrTranscriptSegment>[
          AsrTranscriptSegment(text: 'second', startMs: 1000, endMs: 2000),
          AsrTranscriptSegment(
            text: 'first',
            startMs: 0,
            endMs: 900,
            confidence: 0.8,
            speakerLabel: ' cook ',
          ),
          AsrTranscriptSegment(
            text: 'third',
            startMs: 2000,
            endMs: 3000,
            confidence: 1,
          ),
        ],
      );

      expect(transcript.providerId, 'provider');
      expect(transcript.fullText, 'first\nsecond\nthird');
      expect(transcript.segments.first.speakerLabel, 'cook');
      expect(transcript.averageConfidence, closeTo(0.9, 0.000001));
    });

    test('rejects segments beyond known media duration', () {
      expect(
        () => AsrTranscript(
          providerId: 'provider',
          modelVersion: 'model',
          language: 'und',
          durationMs: 100,
          segments: <AsrTranscriptSegment>[
            AsrTranscriptSegment(text: 'late', startMs: 50, endMs: 101),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('empty or confidence-free transcripts have no average', () {
      final transcript = AsrTranscript(
        providerId: 'provider',
        modelVersion: 'model',
        language: 'und',
        segments: <AsrTranscriptSegment>[
          AsrTranscriptSegment(text: 'text', startMs: 0, endMs: 10),
        ],
      );

      expect(transcript.averageConfidence, isNull);
    });
  });
}
