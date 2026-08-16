import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'native_call_kit.dart';
import 'socket_service.dart';

enum CallPhase { idle, outgoing, incoming, connecting, active }

class CallSession {
  final String callId;
  final String conversationId;
  final String peerUserId;
  final String peerName;
  final bool video;
  final bool isCaller;

  const CallSession({
    required this.callId,
    required this.conversationId,
    required this.peerUserId,
    required this.peerName,
    required this.video,
    required this.isCaller,
  });
}

class CallService extends ChangeNotifier {
  CallService(this._socket);

  final SocketService _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;

  CallPhase phase = CallPhase.idle;
  CallSession? session;
  String? lastError;
  bool muted = false;
  bool camOff = false;
  bool speakerOn = true;
  bool usingFrontCam = true;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;
  final _pendingIce = <RTCIceCandidate>[];
  bool _remoteDescSet = false;
  bool _renderersReady = false;
  int _gen = 0;
  Future<void>? _preparing;
  List<Map<String, dynamic>> _iceServers = const [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  VoidCallback? onShowCallUi;

  static const _pendingKey = 'volt_pending_incoming_call';

  bool get inCall => phase != CallPhase.idle;
  bool get hasLocalMedia => _local != null;
  bool get hasRemoteVideo => _remote != null && session?.video == true;

  void bind() {
    _sub?.cancel();
    _sub = _socket.onCallEvent.listen(_onEvent);
    NativeCallKit.bind(this);
  }

  void clearError() {
    if (lastError == null) return;
    lastError = null;
    notifyListeners();
  }

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<bool> startCall({
    required String conversationId,
    required String peerUserId,
    required String peerName,
    required bool video,
  }) async {
    if (phase != CallPhase.idle) {
      lastError = 'already in a call';
      notifyListeners();
      return false;
    }
    if (!_socket.isConnected) {
      lastError = 'you’re offline';
      notifyListeners();
      return false;
    }
    if (!await _ensurePerms(video)) return false;
    final callId = const Uuid().v4();
    session = CallSession(
      callId: callId,
      conversationId: conversationId,
      peerUserId: peerUserId,
      peerName: peerName,
      video: video,
      isCaller: true,
    );
    phase = CallPhase.outgoing;
    lastError = null;
    notifyListeners();
    onShowCallUi?.call();
    _socket.emitCall('call:invite', {
      'conversationId': conversationId,
      'media': video ? 'video' : 'audio',
      'callId': callId,
    });
    return true;
  }

  Future<void> accept() async {
    final s = session;
    if (s == null || phase != CallPhase.incoming) return;
    if (!await _ensurePerms(s.video)) {
      await reject();
      return;
    }
    phase = CallPhase.connecting;
    notifyListeners();
    await _waitForSocket();
    _socket.emitCall('call:accept', {'callId': s.callId});
    try {
      await _ensurePeer(s.video);
    } catch (e) {
      lastError = e.toString();
      await hangup();
    }
  }

  Future<void> reject() async {
    final id = session?.callId;
    if (id != null) _socket.emitCall('call:reject', {'callId': id});
    await _teardown();
  }

  Future<void> hangup() async {
    if (phase == CallPhase.idle && session == null && _pc == null) {
      unawaited(NativeCallKit.endAll());
      return;
    }
    final s = session;
    final ringing = phase == CallPhase.outgoing;
    if (s != null) {
      if (ringing) {
        _socket.emitCall('call:cancel', {'callId': s.callId});
      } else {
        _socket.emitCall('call:hangup', {'callId': s.callId});
      }
    }
    try {
      await _teardown();
    } catch (e) {
      debugPrint('hangup teardown failed: $e');
      phase = CallPhase.idle;
      session = null;
      notifyListeners();
      unawaited(NativeCallKit.endAll());
    }
  }

  Future<void> toggleMute() async {
    muted = !muted;
    _local?.getAudioTracks().forEach((t) => t.enabled = !muted);
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    if (session?.video != true) return;
    camOff = !camOff;
    _local?.getVideoTracks().forEach((t) => t.enabled = !camOff);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (session?.video != true) return;
    final tracks = _local?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
    usingFrontCam = !usingFrontCam;
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await _applyAudioSession();
    await Helper.setSpeakerphoneOn(speakerOn);
    notifyListeners();
  }

  Future<void> _onEvent(Map<String, dynamic> raw) async {
    final event = raw['event'] as String? ?? '';
    final callId = raw['callId'] as String?;
    switch (event) {
      case 'call:incoming':
        await presentIncoming(raw);
        break;
      case 'call:ringing':
        _readIce(raw['iceServers']);
        if (session != null && callId != null && session!.callId != callId) {
          session = CallSession(
            callId: callId,
            conversationId: session!.conversationId,
            peerUserId: session!.peerUserId,
            peerName: session!.peerName,
            video: session!.video,
            isCaller: true,
          );
        }
        break;
      case 'call:busy':
        lastError = 'they’re busy';
        await _teardown();
        break;
      case 'call:accepted':
        if (session == null || session!.isCaller != true) return;
        phase = CallPhase.connecting;
        notifyListeners();
        try {
          await _ensurePeer(session!.video);
          if (session == null) return;
          await _makeOffer();
        } catch (e) {
          lastError = e.toString();
          await hangup();
        }
        break;
      case 'call:offer':
        await _onOffer(raw['sdp']);
        break;
      case 'call:answer':
        await _onAnswer(raw['sdp']);
        break;
      case 'call:ice':
        await _onIce(raw['candidate']);
        break;
      case 'call:ended':
        if (session != null) {
          lastError = _endReason(raw['reason'] as String?);
        }
        await _teardown();
        break;
    }
  }

  String? _endReason(String? reason) {
    switch (reason) {
      case 'rejected':
        return 'declined';
      case 'cancelled':
        return 'cancelled';
      case 'timeout':
        return 'no answer';
      case 'busy':
        return 'busy';
      case 'disconnect':
        return 'call dropped';
      default:
        return null;
    }
  }

  void _readIce(dynamic raw) {
    if (raw is! List) return;
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    if (out.isNotEmpty) _iceServers = out;
  }

  /// Incoming invite from the socket or an FCM / notification tap.
  Future<void> presentIncoming(Map<String, dynamic> raw) async {
    final callId = (raw['callId'] as String?) ?? '';
    if (callId.isEmpty) return;
    if (phase != CallPhase.idle) {
      if (session?.callId == callId) return;
      if (session != null && !session!.isCaller) return;
      _socket.emitCall('call:reject', {'callId': callId});
      return;
    }
    _readIce(raw['iceServers']);
    if (raw['iceServers'] is String) {
      try {
        _readIce(jsonDecode(raw['iceServers'] as String));
      } catch (_) {}
    }
    final fromId = (raw['fromUserId'] as String?) ?? (raw['senderId'] as String?) ?? '';
    final full = raw['fromFullName'] as String?;
    final user = raw['fromUsername'] as String?;
    session = CallSession(
      callId: callId,
      conversationId: raw['conversationId'] as String? ?? '',
      peerUserId: fromId,
      peerName: (full != null && full.isNotEmpty) ? full : (user ?? 'someone'),
      video: raw['media'] == 'video',
      isCaller: false,
    );
    phase = CallPhase.incoming;
    lastError = null;
    notifyListeners();
    onShowCallUi?.call();
    await _savePending(raw);
    unawaited(NativeCallKit.showIncoming(
      id: callId,
      name: session!.peerName,
      handle: session!.peerName,
      video: session!.video,
      extra: {
        'conversationId': session!.conversationId,
        'media': session!.video ? 'video' : 'audio',
        'fromUserId': session!.peerUserId,
        'fromUsername': raw['fromUsername'],
        'fromFullName': raw['fromFullName'],
      },
    ));
  }

  Future<void> restorePendingIncoming() async {
    if (phase != CallPhase.idle) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      final data = Map<String, dynamic>.from(map);
      final savedAt = (data['_savedAt'] as num?)?.toInt() ?? 0;
      if (savedAt > 0 && DateTime.now().millisecondsSinceEpoch - savedAt > 45000) {
        await prefs.remove(_pendingKey);
        return;
      }
      await presentIncoming(data);
      final action = prefs.getString('volt_callkit_action');
      await prefs.remove('volt_callkit_action');
      if (action == 'accept' && phase == CallPhase.incoming) {
        await accept();
      } else if (action == 'decline' && phase == CallPhase.incoming) {
        await reject();
      }
    } catch (_) {}
  }

  Future<void> _savePending(Map<String, dynamic> raw) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _pendingKey,
        jsonEncode({
          'callId': raw['callId'],
          'conversationId': raw['conversationId'],
          'media': raw['media'],
          'fromUserId': raw['fromUserId'] ?? raw['senderId'],
          'fromUsername': raw['fromUsername'],
          'fromFullName': raw['fromFullName'],
          'iceServers': raw['iceServers'] is String ? raw['iceServers'] : jsonEncode(raw['iceServers'] ?? []),
          '_savedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  Future<void> _clearPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey);
    } catch (_) {}
  }

  Future<void> _waitForSocket() async {
    for (var i = 0; i < 25; i++) {
      if (_socket.isConnected) return;
      await Future.delayed(const Duration(milliseconds: 160));
    }
  }

  Future<bool> _ensurePerms(bool video) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      lastError = 'mic permission needed';
      notifyListeners();
      return false;
    }
    if (video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        lastError = 'camera permission needed';
        notifyListeners();
        return false;
      }
    }
    return true;
  }

  Future<void> _ensurePeer(bool video) {
    if (_pc != null) return Future.value();
    return _preparing ??= _preparePeer(video);
  }

  Future<void> _preparePeer(bool video) async {
    final gen = _gen;
    await _ensureRenderers();
    if (gen != _gen) return;
    final local = await _openMedia(video);
    if (gen != _gen) {
      await local.dispose();
      return;
    }
    _local = local;
    localRenderer.srcObject = _local;
    speakerOn = video;
    await _applyAudioSession();
    await Helper.setSpeakerphoneOn(speakerOn);

    final pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });
    if (gen != _gen) {
      await pc.close();
      return;
    }
    _pc = pc;
    pc.onIceCandidate = (c) {
      if (gen != _gen || c.candidate == null || session == null) return;
      _socket.emitCall('call:ice', {
        'callId': session!.callId,
        'candidate': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };
    pc.onTrack = (event) {
      if (gen != _gen || session == null || event.streams.isEmpty) return;
      _remote = event.streams.first;
      remoteRenderer.srcObject = _remote;
      if (phase != CallPhase.active) {
        phase = CallPhase.active;
      }
      notifyListeners();
    };
    pc.onConnectionState = (state) {
      if (gen != _gen || session == null) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        phase = CallPhase.active;
        notifyListeners();
        final id = session?.callId;
        if (id != null && session?.isCaller != true) {
          unawaited(NativeCallKit.connected(id));
        }
        final live = _pc;
        if (live != null) {
          unawaited(_tuneAudioSender(live));
          if (session?.video == true) unawaited(_tuneVideoSender(live));
        }
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        hangup();
      }
    };
    for (final track in local.getTracks()) {
      await pc.addTrack(track, local);
    }
    await _preferBestCodecs(pc);
    await _tuneAudioSender(pc);
    if (video) await _tuneVideoSender(pc);
    notifyListeners();
  }

  Future<void> _applyAudioSession() async {
    try {
      if (WebRTC.platformIsIOS) {
        // videoChat keeps the 48 kHz hardware path; voiceChat sounds thinner.
        await Helper.setAppleAudioConfiguration(
          AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playAndRecord,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.allowBluetooth,
              AppleAudioCategoryOption.allowBluetoothA2DP,
              AppleAudioCategoryOption.allowAirPlay,
              if (speakerOn) AppleAudioCategoryOption.defaultToSpeaker,
            },
            appleAudioMode: AppleAudioMode.videoChat,
          ),
        );
      }
      await Helper.ensureAudioSession();
    } catch (_) {}
  }

  Future<MediaStream> _openMedia(bool video) async {
    await _applyAudioSession();
    final audio = <String, dynamic>{
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'channelCount': 1,
      'sampleRate': 48000,
      'sampleSize': 16,
      'latency': 0.01,
      'googEchoCancellation': true,
      'googAutoGainControl': true,
      'googNoiseSuppression': true,
      'googHighpassFilter': true,
      'googAudioMirroring': false,
    };
    if (!video) {
      final stream = await navigator.mediaDevices.getUserMedia({'audio': audio, 'video': false});
      await _pushAudioQuality(stream);
      return stream;
    }
    // iOS only honors facingMode when it is the string "user" — a
    // {ideal: user} map is ignored and the rear camera opens instead.
    MediaStream stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': audio,
        'video': {
          'facingMode': 'user',
          'width': {'min': 720, 'ideal': 1080},
          'height': {'min': 1280, 'ideal': 1920},
          'frameRate': {'min': 24, 'ideal': 60},
        },
      });
    } catch (_) {
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': audio,
        'video': {'facingMode': 'user'},
      });
    }
    await _ensureFrontCamera(stream);
    await _pushVideoQuality(stream);
    await _pushAudioQuality(stream);
    usingFrontCam = true;
    return stream;
  }

  Future<void> _pushAudioQuality(MediaStream stream) async {
    for (final track in stream.getAudioTracks()) {
      try {
        await track.applyConstraints({
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'sampleRate': 48000,
          'channelCount': 1,
        });
      } catch (_) {}
    }
  }

  bool _looksFront(String? label) {
    final l = (label ?? '').toLowerCase();
    return l.contains('front') || l.contains('user') || l.contains('facetime') || l.contains('selfie');
  }

  bool _looksBack(String? label) {
    final l = (label ?? '').toLowerCase();
    return l.contains('back') || l.contains('rear') || l.contains('environment');
  }

  Future<void> _ensureFrontCamera(MediaStream stream) async {
    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) return;
    if (_looksFront(tracks.first.label) || !_looksBack(tracks.first.label)) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  Future<void> _pushVideoQuality(MediaStream stream) async {
    const attempts = <Map<String, dynamic>>[
      {'width': 1080, 'height': 1920, 'frameRate': 60},
      {'width': 1920, 'height': 1080, 'frameRate': 60},
      {'width': 1080, 'height': 1920, 'frameRate': 30},
      {'width': 1920, 'height': 1080, 'frameRate': 30},
      {'width': 720, 'height': 1280, 'frameRate': 30},
    ];
    for (final track in stream.getVideoTracks()) {
      for (final c in attempts) {
        try {
          await track.applyConstraints(c);
          break;
        } catch (_) {}
      }
    }
  }

  Future<void> _preferBestCodecs(RTCPeerConnection pc) async {
    try {
      final videoCaps = await getRtpSenderCapabilities('video');
      final videoCodecs = [...?videoCaps.codecs];
      int videoRank(RTCRtpCodecCapability c) {
        final m = c.mimeType.toLowerCase();
        final profile = (c.sdpFmtpLine ?? '').toLowerCase();
        if (m.contains('h264')) {
          // High / 4.1 first — hardware encode on iPhone, sharpest 1080p.
          if (profile.contains('640c') || profile.contains('640028')) return 0;
          if (profile.contains('42e01f') || profile.contains('baseline')) return 2;
          return 1;
        }
        if (m.contains('vp9')) return 3;
        if (m.contains('av1')) return 4;
        if (m.contains('vp8')) return 5;
        return 9;
      }

      videoCodecs.sort((a, b) => videoRank(a).compareTo(videoRank(b)));
      final audioCaps = await getRtpSenderCapabilities('audio');
      final audioCodecs = [...?audioCaps.codecs];
      int audioRank(RTCRtpCodecCapability c) {
        final m = c.mimeType.toLowerCase();
        if (m.contains('opus')) return 0;
        if (m.contains('red')) return 1;
        return 9;
      }

      audioCodecs.sort((a, b) => audioRank(a).compareTo(audioRank(b)));
      for (final t in await pc.getTransceivers()) {
        final kind = t.sender.track?.kind ?? t.receiver.track?.kind;
        if (kind == 'video' && videoCodecs.isNotEmpty) {
          await t.setCodecPreferences(videoCodecs);
        } else if (kind == 'audio' && audioCodecs.isNotEmpty) {
          await t.setCodecPreferences(audioCodecs);
        }
      }
    } catch (_) {}
  }

  Future<void> _tuneAudioSender(RTCPeerConnection pc) async {
    try {
      for (final sender in await pc.getSenders()) {
        if (sender.track?.kind != 'audio') continue;
        final params = sender.parameters;
        if (params.encodings == null || params.encodings!.isEmpty) {
          params.encodings = [RTCRtpEncoding()];
        }
        for (final enc in params.encodings!) {
          enc.active = true;
          enc.maxBitrate = 160000;
          enc.minBitrate = 48000;
          enc.priority = RTCPriorityType.high;
          enc.networkPriority = RTCPriorityType.high;
        }
        await sender.setParameters(params);
      }
    } catch (_) {}
  }

  String _boostAudioSdp(String? sdp) {
    if (sdp == null || sdp.isEmpty) return sdp ?? '';
    final opus = RegExp(r'a=rtpmap:(\d+) opus/48000(?:/\d+)?', caseSensitive: false).firstMatch(sdp);
    if (opus == null) return sdp;
    final pt = opus.group(1)!;
    const params =
        'minptime=10;useinbandfec=1;usedtx=0;stereo=0;sprop-stereo=0;maxplaybackrate=48000;sprop-maxcapturerate=48000;maxaveragebitrate=160000;cbr=0';
    final fmtp = 'a=fmtp:$pt $params';
    final existing = RegExp('a=fmtp:$pt\\s+[^\\r\\n]*');
    if (existing.hasMatch(sdp)) return sdp.replaceFirst(existing, fmtp);
    return sdp.replaceFirst(opus.group(0)!, '${opus.group(0)}\r\n$fmtp');
  }

  String _boostVideoSdp(String sdp) {
    // x-google-* bitrates are kbps. Start high so the first frames aren't mushy.
    const extra = 'x-google-min-bitrate=2500;x-google-start-bitrate=4500;x-google-max-bitrate=8000';
    return sdp.replaceAllMapped(
      RegExp(r'(a=fmtp:\d+ [^\r\n]*)'),
      (m) {
        final line = m.group(1)!;
        if (!line.contains('packetization-mode') && !line.contains('profile-level-id') && !line.contains('apt=')) {
          return line;
        }
        if (line.contains('apt=')) return line;
        if (line.contains('x-google-max-bitrate')) return line;
        return '$line;$extra';
      },
    );
  }

  String _boostSdp(String? sdp) => _boostVideoSdp(_boostAudioSdp(sdp));

  Future<void> _tuneVideoSender(RTCPeerConnection pc) async {
    try {
      for (final sender in await pc.getSenders()) {
        if (sender.track?.kind != 'video') continue;
        final params = sender.parameters;
        params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
        if (params.encodings == null || params.encodings!.isEmpty) {
          params.encodings = [RTCRtpEncoding()];
        }
        for (final enc in params.encodings!) {
          enc.active = true;
          enc.maxBitrate = 8000000;
          enc.minBitrate = 2500000;
          enc.maxFramerate = 60;
          enc.scaleResolutionDownBy = 1.0;
          enc.priority = RTCPriorityType.high;
          enc.networkPriority = RTCPriorityType.high;
        }
        await sender.setParameters(params);
      }
    } catch (_) {}
  }

  Future<void> _makeOffer() async {
    final pc = _pc;
    if (pc == null || session == null) return;
    final offer = await pc.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': session!.video,
      'voiceActivityDetection': true,
    });
    final boosted = RTCSessionDescription(_boostSdp(offer.sdp), offer.type);
    await pc.setLocalDescription(boosted);
    _socket.emitCall('call:offer', {
      'callId': session!.callId,
      'sdp': {'type': boosted.type, 'sdp': boosted.sdp},
    });
  }

  Future<void> _onOffer(dynamic raw) async {
    if (session == null) return;
    await _ensurePeer(session!.video);
    if (session == null) return;
    final sdp = _asSdp(raw);
    if (sdp == null || _pc == null) return;
    await _pc!.setRemoteDescription(sdp);
    if (session == null) return;
    _remoteDescSet = true;
    await _flushIce();
    if (session == null || _pc == null) return;
    final answer = await _pc!.createAnswer();
    if (session == null || _pc == null) return;
    final boosted = RTCSessionDescription(_boostSdp(answer.sdp), answer.type);
    await _pc!.setLocalDescription(boosted);
    if (session == null) return;
    _socket.emitCall('call:answer', {
      'callId': session!.callId,
      'sdp': {'type': boosted.type, 'sdp': boosted.sdp},
    });
    phase = CallPhase.connecting;
    notifyListeners();
  }

  Future<void> _onAnswer(dynamic raw) async {
    if (session == null) return;
    final sdp = _asSdp(raw);
    if (sdp == null || _pc == null) return;
    await _pc!.setRemoteDescription(sdp);
    if (session == null) return;
    _remoteDescSet = true;
    await _flushIce();
    if (session == null) return;
    phase = CallPhase.active;
    notifyListeners();
  }

  Future<void> _onIce(dynamic raw) async {
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    final candidate = map['candidate'] as String?;
    if (candidate == null || candidate.isEmpty) return;
    final mid = map['sdpMid'] as String?;
    final rawIdx = map['sdpMLineIndex'];
    int? idx;
    if (rawIdx is int) {
      idx = rawIdx;
    } else if (rawIdx is num) {
      idx = rawIdx.toInt();
    }
    final c = RTCIceCandidate(candidate, mid, idx);
    if (!_remoteDescSet || _pc == null) {
      _pendingIce.add(c);
      return;
    }
    await _pc!.addCandidate(c);
  }

  Future<void> _flushIce() async {
    if (_pc == null) return;
    for (final c in _pendingIce) {
      await _pc!.addCandidate(c);
    }
    _pendingIce.clear();
  }

  RTCSessionDescription? _asSdp(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final type = map['type'] as String?;
    final sdp = map['sdp'] as String?;
    if (type == null || sdp == null) return null;
    return RTCSessionDescription(sdp, type);
  }

  Future<void> _teardown() async {
    final pc = _pc;
    final local = _local;
    _gen++;
    _preparing = null;
    _pendingIce.clear();
    _remoteDescSet = false;
    _pc = null;
    _local = null;
    _remote = null;
    try {
      pc?.onIceCandidate = null;
      pc?.onTrack = null;
      pc?.onConnectionState = null;
    } catch (_) {}
    // Always drop the overlay first. Setting srcObject on a renderer that
    // was never initialize()'d throws ("Call initialize before setting the
    // stream") — that left A stuck on outgoing and B stuck on incoming
    // after a cancel, even though the server had already ended the call.
    phase = CallPhase.idle;
    session = null;
    muted = false;
    camOff = false;
    speakerOn = true;
    usingFrontCam = true;
    notifyListeners();
    if (_renderersReady) {
      try {
        localRenderer.srcObject = null;
      } catch (_) {}
      try {
        remoteRenderer.srcObject = null;
      } catch (_) {}
    }
    unawaited(_clearPending());
    unawaited(NativeCallKit.endAll());
    unawaited(_disposeMedia(pc, local));
  }

  Future<void> _disposeMedia(RTCPeerConnection? pc, MediaStream? local) async {
    try {
      for (final track in local?.getTracks() ?? const <MediaStreamTrack>[]) {
        await track.stop();
      }
    } catch (_) {}
    try {
      await local?.dispose();
    } catch (_) {}
    try {
      await pc?.close().timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    localRenderer.dispose();
    remoteRenderer.dispose();
    _teardown();
    super.dispose();
  }
}
