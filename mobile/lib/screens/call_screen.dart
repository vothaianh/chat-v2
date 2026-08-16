import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pulse.dart';

/// Full-screen 1:1 call overlay. Incoming / ringing / live audio+video.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _tick;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;

  static const _hud = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_hud);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final calls = context.read<CallService>();
      if (calls.phase == CallPhase.active) {
        _startedAt ??= DateTime.now();
        setState(() => _elapsed = DateTime.now().difference(_startedAt!));
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay);
    super.dispose();
  }

  String get _clock {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = _elapsed.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  String _status(CallService calls) {
    switch (calls.phase) {
      case CallPhase.incoming:
        return calls.session?.video == true ? 'incoming video' : 'incoming voice';
      case CallPhase.outgoing:
        return calls.session?.video == true ? 'video ringing…' : 'calling…';
      case CallPhase.connecting:
        return 'connecting…';
      case CallPhase.active:
        return _clock;
      case CallPhase.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallService>();
    final session = calls.session;
    final name = session?.peerName ?? 'them';
    final video = session?.video == true;
    final liveVideo = video &&
        (calls.phase == CallPhase.connecting || calls.phase == CallPhase.active);
    final remoteReady = calls.hasRemoteVideo && calls.remoteRenderer.srcObject != null;
    final localReady = calls.localRenderer.srcObject != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _hud,
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (liveVideo)
              _fullscreenVideo(calls, remoteReady: remoteReady, localReady: localReady)
            else
              PulseBackdrop(child: _stage(calls, name, video)),
            if (liveVideo) ...[
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 180,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x99000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 220,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xCC000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: liveVideo ? _videoHeader(calls, name) : const SizedBox.shrink(),
                ),
              ),
            ),
            if (liveVideo && localReady && remoteReady)
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 56, 16, 0),
                    child: _pip(calls),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Material(
                  type: MaterialType.transparency,
                  child: _controls(calls, video),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fullscreenVideo(
    CallService calls, {
    required bool remoteReady,
    required bool localReady,
  }) {
    final renderer = remoteReady ? calls.remoteRenderer : (localReady ? calls.localRenderer : null);
    if (renderer == null) {
      return const ColoredBox(color: Colors.black);
    }
    // UiKitView / SurfaceView steal every tap unless ignored.
    return IgnorePointer(
      child: SizedBox.expand(
        child: RTCVideoView(
          renderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          mirror: !remoteReady && calls.usingFrontCam,
        ),
      ),
    );
  }

  Widget _videoHeader(CallService calls, String name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.display(size: 22, letterSpacing: -0.6),
        ),
        const SizedBox(height: 4),
        Text(
          _status(calls),
          style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: AppTheme.primary),
        ),
      ],
    );
  }

  Widget _stage(CallService calls, String name, bool video) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 36),
          Text(
            video ? 'video' : 'voice',
            style: AppTheme.body(size: 12, weight: FontWeight.w800, color: AppTheme.primary),
          ),
          const SizedBox(height: 18),
          PulseAvatar(label: name, size: 112),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.display(size: 30, letterSpacing: -1),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _status(calls),
            style: AppTheme.body(size: 15, weight: FontWeight.w700, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _pip(CallService calls) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: 112,
          height: 168,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: calls.camOff
              ? const ColoredBox(
                  color: AppTheme.surfaceHigh,
                  child: Icon(Icons.videocam_off_rounded, color: AppTheme.textSecondary),
                )
              : IgnorePointer(
                  child: RTCVideoView(
                    calls.localRenderer,
                    mirror: calls.usingFrontCam,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _controls(CallService calls, bool video) {
    final incoming = calls.phase == CallPhase.incoming;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: incoming ? _incomingRow(calls) : _liveRow(calls, video),
    );
  }

  Widget _incomingRow(CallService calls) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundBtn(
          icon: Icons.call_end_rounded,
          label: 'decline',
          color: AppTheme.danger,
          onTap: calls.reject,
        ),
        _roundBtn(
          icon: calls.session?.video == true ? Icons.videocam_rounded : Icons.call_rounded,
          label: 'accept',
          color: AppTheme.primary,
          ink: AppTheme.primaryInk,
          onTap: calls.accept,
        ),
      ],
    );
  }

  Widget _liveRow(CallService calls, bool video) {
    return FittedBox(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _roundBtn(
            icon: calls.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: calls.muted ? 'unmute' : 'mute',
            color: calls.muted ? AppTheme.surfaceHigh : AppTheme.surfaceElevated,
            onTap: calls.toggleMute,
          ),
          if (video) ...[
            const SizedBox(width: 16),
            _roundBtn(
              icon: calls.camOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
              label: calls.camOff ? 'cam on' : 'cam off',
              color: calls.camOff ? AppTheme.surfaceHigh : AppTheme.surfaceElevated,
              onTap: calls.toggleCamera,
            ),
            const SizedBox(width: 16),
            _roundBtn(
              icon: Icons.cameraswitch_rounded,
              label: 'flip',
              color: AppTheme.surfaceElevated,
              onTap: calls.switchCamera,
            ),
          ],
          const SizedBox(width: 16),
          _roundBtn(
            icon: calls.speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
            label: calls.speakerOn ? 'speaker' : 'earpiece',
            color: calls.speakerOn ? AppTheme.surfaceHigh : AppTheme.surfaceElevated,
            onTap: calls.toggleSpeaker,
          ),
          const SizedBox(width: 16),
          _roundBtn(
            icon: Icons.call_end_rounded,
            label: 'end',
            color: AppTheme.danger,
            onTap: calls.hangup,
          ),
        ],
      ),
    );
  }

  Widget _roundBtn({
    required IconData icon,
    required String label,
    required Color color,
    Color ink = AppTheme.textPrimary,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Icon(icon, color: ink, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: AppTheme.body(size: 11, weight: FontWeight.w700, color: AppTheme.textSecondary)),
      ],
    );
  }
}
