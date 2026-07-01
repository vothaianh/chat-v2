import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/app_state.dart';
import 'screens/auth_screen.dart';
import 'screens/root_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  runApp(ChatApp(appState: appState));
}

class ChatApp extends StatefulWidget {
  final AppState appState;
  const ChatApp({super.key, required this.appState});

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  @override
  void initState() {
    super.initState();
    widget.appState.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.appState,
      child: MaterialApp(
        title: 'Chat',
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