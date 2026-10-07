import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frequency_scanner/audio/recommendations.dart';
import 'package:frequency_scanner/audio/tone_generator.dart';
import 'package:frequency_scanner/platform/system_controls.dart';
import 'package:frequency_scanner/scanner_controller.dart';
import 'package:record/record.dart';

/// Micrófono simulado que emite un tono de 1 kHz mientras está grabando.
class FakeRecorder implements AudioRecorder {
  StreamController<Uint8List>? _controller;
  Timer? _timer;
  int _n = 0;

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    final controller = _controller = StreamController<Uint8List>();
    _timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final data = ByteData(4096 * 2);
      for (var i = 0; i < 4096; i++) {
        final v = (0.5 * math.sin(2 * math.pi * 1000 * _n++ / 44100) * 32767).round();
        data.setInt16(i * 2, v, Endian.little);
      }
      controller.add(data.buffer.asUint8List());
    });
    return controller.stream;
  }

  @override
  Future<String?> stop() async {
    _timer?.cancel();
    await _controller?.close();
    return null;
  }

  @override
  Future<void> dispose() async => stop();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTone implements ToneGenerator {
  final List<String> calls = [];
  double? frequency;

  @override
  Future<void> start({required double frequency, required double amplitude}) async {
    this.frequency = frequency;
    calls.add('start');
  }

  @override
  Future<void> update({required double frequency, required double amplitude}) async {
    this.frequency = frequency;
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

class FakeSystem implements SystemControls {
  final List<String> calls = [];

  @override
  void setStopHandler(void Function() onStop) {}

  @override
  Future<void> keepScreenOn(bool on) async => calls.add('screen:$on');

  @override
  Future<void> startBackgroundService(String text) async => calls.add('start');

  @override
  Future<void> updateBackgroundService(String text) async => calls.add('update');

  @override
  Future<void> stopBackgroundService() async => calls.add('stop');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('El modo continuo alterna escaneo y reproducción indefinidamente', () async {
    final tone = FakeTone();
    final system = FakeSystem();
    final c = ScannerController(
      recorder: FakeRecorder(),
      toneGenerator: tone,
      systemControls: system,
      cycleScanDuration: const Duration(milliseconds: 400),
      cyclePlayDuration: const Duration(milliseconds: 300),
    );

    await c.startCycle();
    expect(c.isCycleActive, isTrue);
    expect(c.isScanning, isTrue);
    expect(system.calls, containsAll(['screen:true', 'start']));

    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(c.cyclePhase, CyclePhase.playing);
    expect(c.isScanning, isFalse);
    expect(c.isPlaying, isTrue);
    // Por defecto suena la frecuencia ausente (no el tono de 1 kHz captado).
    expect(c.suggested!.label, missingLabel);
    expect(iso266ThirdOctave, contains(tone.frequency));
    expect(tone.frequency, isNot(1000));
    expect(system.calls, contains('screen:false'));

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(c.cyclePhase, CyclePhase.scanning);
    expect(c.cycleCount, 2);
    expect(c.isPlaying, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(c.cyclePhase, CyclePhase.playing);
    // El servicio en segundo plano no se detiene entre fases.
    expect(system.calls.where((x) => x == 'stop'), isEmpty);

    await c.stopAll();
    expect(c.isCycleActive, isFalse);
    expect(c.isPlaying, isFalse);
    expect(system.calls.last, 'stop');
    c.dispose();
  });
}
