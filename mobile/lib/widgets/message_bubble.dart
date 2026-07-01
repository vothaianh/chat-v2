import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final String? senderLabel;
  final bool showSender;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderLabel,
    this.showSender = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMine ? AppTheme.bubbleMine : AppTheme.bubbleTheirs,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (showSender && !isMine && senderLabel != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              senderLabel!,
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          _body(context),
          _meta(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_body(context), _meta()],
    );
  }

  Widget _body(BuildContext context) {
    final onPrimary = isMine ? Colors.white : AppTheme.textPrimary;
    switch (message.type) {
      case MessageType.sticker:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.media ?? '', style: const TextStyle(fontSize: 40)),
            if (message.caption != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _markdown(message.caption!, onPrimary),
              ),
          ],
        );
      case MessageType.gif:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                message.media ?? '',
                width: 200,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 200, height: 140,
                  color: AppTheme.surfaceHigh,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, color: AppTheme.textSecondary),
                ),
              ),
            ),
            if (message.caption != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _markdown(message.caption!, onPrimary),
              ),
          ],
        );
      case MessageType.text:
        return _markdown(message.text ?? '', onPrimary);
    }
  }

  Widget _markdown(String text, Color color) {
    // Render mentions as bold colored spans via simple inline parsing.
    return MarkdownBody(
      data: text,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: color, fontSize: 15, height: 1.35),
        strong: TextStyle(
          color: isMine ? Colors.white : AppTheme.mention,
          fontWeight: FontWeight.w700,
        ),
      ),
      extensionSet: null,
    );
  }

  Widget _meta() {
    final time = _time(message.createdAt);
    final onSecondary = isMine ? Colors.white70 : AppTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(time, style: TextStyle(color: onSecondary, fontSize: 10.5)),
          if (isMine) ...[
            const SizedBox(width: 4),
            Icon(
              message.delivered ? Icons.done_all : Icons.access_time,
              size: 13,
              color: onSecondary,
            ),
          ],
        ],
      ),
    );
  }

  String _time(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
}