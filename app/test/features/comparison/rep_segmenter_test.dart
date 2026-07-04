import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_session.dart';
import 'package:myemg/features/comparison/domain/services/rep_segmenter.dart';

void main() {
  const segmenter = RepSegmenter();

  test('segments repeated envelope activity into whole-rep windows', () {
    final samples = _samplesForAmplitudes([30, 30, 30]);

    final result = segmenter.segment(samples: samples, noise: 1);

    expect(result.failureReason, isNull);
    expect(result.reps, hasLength(3));
    expect(
      result.reps.every(
        (rep) =>
            rep.durationMs >= 300 &&
            rep.meanAdjustedEnv > 0 &&
            rep.p95AdjustedEnv >= rep.meanAdjustedEnv,
      ),
      isTrue,
    );
  });

  test('a count correction may expose a weaker real peak', () {
    final samples = _samplesForAmplitudes([30, 6, 30]);

    final automatic = segmenter.segment(samples: samples, noise: 1);
    final corrected = segmenter.segment(
      samples: samples,
      noise: 1,
      requestedCount: 3,
    );

    expect(automatic.reps, hasLength(2));
    expect(corrected.requestedCountMatched, isTrue);
    expect(corrected.reps, hasLength(3));
  });

  test('does not invent boundaries to satisfy an impossible count', () {
    final samples = _samplesForAmplitudes([30, 30]);

    final corrected = segmenter.segment(
      samples: samples,
      noise: 1,
      requestedCount: 5,
    );

    expect(corrected.requestedCountMatched, isFalse);
    expect(corrected.failureReason, 'requested_count_unavailable');
    expect(corrected.reps, hasLength(2));
  });

  test('reports no activity when the envelope stays near noise', () {
    final samples = List.generate(
      100,
      (index) => ComparisonEnvelopeSample(
        deviceMs: index * 20,
        env: 101,
        adjustedEnv: 1,
        seq: index,
        missingSamples: 0,
      ),
    );

    final result = segmenter.segment(samples: samples, noise: 1);

    expect(result.reps, isEmpty);
    expect(result.failureReason, 'no_activity');
  });

  test('does not count an active tail without a release boundary', () {
    final values = <double>[
      ...List<double>.filled(20, 0),
      ...List<double>.filled(30, 30),
    ];
    final samples = List.generate(
      values.length,
      (index) => ComparisonEnvelopeSample(
        deviceMs: index * 20,
        env: 100 + values[index],
        adjustedEnv: values[index],
        seq: index,
        missingSamples: 0,
      ),
    );

    final result = segmenter.segment(samples: samples, noise: 1);

    expect(result.reps, isEmpty);
  });
}

List<ComparisonEnvelopeSample> _samplesForAmplitudes(List<double> amplitudes) {
  final values = <double>[];
  for (final amplitude in amplitudes) {
    values
      ..addAll(List<double>.filled(15, 0))
      ..addAll(List<double>.filled(30, amplitude))
      ..addAll(List<double>.filled(15, 0));
  }
  values.addAll(List<double>.filled(10, 0));

  return List.generate(
    values.length,
    (index) => ComparisonEnvelopeSample(
      deviceMs: index * 20,
      env: 100 + values[index],
      adjustedEnv: values[index],
      seq: index,
      missingSamples: 0,
    ),
  );
}
