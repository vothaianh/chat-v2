import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/config.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final String? senderLabel;
  final bool showSender;
  final VoidCallback? onCallTap;
  final String? currentUserId;
  final ValueChanged<String>? onReact;
  final VoidCallback? onReply;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderLabel,
    this.showSender = false,
    this.onCallTap,
    this.currentUserId,
    this.onReact,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    if (message.type == MessageType.call) {
      return _CallHistoryChip(message: message, onTap: onCallTap);
    }
    final mine = isMine;
    final naked = message.type == MessageType.sticker ||
        message.type == MessageType.image ||
        message.type == MessageType.gif;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        child: Padding(
          padding: EdgeInsets.only(
            top: showSender ? 10 : 3,
            bottom: message.reactions.isEmpty ? 3 : 20,
            left: mine ? 48 : 14,
            right: mine ? 14 : 48,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onLongPress: (onReact == null && onReply == null) ? null : () => _openReactTray(context),
                child: Container(
                  padding: naked ? EdgeInsets.zero : const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  decoration: naked
                      ? null
                      : BoxDecoration(
                          color: mine ? AppTheme.bubbleMine : AppTheme.bubbleTheirs,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(22),
                            topRight: const Radius.circular(22),
                            bottomLeft: Radius.circular(mine ? 22 : 6),
                            bottomRight: Radius.circular(mine ? 6 : 22),
                          ),
                          border: mine ? null : Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                  child: _content(context, naked: naked),
                ),
              ),
              if (message.reactions.isNotEmpty)
                Positioned(
                  left: mine ? 2 : null,
                  right: mine ? null : 2,
                  bottom: -16,
                  child: _reactionChips(context),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, {required bool naked}) {
    final onPrimary = naked
        ? AppTheme.textPrimary
        : (isMine ? AppTheme.textOnLime : AppTheme.textPrimary);
    return Column(
      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showSender && !isMine && senderLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              senderLabel!,
              style: AppTheme.body(size: 12, weight: FontWeight.w800, color: AppTheme.accent),
            ),
          ),
        if (message.replyTo != null) _quote(onPrimary),
        _body(context, onPrimary),
        _meta(naked: naked),
      ],
    );
  }

  Widget _body(BuildContext context, Color onPrimary) {
    switch (message.type) {
      case MessageType.sticker:
        final media = message.media ?? '';
        final isAsset = media.startsWith('assets/');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAsset)
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(media, width: 148, height: 148, fit: BoxFit.cover),
              )
            else
              Text(media, style: const TextStyle(fontSize: 44)),
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
                child: _ScaledNetworkImage(url: url, color: onPrimary),
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
              child: _ScaledNetworkImage(url: message.media ?? '', color: onPrimary),
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

  Widget _meta({bool naked = false}) {
    final time = _time(message.createdAt);
    final onSecondary = naked
        ? AppTheme.textFaint
        : (isMine ? AppTheme.primaryInk.withValues(alpha: 0.55) : AppTheme.textFaint);
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

  Widget _quote(Color onPrimary) {
    final q = message.replyTo!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: (isMine ? AppTheme.primaryInk : Colors.white).withValues(alpha: isMine ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: isMine ? AppTheme.primaryInk.withValues(alpha: 0.45) : AppTheme.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              size: 11.5,
              weight: FontWeight.w800,
              color: isMine ? AppTheme.primaryInk : AppTheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            q.preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(size: 12.5, color: onPrimary.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }

  void _openReactTray(BuildContext context) {
    HapticFeedback.mediumImpact();
    final mine = message.reactions
        .where((r) => r.userId == currentUserId)
        .map((r) => r.emoji)
        .toSet();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onReact != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A22),
                      borderRadius: BorderRadius.circular(48),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Row(
                      children: [
                        for (final r in Config.reactionStickers)
                          Expanded(
                            child: _stickerBtn(ctx, r.id, r.asset, selected: mine.contains(r.id)),
                          ),
                      ],
                    ),
                  ),
                if (onReply != null) ...[
                  const SizedBox(height: 10),
                  Material(
                    color: const Color(0xFF1A1A22),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        Navigator.pop(ctx);
                        onReply!();
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Row(
                          children: [
                            const Icon(Icons.reply_rounded, color: AppTheme.primary, size: 22),
                            const SizedBox(width: 12),
                            Text('reply', style: AppTheme.body(size: 16, weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stickerBtn(BuildContext ctx, String id, String asset, {required bool selected}) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        onReact?.call(id);
      },
      child: AnimatedScale(
        scale: selected ? 1.14 : 1,
        duration: const Duration(milliseconds: 140),
        child: AspectRatio(
          aspectRatio: 1,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.high),
          ),
        ),
      ),
    );
  }

  Widget _reactionChips(BuildContext context) {
    final counts = <String, List<MessageReaction>>{};
    for (final r in message.reactions) {
      counts.putIfAbsent(r.emoji, () => []).add(r);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final entry in counts.entries)
            if (Config.reactionAsset(entry.key) != null)
              GestureDetector(
                onTap: onReact == null ? null : () => onReact!(entry.key),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        Config.reactionAsset(entry.key)!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      if (entry.value.length > 1) ...[
                        const SizedBox(width: 3),
                        Text(
                          '${entry.value.length}',
                          style: AppTheme.body(size: 12, weight: FontWeight.w800),
                        ),
                      ],
                    ],
                  ),
              ),
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

class _ScaledNetworkImage extends StatefulWidget {
  final String url;
  final Color color;
  const _ScaledNetworkImage({required this.url, required this.color});

  @override
  State<_ScaledNetworkImage> createState() => _ScaledNetworkImageState();
}

class _ScaledNetworkImageState extends State<_ScaledNetworkImage> {
  Size? _px;
  ImageStream? _stream;
  late final ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _px = Size(info.image.width.toDouble(), info.image.height.toDouble()));
    });
    _resolve();
  }

  void _resolve() {
    if (widget.url.isEmpty) return;
    _stream = CachedNetworkImageProvider(widget.url).resolve(const ImageConfiguration());
    _stream!.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.62;
    if (_px == null) {
      return Container(
        width: maxW * 0.55,
        height: 120,
        color: AppTheme.surfaceHigh,
        alignment: Alignment.center,
        child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    var w = _px!.width * 0.10;
    var h = _px!.height * 0.10;
    if (w > maxW) {
      h *= maxW / w;
      w = maxW;
    }
    if (w < 72) {
      h *= 72 / w;
      w = 72;
    }
    return CachedNetworkImage(
      imageUrl: widget.url,
      width: w,
      height: h,
      fit: BoxFit.contain,
      errorWidget: (_, __, ___) => Container(
        width: w,
        height: h,
        color: AppTheme.surfaceHigh,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: widget.color.withValues(alpha: 0.6)),
      ),
    );
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
