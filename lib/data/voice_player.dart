import 'package:audioplayers/audioplayers.dart';

/// Plays a voice note from a link.
abstract class VoicePlayer {
  /// Completes when playback ends or is stopped. Throws if it cannot play.
  Future<void> play(String url);
  Future<void> stop();
}

class DeviceVoicePlayer implements VoicePlayer {
  AudioPlayer? _player;

  @override
  Future<void> play(String url) async {
    final player = _player ??= AudioPlayer();
    await player.stop();
    final done = player.onPlayerComplete.first;
    await player.play(UrlSource(url));
    await Future.any([
      done,
      player.onPlayerStateChanged.firstWhere((s) => s == PlayerState.stopped),
    ]);
  }

  @override
  Future<void> stop() async => _player?.stop();
}
