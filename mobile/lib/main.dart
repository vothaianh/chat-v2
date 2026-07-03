import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'services/config.dart';
import 'theme/app_theme.dart';
import 'services/app_state.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/root_shell.dart';

/// Shared bootstrap used by the flavor entrypoints (main_dev / main_prod).
/// Defaulting here to the flavor resolved from dart-defines keeps `main.dart`
/// runnable directly too.
void bootstrapApp([AppConfig? config]) {
  WidgetsFlutterBinding.ensureInitialized();
  Config.init(config ?? AppConfig.resolve());
  final appState = AppState();
  runApp(ChatApp(appState: appState));
}

void main() => bootstrapApp();

class ChatApp extends StatefulWidget {
  final AppState appState;
  const ChatApp({super.key, required this.appState});

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Wire notification taps → open the conversation. Lives in the UI layer so
    // it can import ChatScreen without a service/screen import cycle.
    widget.appState.push.onTapConversation = _openConversationFromNotification;
    widget.appState.bootstrap();
  }

  Future<void> _openConversationFromNotification(String conversationId) async {
    debugPrint('[notif-tap] open conversationId=$conversationId');
    final app = widget.appState;
    if (!app.isAuthenticated) {
      debugPrint('[notif-tap] ignored — not authenticated yet');
      return; // ignore taps before login
    }
    final conv = await app.resolveConversation(conversationId);
    debugPrint('[notif-tap] resolved conversation: ${conv != null}');
    if (conv == null) return;
    final nav = app.navigatorKey.currentState;
    debugPrint('[notif-tap] navigator state: ${nav != null}');
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
    nav.push(MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)));
    debugPrint('[notif-tap] pushed ChatScreen');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On resume, pull any messages the FCM background isolate persisted while
    // the app was backgrounded into the live in-memory list.
    if (state == AppLifecycleState.resumed) {
      widget.appState.refreshFromStore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.appState,
      child: MaterialApp(
        navigatorKey: widget.appState.navigatorKey,
        title: Config.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Consumer<AppState>(
          builder: (context, app, _) {
            if (!app.bootstrapped) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!app.isAuthenticated) return AuthScreen(app: app);
            return const RootShell();
          },
        ),
      ),
    );
  }
}
