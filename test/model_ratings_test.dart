import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/models/model_ratings.dart';

void main() {
  test('published catalogue ratings match the complete retained evidence', () {
    final report =
        jsonDecode(
              File(
                'docs/evaluation/model-ratings/paced-results-2026-10-07.json',
              ).readAsStringSync(),
            )
            as Map;
    final grades =
        jsonDecode(
              File(
                'docs/evaluation/model-ratings/grades-2026-10-07.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(report['complete'], isTrue);
    expect((report['results'] as List).length, 60);
    expect(grades['sourceStartedAt'], report['startedAt']);
    for (final (name, rating) in [
      ('apple', ModelRatings.apple),
      ('qwen', ModelRatings.qwen),
    ]) {
      final rows = (report['results'] as List)
          .cast<Map>()
          .where((r) => r['model'] == name)
          .toList();
      final marks = (grades['grades'] as List)
          .cast<Map>()
          .where((r) => r['model'] == name)
          .toList();
      expect(rows.length, rating.total);
      expect(marks.map((g) => g['id']).toSet().length, rating.total);
      expect(
        marks.map((g) => g['id']).toSet(),
        rows.map((r) => r['id']).toSet(),
      );
      expect(marks.where((g) => g['pass'] == true).length, rating.passed);
      expect(
        rows.where((r) => r['completed'] == true).length,
        rating.completed,
      );
      final times = rows.map((r) => r['elapsedMs'] as int).toList()..sort();
      expect(
        (times[14] + times[15]) / 2000,
        closeTo(rating.medianSeconds, 0.000001),
      );
      expect(grades['summary'][name]['qualityScore'], rating.quality);
      expect(grades['summary'][name]['speedScore'], rating.speed);
      expect(grades['summary'][name]['memoryScore'], isNull);
      expect(grades['summary'][name]['batteryScore'], isNull);
    }
    expect(ModelRatings.forModel('unreviewed-model'), isNull);
  });

  test('runtime failures count against quality and withhold speed', () {
    const result = ModelRatings(
      passed: 25,
      total: 30,
      completed: 29,
      medianSeconds: 1,
    );
    expect(result.quality, 3);
    expect(result.speed, isNull);
  });

  test('quality bands use full-task passes and preserve boundary values', () {
    for (final (passed, score) in [
      (0, 1),
      (59, 1),
      (60, 2),
      (74, 2),
      (75, 3),
      (84, 3),
      (85, 4),
      (94, 4),
      (95, 5),
      (100, 5),
    ]) {
      expect(ModelRatingScale.quality(passed, 100), score);
    }
    expect(ModelRatingScale.quality(25, 30), 3);
    expect(() => ModelRatingScale.quality(1, 0), throwsArgumentError);
    expect(() => ModelRatingScale.quality(31, 30), throwsArgumentError);
  });
  test('faster completion always scores higher and invalid timings fail', () {
    for (final (seconds, score) in [
      (2.0, 5),
      (2.001, 4),
      (5.0, 4),
      (5.001, 3),
      (10.0, 3),
      (10.001, 2),
      (20.0, 2),
      (20.001, 1),
    ]) {
      expect(ModelRatingScale.speed(seconds), score);
    }
    expect(() => ModelRatingScale.speed(double.nan), throwsArgumentError);
    expect(() => ModelRatingScale.speed(-1), throwsArgumentError);
  });
}
