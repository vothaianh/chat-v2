import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Own the notification-center delegate before Firebase configures itself.
    // Otherwise firebase_messaging installs its own and swallows taps on
    // notifications posted by flutter_local_notifications, so the foreground
    // banner is never routed to onDidReceiveNotificationResponse. FlutterAppDelegate
    // conforms via FlutterAppLifeCycleProvider and fans events out to every
    // registered plugin, so FCM taps keep working too.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
