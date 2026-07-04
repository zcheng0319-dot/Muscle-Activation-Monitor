import 'dart:math' as math;

import 'package:myemg/features/comparison/domain/entities/comparison_session.dart';

class RepSegmentationResult {
  const RepSegmentationResult({
    required this.reps,
    required this.requestedCountMatched,
    this.confidenceSufficient = false,
    this.failureReason,
  });

  final List<RepEmgResult> reps;
  final bool requestedCountMatched;
  final bool confidenceSufficient;
  final String? failureReason;
}

class RepSegmenter {
  const RepSegmenter({
    this.minimumRepDurationMs = 300,
    this.maximumRepDurationMs = 15000,
    this.minimumReleaseDurationMs = 120,
    this.mergeGapMs = 200,
    this.smoothingRadius = 2,
  });

  final int minimumRepDurationMs;
  final int maximumRepDurationMs;
  final int minimumReleaseDurationMs;
  final int mergeGapMs;
  final int smoothingRadius;

  RepSegmentationResult segment({
    required List<ComparisonEnvelopeSample> samples,
    required double noise,
    int? requestedCount,
  }) {
    if (samples.length < 3 || !noise.isFinite || noise < 0) {
      return const RepSegmentationResult(
        reps: [],
        requestedCountMatched: false,
        failureReason: 'insufficient_samples',
      );
    }
    if (requestedCount != null && requestedCount <= 0) {
      return const RepSegmentationResult(
        reps: [],
        requestedCountMatched: false,
        failureReason: 'invalid_requested_count',
      );
    }

    final smoothed = _movingAverage(
      samples.map((sample) => sample.adjustedEnv).toList(),
    );
    final sorted = [...smoothed]..sort();
    final floor = _percentile(sorted, 0.20);
    final upper = _percentile(sorted, 0.90);
    final range = upper - floor;
    if (range <= math.max(noise * 2, 0.000001)) {
      return const RepSegmentationResult(
        reps: [],
        requestedCountMatched: false,
        failureReason: 'no_activity',
      );
    }

    const thresholdPairs = <(double, double)>[
      (0.30, 0.15),
      (0.38, 0.20),
      (0.48, 0.25),
      (0.60, 0.30),
      (0.25, 0.12),
      (0.20, 0.08),
      (0.15, 0.05),
    ];

    final attempts = <List<RepEmgResult>>[];
    for (final pair in thresholdPairs) {
      final highThreshold = math.max(noise * 3, floor + range * pair.$1);
      final lowThreshold = math.max(noise * 1.5, floor + range * pair.$2);
      final reps = _segmentAtThreshold(
        samples: samples,
        smoothed: smoothed,
        highThreshold: highThreshold,
        lowThreshold: lowThreshold,
      );
      attempts.add(reps);
    }

    final baseReps = attempts.first;
    if (requestedCount == null) {
      final matchingAttempts = attempts
          .where((reps) => reps.length == baseReps.length)
          .length;
      return RepSegmentationResult(
        reps: baseReps,
        requestedCountMatched: baseReps.isNotEmpty,
        confidenceSufficient: baseReps.isNotEmpty && matchingAttempts >= 2,
        failureReason: baseReps.isEmpty ? 'no_valid_reps' : null,
      );
    }

    final matchingAttempts = attempts
        .where((reps) => reps.length == requestedCount)
        .toList();
    if (matchingAttempts.isNotEmpty) {
      return RepSegmentationResult(
        reps: matchingAttempts.first,
        requestedCountMatched: true,
        confidenceSufficient: matchingAttempts.length >= 2,
      );
    }

    return RepSegmentationResult(
      reps: baseReps,
      requestedCountMatched: false,
      failureReason: 'requested_count_unavailable',
    );
  }

  List<RepEmgResult> _segmentAtThreshold({
    required List<ComparisonEnvelopeSample> samples,
    required List<double> smoothed,
    required double highThreshold,
    required double lowThreshold,
  }) {
    final indexRanges = <(int, int)>[];
    int? activeStart;
    int? releaseStart;

    for (var index = 0; index < smoothed.length; index++) {
      final value = smoothed[index];
      if (activeStart == null) {
        if (value >= highThreshold) {
          activeStart = index;
          releaseStart = null;
        }
        continue;
      }

      if (value > lowThreshold) {
        releaseStart = null;
        continue;
      }

      releaseStart ??= index;
      final releaseDuration =
          samples[index].deviceMs - samples[releaseStart].deviceMs;
      if (releaseDuration < minimumReleaseDurationMs) continue;

      indexRanges.add((activeStart, releaseStart));
      activeStart = null;
      releaseStart = null;
    }

    final mergedRanges = <(int, int)>[];
    for (final range in indexRanges) {
      if (mergedRanges.isEmpty) {
        mergedRanges.add(range);
        continue;
      }
      final previous = mergedRanges.last;
      final gap = samples[range.$1].deviceMs - samples[previous.$2].deviceMs;
      if (gap < mergeGapMs) {
        mergedRanges[mergedRanges.length - 1] = (previous.$1, range.$2);
      } else {
        mergedRanges.add(range);
      }
    }

    final reps = <RepEmgResult>[];
    for (final range in mergedRanges) {
      final startMs = samples[range.$1].deviceMs;
      final endMs = samples[range.$2].deviceMs;
      final durationMs = endMs - startMs;
      if (durationMs < minimumRepDurationMs ||
          durationMs > maximumRepDurationMs) {
        continue;
      }

      final values = samples
          .sublist(range.$1, range.$2 + 1)
          .map((sample) => sample.adjustedEnv)
          .toList();
      if (values.isEmpty) continue;

      final mean = values.reduce((a, b) => a + b) / values.length;
      final sortedValues = [...values]..sort();
      reps.add(
        RepEmgResult(
          startDeviceMs: startMs,
          endDeviceMs: endMs,
          sampleCount: values.length,
          meanAdjustedEnv: mean,
          p95AdjustedEnv: _percentile(sortedValues, 0.95),
        ),
      );
    }
    return reps;
  }

  List<double> _movingAverage(List<double> values) {
    final smoothed = List<double>.filled(values.length, 0);
    for (var index = 0; index < values.length; index++) {
      final start = math.max(0, index - smoothingRadius);
      final end = math.min(values.length - 1, index + smoothingRadius);
      var sum = 0.0;
      for (var cursor = start; cursor <= end; cursor++) {
        sum += values[cursor];
      }
      smoothed[index] = sum / (end - start + 1);
    }
    return smoothed;
  }

  double _percentile(List<double> sortedValues, double percentile) {
    if (sortedValues.isEmpty) return 0;
    final position = (sortedValues.length - 1) * percentile;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sortedValues[lower];
    final fraction = position - lower;
    return sortedValues[lower] * (1 - fraction) +
        sortedValues[upper] * fraction;
  }
}
