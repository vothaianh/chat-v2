import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'message_store.dart';
import 'native_call_kit.dart';

/// Manages FCM: initialization, token acquisition/refresh, permission requests,
/// registering the device token with the backend, and showing local notifications
/// for messages that arrive while the app is in the foreground.
///
/// On web/desktop, Firebase Messaging is a no-op; tokens are only registered on
/// Android/iOS. The backend already gracefully stubs push when no tokens exist.
class PushService {
  static final PushService instance = PushService._();
  PushService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _token;
  String? _authToken; // backend JWT, set after login

  /// Set by [AppState]. When a message arrives via FCM while the app is in the
  /// foreground, we reconstruct a [ChatMessage] and hand it here so the open
  /// chat list updates live AND it gets persisted to the local store. The
  /// background isolate can't reach this (different isolate) — it writes to the
  /// store directly and the app re-hydrates on resume.
  void Function(ChatMessage)? onPersistMessage;

  /// Set by [AppState]. Invoked with a conversationId when the user taps a
  /// notification (foreground local-notification tap, or a background/terminated
  /// FCM message that the OS opened the app from). The UI layer resolves the
  /// conversation and pushes the [ChatScreen].
  void Function(String conversationId)? onTapConversation;

  /// Incoming call from FCM / notification tap. [AppState] feeds [CallService].
  void Function(Map<String, dynamic> data)? onIncomingCall;

  /// Top-level handler for messages that arrive while the app is in the background
  /// or terminated. Must be a top-level function (not a closure or class method).
  ///
  /// We persist the message to the per-account local [MessageStore] so it's
  /// still visible when the user reopens the app (FCM is the only copy — the
  /// server never stores messages). This runs in a separate isolate, so it
  /// opens its own [MessageStore] from the userId saved in SharedPreferences by
  /// [AuthService]; the main isolate re-hydrates from disk on resume.
  @pragma('vm:entry-point')
  static Future<void> onBackgroundMessage(RemoteMessage message) async {
    debugPrint('FCM background: ${message.messageId} ${message.notification?.title}');
    if (message.data['type'] == 'call') {
      await _persistIncomingCall(message.data);
      return;
    }
    await _persistFcmMessage(message);
  }

  static Future<void> _persistIncomingCall(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'volt_pending_incoming_call',
        jsonEncode({
          ...data,
          '_savedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      debugPrint('FCM persist incoming call failed: $e');
    }
  }

  /// Reconstructs the [ChatMessage] from the FCM data payload and writes it to
  /// the per-account local store. Shared by the foreground and background paths
  /// (background calls this directly from the static handler; foreground goes
  /// through [onPersistMessage] which also updates the live in-memory list).
  static Future<void> _persistFcmMessage(RemoteMessage message) async {
    final data = message.data;
    if (data['messageId'] == null) return;
    try {
      final m = ChatMessage.fromFcmData(Map<String, dynamic>.from(data));
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(AuthService.kUserIdKey);
      if (userId == null) return;
      final store = MessageStore();
      await store.open(userId);
      await store.upsert(m);
      await store.close();
    } catch (e) {
      debugPrint('FCM persist failed: $e');
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Firebase Messaging only works on Android/iOS. Skip on other platforms.
    if (!Platform.isAndroid && !Platform.isIOS) return;

    await Firebase.initializeApp();

    // Local notifications for foreground FCM messages.
    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_volt');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        debugPrint('Local notification tapped: payload=$payload');
        if (payload == null || payload.isEmpty) return;
        if (payload.startsWith('call:')) {
          _dispatchIncomingCall(payload.substring(5));
          return;
        }
        onTapConversation?.call(payload);
      },
    );

    // Cold start from a notification posted by flutter_local_notifications (the
    // foreground path). iOS attributes that launch to this plugin rather than
    // FCM, so getInitialMessage() below returns null for it and the payload has
    // to be picked up here instead. Replayed in [attach] like the FCM case.
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final payload = launch?.notificationResponse?.payload;
      debugPrint('Local notification cold-start: payload=$payload');
      if (payload != null && payload.isNotEmpty) {
        if (payload.startsWith('call:')) {
          _pendingIncomingRaw = payload.substring(5);
        } else {
          _pendingTapConversationId = payload;
        }
      }
    }

    // Create an Android notification channel for chat messages.
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'chat_messages',
          'Chat messages',
          description: 'Incoming chat messages',
          importance: Importance.high,
        ));
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'incoming_calls',
          'Incoming calls',
          description: 'Incoming voice and video calls',
          importance: Importance.max,
          playSound: true,
        ));

    FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);

    // FCM owns the iOS notification-center delegate; without this it suppresses
    // any notification (including our local ones) while the app is foreground.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground messages: show a local notification so the user sees them.
    FirebaseMessaging.onMessage.listen(_handleForeground);

    // User tapped a notification that opened the app from background state.
    // Persist the message (the banner only carries an alert — the message
    // content is in the data payload, which we reconstruct into the local
    // store here) and then open the conversation.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTapMessage);

    // Cold start: a notification tap launched the app from terminated state.
    // Captured here and replayed in [attach] once the user is authenticated and
    // the UI has wired [onTapConversation] (init() runs before auth.load()).
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    debugPrint('FCM getInitialMessage: ${initial == null ? "NULL (no cold-start tap / sim did not deliver)" : "conversationId=${initial.data['conversationId']}"}');
    if (initial != null) {
      if (initial.data['type'] == 'call') {
        _pendingIncomingData = Map<String, dynamic>.from(initial.data);
      } else {
        _pendingTapMessage = initial;
      }
      debugPrint('FCM cold-start tap pending: conversationId=${initial.data['conversationId']} type=${initial.data['type']}');
    }

    // Token refresh → re-register with the backend if we have a JWT.
    FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);
  }

  /// A cold-start notification tap captured in [init] before auth was loaded.
  /// Replayed in [attach] once the UI is ready.
  RemoteMessage? _pendingTapMessage;

  /// Same, for a cold start from a local notification — that path only carries
  /// the payload (the conversation id), not a full [RemoteMessage].
  String? _pendingTapConversationId;

  /// Incoming-call payload waiting for [onIncomingCall] to be wired.
  Map<String, dynamic>? _pendingIncomingData;
  String? _pendingIncomingRaw;

  void _dispatchIncomingCall(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _emitIncoming(Map<String, dynamic>.from(decoded));
        return;
      }
    } catch (_) {}
    _emitIncoming({'callId': raw});
  }

  void _emitIncoming(Map<String, dynamic> data) {
    final cb = onIncomingCall;
    if (cb != null) {
      cb(data);
      return;
    }
    _pendingIncomingData = data;
  }

  /// Persist the message from its FCM data payload, then open the conversation.
  /// The banner only shows an alert; the message body lives in `data`, so we
  /// reconstruct + persist it here (in both warm and cold-start tap paths) —
  /// iOS does not run [onBackgroundMessage] for alert notifications, so without
  /// this the tapped message would never reach the local store and the chat
  /// would open empty.
  Future<void> _handleTapMessage(RemoteMessage message) async {
    if (message.data['type'] == 'call') {
      _emitIncoming(Map<String, dynamic>.from(message.data));
      return;
    }
    final conversationId = message.data['conversationId'] as String?;
    if (conversationId == null || conversationId.isEmpty) return;
    debugPrint('FCM tap → conversationId=$conversationId, callback set=${onTapConversation != null}');
    // This runs in the main isolate, where AppState already holds an open store.
    // Persist through it when wired: the static fallback opens its own
    // MessageStore and closes it when done, and sqflite hands both instances the
    // same underlying connection — so that close would shut the database out
    // from under AppState, and the navigation that follows dies on
    // DatabaseException(database_closed). The fallback is for the case where
    // AppState hasn't wired up yet.
    final persist = onPersistMessage;
    if (persist != null && message.data['messageId'] != null) {
      try {
        persist(ChatMessage.fromFcmData(Map<String, dynamic>.from(message.data)));
      } catch (e) {
        debugPrint('FCM tap persist failed: $e');
      }
    } else {
      await _persistFcmMessage(message); // persist so it shows when the chat opens
    }
    onTapConversation?.call(conversationId);
  }

  /// Called after the user logs in. Requests permissions, gets the token, and
  /// registers it with the backend so the server can push to this device.
  ///
  /// This is best-effort: any FCM failure (e.g. iOS Simulator has no APNS token)
  /// is swallowed so it can never block app startup or login.
  Future<void> attach(String authToken) async {
    _authToken = authToken;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await init();

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('FCM permission: ${settings.authorizationStatus}');
      try {
        await FlutterCallkitIncoming.requestNotificationPermission({
          'title': 'Notifications',
          'rationaleMessagePermission': 'Volt needs notifications so incoming calls can ring.',
          'postNotificationMessageRequired': 'Allow notifications so you don’t miss calls.',
        });
        await FlutterCallkitIncoming.requestFullIntentPermission();
      } catch (_) {}

      // On iOS, getToken() requires an APNS token which the Simulator never
      // provides — guard so it doesn't throw and abort startup.
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _token = token;
        await _registerWithBackend(token);
      }
      await registerVoipToken();

      // Now that the user is authenticated and the UI has wired [onTapConversation],
      // replay a cold-start notification tap captured in [init] — persist the
      // message then open the conversation.
      final pending = _pendingTapMessage;
      final pendingConversationId = _pendingTapConversationId;
      _pendingTapMessage = null;
      _pendingTapConversationId = null;
      final pendingIncoming = _pendingIncomingData;
      final pendingIncomingRaw = _pendingIncomingRaw;
      _pendingIncomingData = null;
      _pendingIncomingRaw = null;
      if (pendingIncoming != null) {
        onIncomingCall?.call(pendingIncoming);
      } else if (pendingIncomingRaw != null) {
        _dispatchIncomingCall(pendingIncomingRaw);
      } else if (pending != null) {
        await _handleTapMessage(pending);
      } else if (pendingConversationId != null) {
        // Local-notification cold start: no data payload to persist, just open
        // the conversation from the cached history.
        debugPrint('Local cold-start tap → conversationId=$pendingConversationId');
        onTapConversation?.call(pendingConversationId);
      }
    } catch (e) {
      debugPrint('FCM attach skipped: $e');
    }
  }

  /// Called on logout — unregisters this device's token from the backend.
  Future<void> detach() async {
    if (_token != null && _authToken != null) {
      try {
        await ApiService.unregisterDevice(_authToken!, _token!);
      } catch (_) {}
    }
    _authToken = null;
    _token = null;
  }

  Future<void> _onTokenRefresh(String token) async {
    _token = token;
    if (_authToken != null) await _registerWithBackend(token);
  }

  Future<void> registerVoipToken() async {
    if (_authToken == null) return;
    NativeCallKit.onVoipToken = (token) {
      final auth = _authToken;
      if (auth == null || token.isEmpty) return;
      ApiService.registerDevice(auth, token, platform: 'ios-voip').then((_) {
        debugPrint('VoIP token registered');
      }).catchError((e) {
        debugPrint('VoIP token register failed: $e');
      });
    };
    try {
      String? voip;
      for (var i = 0; i < 16; i++) {
        voip = await NativeCallKit.voipToken();
        voip ??= (await SharedPreferences.getInstance()).getString('volt_voip_token');
        if (voip != null && voip.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (voip != null && voip.isNotEmpty) {
        await ApiService.registerDevice(_authToken!, voip, platform: 'ios-voip');
        debugPrint('VoIP token registered');
      } else {
        debugPrint('VoIP token not ready yet');
      }
    } catch (e) {
      debugPrint('VoIP token register skipped: $e');
    }
  }

  Future<void> _registerWithBackend(String token) async {
    if (_authToken == null) return;
    final platform = Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'web';
    try {
      await ApiService.registerDevice(_authToken!, token, platform: platform);
      debugPrint('FCM token registered with backend ($platform)');
    } catch (e) {
      debugPrint('FCM register failed: $e');
    }
  }

  /// Notification ids must fit in a signed 32-bit integer on both platforms.
  /// Epoch millis overflow it outright and hash codes can too, so fold the
  /// seed down to 31 bits.
  static int _notificationId(Object seed) => seed.hashCode & 0x7fffffff;

  /// Shows an in-app banner for a message delivered over the socket while the
  /// app is in the foreground. FCM covers the offline/background case; this
  /// covers online delivery, which never triggers an FCM `onMessage`.
  Future<void> showMessageNotification({
    required String title,
    required String body,
    String? conversationId,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await init();
      await _local.show(
        id: _notificationId(conversationId ?? title),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'chat_messages',
            'Chat messages',
            icon: '@drawable/ic_stat_volt',
            color: Color(0xFFC6FF4A),
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: conversationId,
      );
    } catch (e) {
      debugPrint('local notification failed: $e');
    }
  }

  void _handleForeground(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'call') {
      _emitIncoming(Map<String, dynamic>.from(data));
      return;
    }
    final n = message.notification;
    final title = n?.title ?? 'New message';
    final body = n?.body ?? '';
    final conversationId = data['conversationId'] as String?;
    try {
      _local.show(
        id: _notificationId(data['messageId'] ?? conversationId ?? title),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'chat_messages',
            'Chat messages',
            icon: '@drawable/ic_stat_volt',
            color: Color(0xFFC6FF4A),
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: conversationId,
      );
    } catch (e) {
      debugPrint('foreground notification failed: $e');
    }
    // Persist into local history so the message survives an app restart.
    // onPersistMessage (set by AppState) upserts to the store AND updates the
    // live in-memory list + notifies listeners.
    if (data['messageId'] != null && onPersistMessage != null) {
      try {
        onPersistMessage!(ChatMessage.fromFcmData(Map<String, dynamic>.from(data)));
      } catch (e) {
        debugPrint('FCM foreground persist failed: $e');
      }
    }
  }
}