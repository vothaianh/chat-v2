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
    unawaited(NativeCallKit.startOutgoing(
      id: callId,
      name: peerName,
      handle: peerName,
      video: video,
      extra: {'conversationId': conversationId, 'media': video ? 'video' : 'audio'},
    ));
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
    final s = session;
    if (s == null) {
      await _teardown();
      return;
    }
    if (phase == CallPhase.outgoing) {
      _socket.emitCall('call:cancel', {'callId': s.callId});
    } else {
      _socket.emitCall('call:hangup', {'callId': s.callId});
    }
    await _teardown();
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
      if (c.candidate == null || session == null) return;
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
      if (event.streams.isEmpty) return;
      _remote = event.streams.first;
      remoteRenderer.srcObject = _remote;
      if (phase != CallPhase.active) {
        phase = CallPhase.active;
      }
      notifyListeners();
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        phase = CallPhase.active;
        notifyListeners();
        final id = session?.callId;
        if (id != null) unawaited(NativeCallKit.connected(id));
        final live = _pc;
        if (live != null && session?.video == true) {
          _tuneVideoSender(live);
        }
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        hangup();
      }
    };
    for (final track in local.getTracks()) {
      await pc.addTrack(track, local);
    }
    if (video) {
      await _preferBestCodecs(pc);
      await _tuneVideoSender(pc);
    }
    notifyListeners();
  }

  Future<MediaStream> _openMedia(bool video) async {
    final audio = <String, dynamic>{
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'sampleRate': 48000,
      'channelCount': 1,
    };
    if (!video) {
      return navigator.mediaDevices.getUserMedia({'audio': audio, 'video': false});
    }
    // iOS only honors facingMode when it is the string "user" — a
    // {ideal: user} map is ignored and the rear camera opens instead.
    MediaStream stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': audio,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1080},
          'height': {'ideal': 1920},
          'frameRate': {'ideal': 30},
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
    usingFrontCam = true;
    return stream;
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
    for (final track in stream.getVideoTracks()) {
      try {
        await track.applyConstraints({
          'width': 1080,
          'height': 1920,
          'frameRate': 30,
        });
      } catch (_) {
        try {
          await track.applyConstraints({
            'width': 1920,
            'height': 1080,
            'frameRate': 30,
          });
        } catch (_) {}
      }
    }
  }

  Future<void> _preferBestCodecs(RTCPeerConnection pc) async {
    try {
      final caps = await getRtpSenderCapabilities('video');
      final codecs = [...?caps.codecs];
      int rank(RTCRtpCodecCapability c) {
        final m = c.mimeType.toLowerCase();
        if (m.contains('h264')) return 0;
        if (m.contains('vp9')) return 1;
        if (m.contains('av1')) return 2;
        if (m.contains('vp8')) return 3;
        return 9;
      }

      codecs.sort((a, b) => rank(a).compareTo(rank(b)));
      if (codecs.isEmpty) return;
      for (final t in await pc.getTransceivers()) {
        final kind = t.sender.track?.kind ?? t.receiver.track?.kind;
        if (kind == 'video') {
          await t.setCodecPreferences(codecs);
        }
      }
    } catch (_) {}
  }

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
          enc.maxBitrate = 4500000;
          enc.minBitrate = 1200000;
          enc.maxFramerate = 30;
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
    });
    await pc.setLocalDescription(offer);
    _socket.emitCall('call:offer', {
      'callId': session!.callId,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  Future<void> _onOffer(dynamic raw) async {
    if (session == null) return;
    await _ensurePeer(session!.video);
    final sdp = _asSdp(raw);
    if (sdp == null || _pc == null) return;
    await _pc!.setRemoteDescription(sdp);
    _remoteDescSet = true;
    await _flushIce();
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    _socket.emitCall('call:answer', {
      'callId': session!.callId,
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });
    phase = CallPhase.connecting;
    notifyListeners();
  }

  Future<void> _onAnswer(dynamic raw) async {
    final sdp = _asSdp(raw);
    if (sdp == null || _pc == null) return;
    await _pc!.setRemoteDescription(sdp);
    _remoteDescSet = true;
    await _flushIce();
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
    final endedId = session?.callId;
    _gen++;
    _preparing = null;
    unawaited(_clearPending());
    if (!NativeCallKit.acting && endedId != null) {
      unawaited(NativeCallKit.end(endedId));
    }
    _pendingIce.clear();
    _remoteDescSet = false;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      await _local?.dispose();
    } catch (_) {}
    _local = null;
    _remote = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    phase = CallPhase.idle;
    session = null;
    muted = false;
    camOff = false;
    speakerOn = true;
    usingFrontCam = true;
    notifyListeners();
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
