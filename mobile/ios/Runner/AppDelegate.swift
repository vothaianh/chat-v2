import Flutter
import UIKit
import UserNotifications
import PushKit
import AVFAudio
import CallKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate, CXProviderDelegate {
  private var fallbackProvider: CXProvider?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let config = CXProviderConfiguration(localizedName: "Volt")
    config.supportsVideo = true
    config.maximumCallGroups = 1
    config.maximumCallsPerCallGroup = 1
    config.supportedHandleTypes = [.generic]
    if let icon = UIImage(named: "CallKitLogo") {
      config.iconTemplateImageData = icon.pngData()
    }
    let provider = CXProvider(configuration: config)
    provider.setDelegate(self, queue: nil)
    fallbackProvider = provider

    let voipRegistry = PKPushRegistry(queue: .main)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [.voIP]

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    UserDefaults.standard.set(token, forKey: "volt_voip_token")
    UserDefaults.standard.set(token, forKey: "flutter.volt_voip_token")
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    UserDefaults.standard.removeObject(forKey: "volt_voip_token")
    UserDefaults.standard.removeObject(forKey: "flutter.volt_voip_token")
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    let d = payload.dictionaryPayload
    func str(_ key: String) -> String? {
      if let s = d[key] as? String, !s.isEmpty { return s }
      if let inner = d["data"] as? [String: Any], let s = inner[key] as? String, !s.isEmpty { return s }
      return nil
    }
    let rawId = str("callId")
    let callId = (rawId.flatMap { UUID(uuidString: $0) } != nil) ? rawId! : UUID().uuidString
    let name = str("fromFullName") ?? str("fromUsername") ?? "Incoming call"
    let handle = str("fromUsername") ?? "volt"
    let video = str("media") == "video"

    persistPendingCall(
      callId: callId,
      conversationId: str("conversationId") ?? "",
      media: video ? "video" : "audio",
      fromUserId: str("fromUserId") ?? "",
      fromUsername: str("fromUsername") ?? "",
      fromFullName: name
    )

    var info: [String: Any] = [:]
    info["id"] = callId
    info["nameCaller"] = name
    info["handle"] = handle
    info["appName"] = "Volt"
    info["type"] = video ? 1 : 0
    info["duration"] = 45000
    info["extra"] = d
    info["iconName"] = "CallKitLogo"
    let data = flutter_callkit_incoming.Data(args: info)

    // Prefer the plugin so Flutter gets accept/decline events. When the app
    // was killed, the plugin is often still nil — report CallKit ourselves
    // or iOS only shows a normal notification banner (or kills us).
    if let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
      plugin.showCallkitIncoming(data, fromPushKit: true, completion: completion)
      return
    }

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: handle)
    update.localizedCallerName = name
    update.hasVideo = video
    update.supportsDTMF = false
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    fallbackProvider?.reportNewIncomingCall(with: UUID(uuidString: callId) ?? UUID(), update: update) { _ in
      completion()
    }
  }

  private func persistPendingCall(
    callId: String,
    conversationId: String,
    media: String,
    fromUserId: String,
    fromUsername: String,
    fromFullName: String
  ) {
    let pending: [String: Any] = [
      "callId": callId,
      "conversationId": conversationId,
      "media": media,
      "fromUserId": fromUserId,
      "fromUsername": fromUsername,
      "fromFullName": fromFullName,
      "_savedAt": Int(Date().timeIntervalSince1970 * 1000),
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: pending),
          let json = String(data: data, encoding: .utf8) else { return }
    UserDefaults.standard.set(json, forKey: "volt_pending_incoming_call")
    UserDefaults.standard.set(json, forKey: "flutter.volt_pending_incoming_call")
  }

  func providerDidReset(_ provider: CXProvider) {}

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    UserDefaults.standard.set("accept", forKey: "volt_callkit_action")
    UserDefaults.standard.set("accept", forKey: "flutter.volt_callkit_action")
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    UserDefaults.standard.set("decline", forKey: "volt_callkit_action")
    UserDefaults.standard.set("decline", forKey: "flutter.volt_callkit_action")
    action.fulfill()
  }
}
