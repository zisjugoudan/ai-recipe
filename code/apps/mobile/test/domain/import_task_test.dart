import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 7, 28, 8);

  ImportTask queued({int maxAttempts = 3}) {
    return ImportTask.queued(
      id: 'task-1',
      source: ImportSourceLink.parse(
        'HTTPS://WWW.XIAOHONGSHU.COM/explore/abc?source=share#comments',
      ),
      now: createdAt,
      maxAttempts: maxAttempts,
    );
  }

  test('parses and normalizes supported Xiaohongshu and Douyin links', () {
    final xhs = ImportSourceLink.parse(
      ' HTTPS://WWW.XIAOHONGSHU.COM/explore/abc#comments ',
    );
    final douyin = ImportSourceLink.parse('https://v.douyin.com/abc123/');

    expect(xhs.platform, ImportSourcePlatform.xiaohongshu);
    expect(xhs.normalizedUrl, 'https://www.xiaohongshu.com/explore/abc');
    expect(douyin.platform, ImportSourcePlatform.douyin);
    expect(douyin.normalizedUrl, 'https://v.douyin.com/abc123/');
  });

  test('rejects malformed URLs and unsupported platforms', () {
    expect(
      () => ImportSourceLink.parse('not-a-url'),
      throwsA(
        isA<ImportTaskInputException>().having(
          (error) => error.code,
          'code',
          ImportTaskErrorCode.invalidUrl,
        ),
      ),
    );
    expect(
      () => ImportSourceLink.parse('https://example.com/recipe'),
      throwsA(
        isA<ImportTaskInputException>().having(
          (error) => error.code,
          'code',
          ImportTaskErrorCode.unsupportedPlatform,
        ),
      ),
    );
  });

  test('runs through generation, review, and completion', () {
    final started = queued().start(createdAt.add(const Duration(minutes: 1)));
    final extracting = started.advance(
      nextStage: ImportTaskStage.extracting,
      nextProgress: 0.25,
      now: createdAt.add(const Duration(minutes: 2)),
    );
    final generating = extracting.advance(
      nextStage: ImportTaskStage.generating,
      nextProgress: 0.8,
      now: createdAt.add(const Duration(minutes: 3)),
    );
    final review = generating.markNeedsReview(
      recipeId: 'recipe-draft-1',
      now: createdAt.add(const Duration(minutes: 4)),
    );
    final completed = review.complete(
      createdAt.add(const Duration(minutes: 5)),
    );

    expect(started.status, ImportTaskStatus.running);
    expect(started.stage, ImportTaskStage.fetching);
    expect(review.status, ImportTaskStatus.needsReview);
    expect(review.resultRecipeId, 'recipe-draft-1');
    expect(completed.status, ImportTaskStatus.completed);
    expect(completed.completedAt, createdAt.add(const Duration(minutes: 5)));
    expect(completed.localVersion, 6);
  });

  test('prevents stage and progress regression', () {
    final running = queued()
        .start(createdAt.add(const Duration(minutes: 1)))
        .advance(
          nextStage: ImportTaskStage.transcribing,
          nextProgress: 0.6,
          now: createdAt.add(const Duration(minutes: 2)),
        );

    expect(
      () => running.advance(
        nextStage: ImportTaskStage.ocr,
        nextProgress: 0.7,
        now: createdAt.add(const Duration(minutes: 3)),
      ),
      throwsA(isA<ImportTaskTransitionException>()),
    );
    expect(
      () => running.advance(
        nextStage: ImportTaskStage.generating,
        nextProgress: 0.5,
        now: createdAt.add(const Duration(minutes: 3)),
      ),
      throwsA(isA<ImportTaskTransitionException>()),
    );
  });

  test('retries only retryable failures while attempts remain', () {
    final failureTime = createdAt.add(const Duration(minutes: 2));
    final failed = queued()
        .start(createdAt.add(const Duration(minutes: 1)))
        .fail(
          code: ImportTaskErrorCode.networkUnavailable,
          message: 'offline',
          canRetry: true,
          nextRetryAt: failureTime.add(const Duration(minutes: 5)),
          now: failureTime,
        );

    expect(failed.canRetry, isTrue);
    expect(
      () => failed.retry(failureTime.add(const Duration(minutes: 4))),
      throwsA(isA<ImportTaskTransitionException>()),
    );

    final retried = failed.retry(failureTime.add(const Duration(minutes: 5)));
    expect(retried.status, ImportTaskStatus.queued);
    expect(retried.attempt, 2);
    expect(retried.errorCode, isNull);
    expect(retried.nextRetryAt, isNull);

    final finalFailure = ImportTask.queued(
      id: 'task-final',
      source: ImportSourceLink.parse('https://v.douyin.com/final/'),
      now: createdAt,
      maxAttempts: 1,
    ).fail(code: ImportTaskErrorCode.timeout, canRetry: true, now: failureTime);
    expect(finalFailure.retryable, isFalse);
    expect(finalFailure.canRetry, isFalse);
  });

  test(
    'cancellation is idempotent and completed tasks cannot be cancelled',
    () {
      final cancelled = queued().cancel(
        createdAt.add(const Duration(minutes: 1)),
      );
      final cancelledAgain = cancelled.cancel(
        createdAt.add(const Duration(minutes: 2)),
      );

      expect(identical(cancelled, cancelledAgain), isTrue);
      expect(cancelledAgain.localVersion, 2);

      final review = queued()
          .start(createdAt.add(const Duration(minutes: 1)))
          .advance(
            nextStage: ImportTaskStage.generating,
            nextProgress: 0.9,
            now: createdAt.add(const Duration(minutes: 2)),
          )
          .markNeedsReview(
            recipeId: 'recipe-review',
            now: createdAt.add(const Duration(minutes: 3)),
          );
      final cancelledReview = review.cancel(
        createdAt.add(const Duration(minutes: 4)),
      );
      expect(cancelledReview.status, ImportTaskStatus.cancelled);
      expect(cancelledReview.resultRecipeId, isNull);

      final completed = queued()
          .start(createdAt.add(const Duration(minutes: 1)))
          .advance(
            nextStage: ImportTaskStage.generating,
            nextProgress: 0.9,
            now: createdAt.add(const Duration(minutes: 2)),
          )
          .markNeedsReview(
            recipeId: 'recipe-1',
            now: createdAt.add(const Duration(minutes: 3)),
          )
          .complete(createdAt.add(const Duration(minutes: 4)));
      expect(
        () => completed.cancel(createdAt.add(const Duration(minutes: 5))),
        throwsA(isA<ImportTaskTransitionException>()),
      );
    },
  );

  test('restart recovery requeues running work or fails exhausted work', () {
    final running = queued().start(createdAt.add(const Duration(minutes: 1)));
    final recovered = running.recoverAfterRestart(
      createdAt.add(const Duration(minutes: 2)),
    );

    expect(recovered.status, ImportTaskStatus.queued);
    expect(recovered.attempt, 2);
    expect(recovered.startedAt, isNull);

    final exhausted = queued(maxAttempts: 1)
        .start(createdAt.add(const Duration(minutes: 1)))
        .recoverAfterRestart(createdAt.add(const Duration(minutes: 2)));
    expect(exhausted.status, ImportTaskStatus.failed);
    expect(exhausted.errorCode, ImportTaskErrorCode.interrupted);
    expect(exhausted.retryable, isFalse);
  });
}
