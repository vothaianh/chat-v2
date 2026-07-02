import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

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

  /// Top-level handler for messages that arrive while the app is in the background
  /// or terminated. Must be a top-level function (not a closure or class method).
  @pragma('vm:entry-point')
  static Future<void> onBackgroundMessage(RemoteMessage message) async {
    // Lightweight handling — we only surface a notification when the OS shows it
    // automatically (data-only messages rely on the system tray). For visible
    // background notifications, the OS uses the FCM `notification` payload.
    debugPrint('FCM background: ${message.messageId} ${message.notification?.title}');
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Firebase Messaging only works on Android/iOS. Skip on other platforms.
    if (!Platform.isAndroid && !Platform.isIOS) return;

    await Firebase.initializeApp();

    // Local notifications for foreground FCM messages.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        debugPrint('Local notification tapped: ${resp.payload}');
      },
    );

    // Create an Android notification channel for chat messages.
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'chat_messages',
          'Chat messages',
          description: 'Incoming chat messages',
          importance: Importance.high,
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

    // Token refresh → re-register with the backend if we have a JWT.
    FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);
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

      // On iOS, getToken() requires an APNS token which the Simulator never
      // provides — guard so it doesn't throw and abort startup.
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _token = token;
        await _registerWithBackend(token);
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
        id: (conversationId ?? title).hashCode,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'chat_messages',
            'Chat messages',
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
    final n = message.notification;
    final title = n?.title ?? 'New message';
    final body = n?.body ?? '';
    final data = message.data;
    _local.show(
      id: data['messageId']?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'chat_messages',
          'Chat messages',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: data['conversationId'] as String?,
    );
  }
}