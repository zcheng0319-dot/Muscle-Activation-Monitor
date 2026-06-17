import 'dart:async';
import 'dart:math';

class MockEmgDataSource {
  final _random = Random();
  int _tick = 0;

  Stream<(int, int)> watchActivation() {
    return Stream.periodic(const Duration(milliseconds: 650), (_) {
      _tick++;
      final wave = sin(_tick / 2.3) * 24;
      final left = (58 + wave + _random.nextInt(10)).round().clamp(5, 98);
      final right = (55 + wave * 0.9 + _random.nextInt(12)).round().clamp(
        5,
        98,
      );
      return (left, right);
    });
  }
}
