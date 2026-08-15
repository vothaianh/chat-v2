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
    final mine = isMine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        margin: EdgeInsets.only(
          top: showSender ? 10 : 3,
          bottom: 3,
          left: mine ? 48 : 14,
          right: mine ? 14 : 48,
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: mine ? AppTheme.bubbleMine : AppTheme.bubbleTheirs,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(mine ? 22 : 6),
            bottomRight: Radius.circular(mine ? 6 : 22),
          ),
          border: mine
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: _content(),
      ),
    );
  }

  Widget _content() {
    final onPrimary = isMine ? AppTheme.textOnLime : AppTheme.textPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSender && !isMine && senderLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              senderLabel!,
              style: AppTheme.body(size: 12, weight: FontWeight.w800, color: AppTheme.accent),
            ),
          ),
        _body(onPrimary),
        _meta(),
      ],
    );
  }

  Widget _body(Color onPrimary) {
    switch (message.type) {
      case MessageType.sticker:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.media ?? '', style: const TextStyle(fontSize: 44)),
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
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                message.media ?? '',
                width: 210,
                height: 148,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 210,
                  height: 148,
                  color: AppTheme.surfaceHigh,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, color: AppTheme.textSecondary),
                ),
              ),
            ),
            if (message.caption != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _markdown(message.caption!, onPrimary),
              ),
          ],
        );
      case MessageType.text:
        return _markdown(message.text ?? '', onPrimary);
    }
  }

  Widget _markdown(String text, Color color) {
    return MarkdownBody(
      data: text,
      styleSheet: MarkdownStyleSheet(
        p: AppTheme.body(size: 15.5, color: color, height: 1.38),
        strong: AppTheme.body(
          size: 15.5,
          weight: FontWeight.w800,
          color: isMine ? AppTheme.primaryInk : AppTheme.mention,
        ),
      ),
      extensionSet: null,
    );
  }

  Widget _meta() {
    final time = _time(message.createdAt);
    final onSecondary = isMine
        ? AppTheme.primaryInk.withValues(alpha: 0.55)
        : AppTheme.textFaint;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(time, style: AppTheme.body(size: 10.5, color: onSecondary, weight: FontWeight.w600)),
          if (isMine) ...[
            const SizedBox(width: 4),
            Icon(
              message.delivered ? Icons.done_all_rounded : Icons.schedule_rounded,
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
