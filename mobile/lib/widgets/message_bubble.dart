import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final String? senderLabel;
  final bool showSender;
  final VoidCallback? onCallTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderLabel,
    this.showSender = false,
    this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    if (message.type == MessageType.call) {
      return _CallHistoryChip(message: message, onTap: onCallTap);
    }
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
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
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
        _body(context, onPrimary),
        _meta(),
      ],
    );
  }

  Widget _body(BuildContext context, Color onPrimary) {
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
      case MessageType.image:
        final url = message.media ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: url.isEmpty ? null : () => _openFull(context, url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 220,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 220,
                    height: 160,
                    color: AppTheme.surfaceHigh,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 220,
                    height: 120,
                    color: AppTheme.surfaceHigh,
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image_outlined, color: onPrimary.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ),
            if (message.caption != null && message.caption!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
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
      case MessageType.call:
        return const SizedBox.shrink();
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

  void _openFull(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (_, __, ___) => _ImageLightbox(url: url),
      ),
    );
  }

  String _time(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _CallHistoryChip extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onTap;
  const _CallHistoryChip({required this.message, this.onTap});

  @override
  Widget build(BuildContext context) {
    final reason = message.caption ?? '';
    final video = message.media == 'video';
    final missed = reason == 'timeout' || reason == 'busy';
    final failed = missed || reason == 'rejected' || reason == 'cancelled' || reason == 'disconnect';
    final icon = switch (reason) {
      'timeout' => Icons.call_missed_outgoing_rounded,
      'rejected' || 'cancelled' => Icons.call_end_rounded,
      'disconnect' => Icons.phone_disabled_rounded,
      _ => video ? Icons.videocam_rounded : Icons.call_rounded,
    };
    final color = missed ? AppTheme.danger : (failed ? AppTheme.textSecondary : AppTheme.primary);
    final label = (message.text != null && message.text!.isNotEmpty)
        ? message.text!
        : (video ? 'Video call' : 'Voice call');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Material(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: AppTheme.body(size: 12.5, weight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageLightbox extends StatelessWidget {
  final String url;
  const _ImageLightbox({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
