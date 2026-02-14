// Shared RTA audio capture + FFT service
// Used by both the standalone RTA tab and the GEQ overlay.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
// ignore: implementation_imports
import 'package:flutter_recorder/src/enums.dart' show CaptureDevice;
import 'package:fftea/fftea.dart';

// ─── Constants ───

const int rtaFftSize = 8192; // ~5.4Hz per bin at 44100Hz
const int rtaSampleRate = 44100;
const int rtaBandCount = 128;
const double rtaDisplayMinFreq = 20.0;
const double rtaDisplayMaxFreq = 20000.0;
const double rtaMinDb = -140.0;
const double rtaMaxDb = 10.0;
const double rtaDbRange = rtaMaxDb - rtaMinDb;
const double rtaPeakDecayDbPerSec = 6.0;

/// Pre-computed log-spaced band edge frequencies.
/// Band i spans from rtaBandEdges[i] to rtaBandEdges[i+1].
final List<double> rtaBandEdges = () {
  final logMin = math.log(rtaDisplayMinFreq);
  final logMax = math.log(rtaDisplayMaxFreq);
  return List<double>.generate(
    rtaBandCount + 1,
    (i) => math.exp(logMin + (logMax - logMin) * i / rtaBandCount),
  );
}();

/// Manages microphone capture, FFT processing, and peak hold for RTA display.
class RtaService {
  List<double> magnitudes = List.filled(rtaBandCount, rtaMinDb);
  List<double> peaks = List.filled(rtaBandCount, rtaMinDb);
  bool isRunning = false;
  bool isInitialized = false;

  /// Called when new FFT data is ready — set this to trigger UI updates.
  VoidCallback? onUpdate;

  final FFT _fft = FFT(rtaFftSize);
  final List<double> _sampleBuffer = [];
  StreamSubscription? _audioSubscription;
  Timer? _uiTimer;
  bool _hasPendingUpdate = false;
  DateTime _lastProcessTime = DateTime.now();

  List<CaptureDevice> enumerateDevices() {
    return Recorder.instance.listCaptureDevices();
  }

  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        const channel = MethodChannel('dsp/permissions');
        return await channel.invokeMethod<bool>('requestMicrophone') ?? false;
      } catch (_) {
        return true;
      }
    }
    return true;
  }

  /// Start audio capture and FFT processing.
  /// [deviceId] — capture device ID (0 = default on mobile).
  Future<void> startCapture({required int deviceId}) async {
    try {
      await Recorder.instance.init(
        deviceID: deviceId,
        format: PCMFormat.f32le,
        sampleRate: rtaSampleRate,
        channels: RecorderChannels.mono,
      );
      Recorder.instance.start();
      Recorder.instance.startStreamingData();
      isInitialized = true;
      isRunning = true;
      _lastProcessTime = DateTime.now();

      _sampleBuffer.clear();
      _audioSubscription =
          Recorder.instance.uint8ListStream.listen((container) {
        final f32 = container.toF32List(from: PCMFormat.f32le);
        _sampleBuffer.addAll(f32);

        while (_sampleBuffer.length >= rtaFftSize) {
          _processFFT(_sampleBuffer.sublist(0, rtaFftSize));
          _sampleBuffer.removeRange(0, rtaFftSize ~/ 2); // 50% overlap
        }
      });

      // Throttle UI updates to ~30fps
      _uiTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (_hasPendingUpdate) {
          _hasPendingUpdate = false;
          onUpdate?.call();
        }
      });
    } catch (e) {
      debugPrint('RtaService: Failed to start capture: $e');
      rethrow;
    }
  }

  void _processFFT(List<double> samples) {
    // Apply Hanning window
    final windowed = Float64List(rtaFftSize);
    for (int i = 0; i < rtaFftSize; i++) {
      final w = 0.5 * (1 - math.cos(2 * math.pi * i / (rtaFftSize - 1)));
      windowed[i] = samples[i] * w;
    }

    // Compute FFT
    final spectrum = _fft.realFft(windowed);
    final rawMags = spectrum.discardConjugates().magnitudes();

    // Aggregate linear FFT bins into log-spaced bands
    const binFreqStep = rtaSampleRate / rtaFftSize;
    final bandDb = List<double>.filled(rtaBandCount, rtaMinDb);

    for (int b = 0; b < rtaBandCount; b++) {
      final loFreq = rtaBandEdges[b];
      final hiFreq = rtaBandEdges[b + 1];

      final loBin =
          (loFreq / binFreqStep).floor().clamp(1, rawMags.length - 1);
      final hiBin =
          (hiFreq / binFreqStep).ceil().clamp(1, rawMags.length - 1);

      if (loBin >= hiBin) {
        final centerBin = ((loFreq + hiFreq) / 2 / binFreqStep)
            .round()
            .clamp(1, rawMags.length - 1);
        final mag = rawMags[centerBin] / rtaFftSize;
        if (mag > 0) {
          bandDb[b] =
              (20 * math.log(mag) / math.ln10).clamp(rtaMinDb, rtaMaxDb);
        }
      } else {
        double sum = 0;
        for (int i = loBin; i < hiBin; i++) {
          sum += rawMags[i];
        }
        final mag = sum / (hiBin - loBin) / rtaFftSize;
        if (mag > 0) {
          bandDb[b] =
              (20 * math.log(mag) / math.ln10).clamp(rtaMinDb, rtaMaxDb);
        }
      }
    }

    // Peak hold with decay
    final now = DateTime.now();
    final dt = now.difference(_lastProcessTime).inMicroseconds / 1e6;
    _lastProcessTime = now;
    final decay = rtaPeakDecayDbPerSec * dt;

    final newPeaks = List<double>.filled(rtaBandCount, rtaMinDb);
    for (int b = 0; b < rtaBandCount; b++) {
      final decayed = peaks[b] - decay;
      newPeaks[b] = math.max(bandDb[b], decayed).clamp(rtaMinDb, rtaMaxDb);
    }

    magnitudes = bandDb;
    peaks = newPeaks;
    _hasPendingUpdate = true;
  }

  /// Stop capture and reset display state.
  void stopCapture() {
    release();
    magnitudes = List.filled(rtaBandCount, rtaMinDb);
    peaks = List.filled(rtaBandCount, rtaMinDb);
  }

  /// Release native resources — safe to call from dispose().
  void release() {
    _uiTimer?.cancel();
    _uiTimer = null;
    _hasPendingUpdate = false;
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _sampleBuffer.clear();

    if (isInitialized) {
      try {
        Recorder.instance.stopStreamingData();
        Recorder.instance.deinit();
      } catch (e) {
        debugPrint('RtaService: Failed to stop capture: $e');
      }
      isInitialized = false;
    }
    isRunning = false;
  }
}
