import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_message.dart';
import '../utils/thought_parser.dart';
import 'attachment_preview.dart';
import 'image_viewer.dart';
import 'thought_disclosure.dart';
import '../core/haptics.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  /// True when this is the last assistant message in the chat. Only then
  /// do the regenerate and read-aloud actions make sense.
  final bool isLastAssistant;

  /// True while this message is being read aloud.
  final bool isSpeaking;

  /// True while this message is the current search hit.
  final bool highlighted;

  final VoidCallback? onRegenerate;
  final VoidCallback? onToggleSpeech;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ChatBubble({
    super.key,
    required this.message,
    this.isLastAssistant = false,
    this.isSpeaking = false,
    this.highlighted = false,
    this.onRegenerate,
    this.onToggleSpeech,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Premium Generated Image Card (Assistant only)
    if (!isUser && message.decodedImageBytes != null) {
      return _buildGeneratedImageCard(context, isDark);
    }

    final visibleContent = message.fileName == null
        ? message.content
        : message.content.split('\n\nAttached file:').first;

    final Widget body;
    if (isUser) {
      body = _buildUser(context, isDark, visibleContent);
    } else {
      final thoughtParts =
          splitThoughtTags(_cleanAssistantText(visibleContent));
      final answerContent = thoughtParts.answer.trim();
      body = _buildAssistant(context, isDark, thoughtParts, answerContent);
    }

    if (!highlighted) return body;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: body,
    );
  }

  // ── User: compact neutral bubble on the right ──
  // Long-press opens Edit / Copy / Delete. Editing re-sends the message
  // and regenerates everything after it.
  Widget _buildUser(BuildContext context, bool isDark, String text) {
    final maxW = MediaQuery.of(context).size.width * 0.8;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(48, 14, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (message.decodedImageBytes != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onTap: () => ImageViewer.show(context, message.imageBase64!),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: maxW * 0.7, maxHeight: 260),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    message.decodedImageBytes!,
                    gaplessPlayback: true,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 160,
                      height: 120,
                      color: _userFill(isDark),
                      child: const Center(
                          child: Icon(Icons.broken_image_rounded, size: 24)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (message.fileName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: AttachmentPreview(
                fileName: message.fileName!,
                fileType: message.fileType,
                fileSize: message.fileSize,
                imageBase64: message.imageBase64,
                imagePath: message.imagePath,
                compact: true,
              ),
            ),
          ),
        if (text.trim().isNotEmpty)
          Container(
            constraints: BoxConstraints(maxWidth: maxW),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _userFill(isDark),
              borderRadius: BorderRadius.circular(20),
            ),
            child: SelectableText(
              text,
              style: GoogleFonts.inter(
                fontSize: 15.5,
                height: 1.45,
                letterSpacing: -0.1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
      ]),
    );
    return GestureDetector(
      onLongPress: () => _showUserMenu(context),
      child: content,
    );
  }

  void _showUserMenu(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit and resend'),
              onTap: () {
                Navigator.pop(ctx);
                onEdit?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_rounded),
              title: const Text('Copy text'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: message.visibleText));
                Haptics.lightImpact();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete message',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete?.call();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Assistant: full-width text, no bubble, quiet actions underneath ──
  Widget _buildAssistant(BuildContext context, bool isDark,
      ThoughtParts thoughtParts, String answerContent) {
    final muted = Theme.of(context).hintColor;
    final meta = <String>[
      if (message.tokensPerSec != null && message.tokensPerSec! > 0)
        '${message.tokensPerSec!.toStringAsFixed(1)} tok/s',
      if (message.imageGenDurationMs != null && message.imageGenDurationMs! > 0)
        _formatGenTime(message.imageGenDurationMs!),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (thoughtParts.hasThought)
          ThoughtDisclosure(
            thought: thoughtParts.thought,
            durationSeconds: message.thoughtDurationSeconds,
            styleSheet: _thoughtMarkdownStyle(context),
          ),
        if (answerContent.isNotEmpty)
          MarkdownBody(
            data: answerContent,
            selectable: true,
            styleSheet: answerStyle(context),
          ),
        if (message.fileName != null) ...[
          const SizedBox(height: 10),
          AttachmentPreview(
            fileName: message.fileName!,
            fileType: message.fileType,
            fileSize: message.fileSize,
            imageBase64: message.imageBase64,
            imagePath: message.imagePath,
            compact: true,
          ),
        ],
        const SizedBox(height: 4),
        // Nudge left so the copy glyph lines up with the text edge.
        Transform.translate(
            offset: const Offset(-6, 0),
            child: Row(children: [
              if (answerContent.isNotEmpty)
                _CopyButton(text: answerContent, color: muted),
              if (answerContent.isNotEmpty && isLastAssistant) ...[
                _ActionIcon(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Regenerate response',
                  color: muted,
                  onTap: onRegenerate,
                ),
                _ActionIcon(
                  icon: isSpeaking
                      ? Icons.stop_rounded
                      : Icons.volume_up_rounded,
                  tooltip: isSpeaking ? 'Stop reading' : 'Read aloud',
                  color: isSpeaking
                      ? Theme.of(context).colorScheme.primary
                      : muted,
                  onTap: onToggleSpeech,
                ),
              ],
              if (meta.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(meta.join(' · '),
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: muted.withValues(alpha: 0.8),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ])),
      ]),
    );
  }

  static Color _userFill(bool isDark) =>
      isDark ? const Color(0xFF1E1E21) : const Color(0xFFF0F0F2);

  /// Answer text style — shared with the streaming reply so text doesn't
  /// shift when generation finishes.
  static MarkdownStyleSheet answerStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).hintColor;
    final base = GoogleFonts.inter(
        fontSize: 15.5, color: color, height: 1.6, letterSpacing: -0.1);
    final codeBlockBg =
        isDark ? const Color(0xFF161618) : const Color(0xFFF3F3F5);

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      strong: base.copyWith(fontWeight: FontWeight.w600),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base,
      code: GoogleFonts.firaCode(
        fontSize: 13,
        color: color,
        backgroundColor: codeBlockBg,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBlockBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.06),
            width: 0.5),
      ),
      h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.w700, height: 1.3),
      h2: base.copyWith(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3),
      h3: base.copyWith(
          fontSize: 17, fontWeight: FontWeight.w600, height: 1.35),
      pPadding: const EdgeInsets.only(bottom: 2),
      codeblockPadding: const EdgeInsets.all(14),
      blockquote: base.copyWith(color: muted),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.15),
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
    );
  }

  MarkdownStyleSheet _thoughtMarkdownStyle(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    final base = GoogleFonts.inter(fontSize: 13, color: muted, height: 1.4);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      strong: base.copyWith(fontWeight: FontWeight.w600),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base,
      code: GoogleFonts.firaCode(
        fontSize: 11,
        color: muted,
        backgroundColor:
            isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
      ),
      codeblockDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  String _formatGenTime(int ms) {
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  String _cleanAssistantText(String text) {
    return text
        .replaceAll('<|endoftext|>', '')
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|end|>', '')
        .trim();
  }

  Widget _buildGeneratedImageCard(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => ImageViewer.show(context, message.imageBase64!),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Stack(
                children: [
                  Image.memory(
                    message.decodedImageBytes!,
                    width: double.infinity,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Container(
                      height: 150,
                      color: isDark
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFFF2F2F7),
                      child: const Center(
                          child: Icon(Icons.broken_image_rounded, size: 28)),
                    ),
                  ),
                  // Time elapsed overlay
                  if (message.imageGenDurationMs != null &&
                      message.imageGenDurationMs! > 0)
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined,
                                size: 10, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              _formatGenTime(message.imageGenDurationMs!),
                              style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
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

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: () {
          if (onTap != null) {
            Haptics.lightImpact();
            onTap!();
          }
        },
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String text;
  final Color color;
  const _CopyButton({required this.text, required this.color});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    Haptics.lightImpact();
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Copy',
      child: InkResponse(
        onTap: _copy,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              _copied ? Icons.check_rounded : Icons.content_copy_rounded,
              key: ValueKey(_copied),
              size: 16,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
