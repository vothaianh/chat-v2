import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Looping PSTN-style ringback while the caller waits on the outgoing screen.
class CallRingtone {
  CallRingtone._();

  static final AudioPlayer _player = AudioPlayer();
  static int _token = 0;
  static bool _ready = false;

  static Future<void> _ensure() async {
    if (_ready) return;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(0.72);
    await _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: const {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.allowBluetooth,
          },
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          audioMode: AndroidAudioMode.inCommunication,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.voiceCommunicationSignalling,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
    _ready = true;
  }

  static Future<void> start() async {
    final token = ++_token;
    try {
      await _ensure();
      if (token != _token) return;
      await _player.stop();
      if (token != _token) return;
      await _player.play(AssetSource('sounds/ringback.wav'));
      if (token != _token) {
        await _player.stop();
      }
    } catch (e) {
      debugPrint('ringback start failed: $e');
    }
  }

  static Future<void> stop() async {
    _token++;
    try {
      await _player.stop();
    } catch (_) {}
  }
}
