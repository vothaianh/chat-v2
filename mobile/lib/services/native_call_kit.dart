import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'call_service.dart';

/// Apple CallKit (iOS) / full-screen incoming UI (Android).
class NativeCallKit {
  NativeCallKit._();

  static CallService? _calls;
  static bool _bound = false;
  static bool _acting = false;

  static bool get acting => _acting;

  static void bind(CallService calls) {
    _calls = calls;
    if (_bound) return;
    _bound = true;
    FlutterCallkitIncoming.onEvent.listen(_onEvent);
  }

  static CallKitParams _params({
    required String id,
    required String name,
    required String handle,
    required bool video,
    Map<String, dynamic>? extra,
    bool outgoing = false,
  }) {
    return CallKitParams(
      id: id,
      nameCaller: name,
      appName: 'Volt',
      handle: handle,
      type: video ? 1 : 0,
      duration: 45000,
      extra: extra,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#07070B',
        actionColor: '#C6FF4A',
        textColor: '#F4F4F0',
        incomingCallNotificationChannelName: 'Incoming calls',
        missedCallNotificationChannelName: 'Missed calls',
        isShowFullLockedScreen: true,
      ),
      ios: IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: video,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'videoChat',
        audioSessionActive: true,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed call',
      ),
      callingNotification: NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: outgoing ? 'Calling…' : 'On a call',
        callbackText: 'Hang Up',
      ),
    );
  }

  static Future<void> showIncoming({
    required String id,
    required String name,
    required String handle,
    required bool video,
    Map<String, dynamic>? extra,
  }) async {
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(
        _params(id: id, name: name, handle: handle, video: video, extra: extra),
      );
    } catch (e) {
      debugPrint('CallKit show incoming failed: $e');
    }
  }

  static Future<void> startOutgoing({
    required String id,
    required String name,
    required String handle,
    required bool video,
    Map<String, dynamic>? extra,
  }) async {
    try {
      await FlutterCallkitIncoming.startCall(
        _params(
          id: id,
          name: name,
          handle: handle,
          video: video,
          extra: extra,
          outgoing: true,
        ),
      );
    } catch (e) {
      debugPrint('CallKit start outgoing failed: $e');
    }
  }

  static Future<void> connected(String id) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(id);
    } catch (_) {}
  }

  static Future<void> end(String id) async {
    try {
      await FlutterCallkitIncoming.endCall(id);
    } catch (_) {}
  }

  static Future<void> endAll() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }

  static Future<String?> voipToken() async {
    try {
      return await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _onEvent(CallEvent? event) async {
    if (event == null || _acting) return;
    final calls = _calls;
    if (calls == null) return;
    _acting = true;
    try {
      switch (event) {
        case CallEventActionCallAccept(:final callKitParams):
          final extra = callKitParams.extra ?? {};
          if (calls.phase == CallPhase.idle) {
            await calls.presentIncoming({
              'callId': callKitParams.id,
              'conversationId': extra['conversationId'],
              'media': extra['media'] ?? (callKitParams.type == 1 ? 'video' : 'audio'),
              'fromUserId': extra['fromUserId'],
              'fromUsername': extra['fromUsername'] ?? callKitParams.handle,
              'fromFullName': extra['fromFullName'] ?? callKitParams.nameCaller,
            });
          }
          if (calls.phase == CallPhase.incoming) {
            await calls.accept();
          }
        case CallEventActionCallDecline():
          if (calls.phase == CallPhase.incoming) {
            await calls.reject();
          } else if (calls.inCall) {
            await calls.hangup();
          }
        case CallEventActionCallEnded():
          if (calls.inCall) await calls.hangup();
        case CallEventActionCallTimeout():
          if (calls.phase == CallPhase.incoming) await calls.reject();
        default:
          break;
      }
    } catch (e) {
      debugPrint('CallKit event failed: $e');
    } finally {
      _acting = false;
    }
  }
}
