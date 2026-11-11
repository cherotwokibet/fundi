import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

typedef Recording = ({Uint8List bytes, String mime});

/// Records a short voice note with the device microphone.
abstract class VoiceRecorder {
  /// Returns false if the microphone is not allowed or not available.
  Future<bool> start();

  /// Stops and returns the recording, or null if nothing was recorded.
  Future<Recording?> stop();

  Future<void> cancel();
}

class DeviceVoiceRecorder implements VoiceRecorder {
  AudioRecorder? _recorder;

  // Browsers record Opus in WebM; phones record AAC in an .m4a file.
  static const _mime = kIsWeb ? 'audio/webm' : 'audio/mp4';

  @override
  Future<bool> start() async {
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) return false;
      // On the web the path is ignored; on phones the plugin needs one.
      final path = kIsWeb
          ? ''
          : '${await _tempDir()}/fundi-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(
          encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
          bitRate: 32000,
          numChannels: 1,
        ),
        path: path,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Recording?> stop() async {
    try {
      final path = await _recorder?.stop();
      if (path == null) return null;
      final bytes = await XFile(path).readAsBytes();
      if (bytes.isEmpty) return null;
      return (bytes: bytes, mime: _mime);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _recorder?.cancel();
    } catch (_) {}
  }

  Future<String> _tempDir() async => (await getTemporaryDirectory()).path;
}
