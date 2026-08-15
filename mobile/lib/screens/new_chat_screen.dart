import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../widgets/pulse.dart';
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
    for (final c in _memberCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureGroupControllers() {
    while (_memberCtrls.length < 2) {
      _memberCtrls.add(TextEditingController());
    }
  }

  Future<void> _start() async {
    final app = context.read<AppState>();
    if (!_groupMode) {
      final uname = _usernameCtrl.text.trim().toLowerCase();
      if (uname.isEmpty) return;
      final conv = await app.startPrivateWith(uname);
      if (conv != null && mounted) {
        Navigator.of(context).pushReplacement(pulseRoute(ChatScreen(conversation: conv)));
      }
    } else {
      _ensureGroupControllers();
      final members = _memberCtrls.map((c) => c.text.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
      if (members.isEmpty) return;
      final conv = await app.startGroup(_titleCtrl.text.trim(), members);
      if (conv != null && mounted) {
        Navigator.of(context).pushReplacement(pulseRoute(ChatScreen(conversation: conv)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PulseBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(_groupMode ? 'new group' : 'new dm')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.person_outline_rounded), label: Text('dm')),
                  ButtonSegment(value: true, icon: Icon(Icons.groups_2_outlined), label: Text('group')),
                ],
                selected: {_groupMode},
                onSelectionChanged: (s) => setState(() => _groupMode = s.first),
              ),
              const SizedBox(height: 28),
              if (_groupMode) ...[
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'group name', hintText: 'optional'),
                ),
                const SizedBox(height: 14),
              ] else
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'username',
                    hintText: 'vothaianh',
                    prefixText: '@',
                  ),
                ),
              const SizedBox(height: 14),
              if (_groupMode) ..._memberFields(),
              if (_groupMode)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _memberCtrls.add(TextEditingController())),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('add someone'),
                  ),
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _start,
                child: Text(_groupMode ? 'make the group' : 'slide in'),
              ),
              const SizedBox(height: 18),
              Text(
                'tag people anywhere — try “hey @vothaianh”',
                style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
                    labelText: 'member ${i + 1}',
                    prefixText: '@',
                  ),
                ),
              ),
              if (_memberCtrls.length > 2)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: AppTheme.danger),
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
