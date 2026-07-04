import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/features/devices/domain/entities/emg_packet.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BLE v2 packet decoder', () {
    test('decodes a sample packet', () {
      final packet = decodeEmgV2Packet(
        _bytes('{"v":2,"type":"sample","env":36,"deviceMs":1234,"seq":12}'),
      );

      expect(packet, isA<EmgSample>());
      final sample = packet! as EmgSample;
      expect(sample.env, 36);
      expect(sample.deviceMs, 1234);
      expect(sample.seq, 12);
    });

    test('requires baseline, noise, and quality on calibration complete', () {
      final complete = decodeEmgV2Packet(
        _bytes(
          '{"v":2,"type":"calibration","state":"complete",'
          '"baseline":128,"noise":6,"quality":"good"}',
        ),
      );
      final incomplete = decodeEmgV2Packet(
        _bytes(
          '{"v":2,"type":"calibration","state":"complete",'
          '"baseline":128,"noise":6}',
        ),
      );

      expect(complete, isA<EmgCalibration>());
      final calibration = complete! as EmgCalibration;
      expect(calibration.state, EmgCalibrationState.complete);
      expect(calibration.baseline, 128);
      expect(calibration.noise, 6);
      expect(calibration.quality, 'good');
      expect(incomplete, isNull);
    });

    test('decodes quality and rejects inconsistent rail counts', () {
      final valid = decodeEmgV2Packet(
        _bytes(
          '{"v":2,"type":"quality","deviceMs":2000,'
          '"rawSamples":500,"nearRailSamples":5,"clipRatio":0.01}',
        ),
      );
      final invalid = decodeEmgV2Packet(
        _bytes(
          '{"v":2,"type":"quality","deviceMs":2000,'
          '"rawSamples":5,"nearRailSamples":6,"clipRatio":1.0}',
        ),
      );

      expect(valid, isA<EmgQuality>());
      expect((valid! as EmgQuality).clipRatio, 0.01);
      expect(invalid, isNull);
    });
  });

  group('device protocol routing', () {
    test('v2 sample locks protocol and legacy packets cannot switch it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        deviceConnectionControllerProvider.notifier,
      );
      final samples = <EmgSample>[];
      final subscription = controller
          .sampleStream(DeviceSide.left)
          .listen(samples.add);
      addTearDown(subscription.cancel);

      expect(controller.sampleStream(DeviceSide.left).isBroadcast, isTrue);

      controller.handleEmgValueForTesting(
        DeviceSide.left,
        _bytes('{"v":2,"type":"sample","env":42,"deviceMs":100,"seq":1}'),
      );
      controller.handleEmgValueForTesting(
        DeviceSide.left,
        _bytes('{"act":88.5,"raw":2048,"env":42.3,"invalid":0}'),
      );

      final device = container
          .read(deviceConnectionControllerProvider)
          .leftDevice;
      expect(device.protocolVersion, EmgProtocolVersion.v2);
      expect(device.smoothEmg, 0);
      expect(samples, hasLength(1));
      expect(samples.single.env, 42);
    });

    test(
      'legacy packet locks protocol and v2 packets stay out of new stream',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final controller = container.read(
          deviceConnectionControllerProvider.notifier,
        );
        final samples = <EmgSample>[];
        final subscription = controller
            .sampleStream(DeviceSide.left)
            .listen(samples.add);
        addTearDown(subscription.cancel);

        controller.handleEmgValueForTesting(
          DeviceSide.left,
          _bytes('{"act":23.5,"raw":2048,"env":42.3,"invalid":0}'),
        );
        controller.handleEmgValueForTesting(
          DeviceSide.left,
          _bytes('{"v":2,"type":"sample","env":90,"deviceMs":100,"seq":1}'),
        );

        final device = container
            .read(deviceConnectionControllerProvider)
            .leftDevice;
        expect(device.protocolVersion, EmgProtocolVersion.legacy);
        expect(device.smoothEmg, 23.5);
        expect(samples, isEmpty);
      },
    );

    test('quality alone does not identify v2 but calibration does', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        deviceConnectionControllerProvider.notifier,
      );
      final qualityPackets = <EmgQuality>[];
      final calibrationPackets = <EmgCalibration>[];
      final qualitySubscription = controller
          .qualityStream(DeviceSide.left)
          .listen(qualityPackets.add);
      final calibrationSubscription = controller
          .calibrationStream(DeviceSide.left)
          .listen(calibrationPackets.add);
      addTearDown(qualitySubscription.cancel);
      addTearDown(calibrationSubscription.cancel);

      controller.handleEmgValueForTesting(
        DeviceSide.left,
        _bytes(
          '{"v":2,"type":"quality","deviceMs":1000,'
          '"rawSamples":500,"nearRailSamples":0,"clipRatio":0.0}',
        ),
      );
      expect(
        container
            .read(deviceConnectionControllerProvider)
            .leftDevice
            .protocolVersion,
        EmgProtocolVersion.unknown,
      );
      expect(qualityPackets, isEmpty);

      controller.handleEmgValueForTesting(
        DeviceSide.left,
        _bytes('{"v":2,"type":"calibration","state":"preparing"}'),
      );

      expect(
        container
            .read(deviceConnectionControllerProvider)
            .leftDevice
            .protocolVersion,
        EmgProtocolVersion.v2,
      );
      expect(calibrationPackets, hasLength(1));
    });

    test(
      'sample stream reports sequence gaps and device timestamp rollback',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final controller = container.read(
          deviceConnectionControllerProvider.notifier,
        );
        final samples = <EmgSample>[];
        final subscription = controller
            .sampleStream(DeviceSide.left)
            .listen(samples.add);
        addTearDown(subscription.cancel);

        controller.handleEmgValueForTesting(
          DeviceSide.left,
          _bytes('{"v":2,"type":"sample","env":10,"deviceMs":100,"seq":10}'),
        );
        controller.handleEmgValueForTesting(
          DeviceSide.left,
          _bytes('{"v":2,"type":"sample","env":11,"deviceMs":120,"seq":13}'),
        );
        controller.handleEmgValueForTesting(
          DeviceSide.left,
          _bytes('{"v":2,"type":"sample","env":12,"deviceMs":5,"seq":0}'),
        );

        expect(samples, hasLength(3));
        expect(samples[0].missingSamples, 0);
        expect(samples[0].deviceRestarted, isFalse);
        expect(samples[1].missingSamples, 2);
        expect(samples[1].deviceRestarted, isFalse);
        expect(samples[2].missingSamples, 0);
        expect(samples[2].deviceRestarted, isTrue);
      },
    );
  });
}

List<int> _bytes(String value) => utf8.encode(value);
