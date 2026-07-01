import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  bool _groupMode = false;
  final _usernameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _memberCtrls = <TextEditingController>[];

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _titleCtrl.dispose();
    for (final c in _memberCtrls) c.dispose();
    super.dispose();
  }

  void _ensureGroupControllers() {
    if (_memberCtrls.length < 2) {
      while (_memberCtrls.length < 2) {
        _memberCtrls.add(TextEditingController());
      }
    }
  }

  Future<void> _start() async {
    final app = context.read<AppState>();
    if (!_groupMode) {
      final uname = _usernameCtrl.text.trim().toLowerCase();
      if (uname.isEmpty) return;
      final conv = await app.startPrivateWith(uname);
      if (conv != null && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)));
      }
    } else {
      _ensureGroupControllers();
      final members = _memberCtrls.map((c) => c.text.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
      if (members.isEmpty) return;
      final conv = await app.startGroup(_titleCtrl.text.trim(), members);
      if (conv != null && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.person), label: Text('Private')),
                ButtonSegment(value: true, icon: Icon(Icons.group), label: Text('Group')),
              ],
              selected: {_groupMode},
              onSelectionChanged: (s) => setState(() => _groupMode = s.first),
            ),
            const SizedBox(height: 24),
            if (_groupMode) ...[
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Group name (optional)'),
              ),
              const SizedBox(height: 16),
            ]
            else
              TextField(
                controller: _usernameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: '@vothaianh',
                  prefixText: '@',
                ),
              ),
            const SizedBox(height: 16),
            if (_groupMode) ..._memberFields(),
            if (_groupMode)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _memberCtrls.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add member'),
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _start,
              child: Text(_groupMode ? 'Create group' : 'Start chat'),
            ),
            const SizedBox(height: 16),
            Text(
              'Tag people by username anywhere in a message, e.g. "hey @vothaianh"',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _memberFields() {
    _ensureGroupControllers();
    return [
      for (int i = 0; i < _memberCtrls.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberCtrls[i],
                  decoration: InputDecoration(
                    labelText: 'Member ${i + 1} username',
                    prefixText: '@',
                  ),
                ),
              ),
              if (_memberCtrls.length > 2)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  onPressed: () => setState(() {
                    _memberCtrls[i].dispose();
                    _memberCtrls.removeAt(i);
                  }),
                ),
            ],
          ),
        ),
    ];
  }
}