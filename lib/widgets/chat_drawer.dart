import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/chat_controller.dart';
import '../controllers/home_controller.dart';
import '../models/chat_session.dart';
import 'tonal_button.dart';
import '../core/haptics.dart';

/// Two-bar "sidebar" glyph — the long bar over a short one reads as a list
/// rather than the generic hamburger.
class SidebarGlyph extends StatelessWidget {
  final Color color;
  const SidebarGlyph({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    Widget bar(double w) => Container(
          width: w,
          height: 2,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(1)),
        );
    return SizedBox(
      width: 22,
      height: 22,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bar(18), const SizedBox(height: 5), bar(11)],
      ),
    );
  }
}

/// Conversation sidebar: search, new chat, and history grouped by date.
class ChatDrawer extends StatefulWidget {
  const ChatDrawer({super.key});

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ChatController get _chat => Get.find<ChatController>();

  void _close() => Get.find<HomeController>().closeSidebar();

  void _newChat() {
    Haptics.selectionClick();
    // Reuse the current blank chat instead of piling up empty sessions.
    if (_chat.messages.isNotEmpty || _chat.currentSessionId.value.isEmpty) {
      _chat.createNewChat();
    }
    Get.find<HomeController>().changeTab(0);
    _close();
  }

  void _open(ChatSession s) {
    Haptics.selectionClick();
    if (_chat.currentSessionId.value != s.id) _chat.openChat(s.id);
    Get.find<HomeController>().changeTab(0);
    _close();
  }

  /// Long-press menu: rename, pin/unpin, delete.
  void _showSessionMenu(BuildContext context, ChatSession s) {
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
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, s);
              },
            ),
            ListTile(
              leading: Icon(s.pinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded),
              title: Text(s.pinned ? 'Unpin chat' : 'Pin chat'),
              onTap: () {
                Navigator.pop(ctx);
                _chat.togglePinChat(s.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete chat',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, s);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, ChatSession s) async {
    final textController = TextEditingController(text: s.title);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Chat name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, textController.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (saved != null) _chat.renameChat(s.id, saved);
  }

  Future<void> _confirmDelete(BuildContext context, ChatSession s) async {
    Haptics.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 4),
              Text('This conversation will be permanently deleted.',
                  style: GoogleFonts.inter(
                      fontSize: 13.5, color: Theme.of(ctx).hintColor)),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(
                  child: TonalButton.neutral(ctx,
                      label: 'Cancel', onTap: () => Navigator.pop(ctx, false)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TonalButton.destructive(ctx,
                      label: 'Delete', onTap: () => Navigator.pop(ctx, true)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (ok == true) _chat.deleteChat(s.id);
  }

  /// Buckets sessions (already sorted newest first) into date sections.
  List<(String, List<ChatSession>)> _group(List<ChatSession> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String bucket(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      final diff = today.difference(day).inDays;
      if (diff <= 0) return 'Today';
      if (diff == 1) return 'Yesterday';
      if (diff < 7) return 'Previous 7 days';
      if (diff < 30) return 'Previous 30 days';
      return 'Older';
    }

    final out = <(String, List<ChatSession>)>[];
    for (final s in list) {
      final b = bucket(s.updatedAt);
      if (out.isEmpty || out.last.$1 != b) out.add((b, []));
      out.last.$2.add(s);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : const Color(0xFF0B0B0C);
    final muted = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);
    final accent = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
    final bg = isDark ? const Color(0xFF0E0E10) : const Color(0xFFF7F7F8);
    final field = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.05);
    final selected = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    final width = (MediaQuery.of(context).size.width * 0.84).clamp(0.0, 340.0);

    return Drawer(
      width: width,
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
            child: Row(children: [
              Expanded(
                child: Text('Chats',
                    style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        color: text)),
              ),
              IconButton(
                tooltip: 'New chat',
                onPressed: _newChat,
                icon: Icon(Icons.edit_square, size: 21, color: accent),
              ),
            ]),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                  color: field, borderRadius: BorderRadius.circular(10)),
              child: TextField(
                controller: _search,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                style: GoogleFonts.inter(fontSize: 15, color: text),
                cursorColor: accent,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: GoogleFonts.inter(fontSize: 15, color: muted),
                  prefixIcon:
                      Icon(Icons.search_rounded, size: 19, color: muted),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 36, minHeight: 38),
                  suffixIcon: _query.isEmpty
                      ? null
                      : GestureDetector(
                          onTap: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          child: Icon(Icons.cancel_rounded,
                              size: 17, color: muted),
                        ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          // List
          Expanded(child: Obx(() {
            final current = _chat.currentSessionId.value;
            // Hide blank "New Chat" shells, except the one that's open.
            final all = _chat.sessions
                .where((s) =>
                    (s.lastMessage ?? '').trim().isNotEmpty || s.id == current)
                .where((s) =>
                    _query.isEmpty ||
                    s.title.toLowerCase().contains(_query) ||
                    (s.lastMessage ?? '').toLowerCase().contains(_query))
                .toList();

            if (all.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                child: Column(children: [
                  Icon(
                      _query.isEmpty
                          ? Icons.chat_bubble_outline_rounded
                          : Icons.search_off_rounded,
                      size: 28,
                      color: muted.withValues(alpha: 0.6)),
                  const SizedBox(height: 12),
                  Text(_query.isEmpty ? 'No conversations yet' : 'No matches',
                      style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: text)),
                  const SizedBox(height: 4),
                  Text(
                      _query.isEmpty
                          ? 'Your chats will show up here.'
                          : 'Try a different word.',
                      style: GoogleFonts.inter(fontSize: 13, color: muted)),
                ]),
              );
            }

            final pinned = all.where((s) => s.pinned).toList();
            final groups = _group(all.where((s) => !s.pinned).toList());
            return ListView(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
              children: [
                if (pinned.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                    child: Row(children: [
                      Icon(Icons.push_pin_rounded, size: 13, color: muted),
                      const SizedBox(width: 4),
                      Text('Pinned',
                          style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: muted)),
                    ]),
                  ),
                  for (final s in pinned)
                    _SessionRow(
                      session: s,
                      active: s.id == current,
                      text: text,
                      selected: selected,
                      onTap: () => _open(s),
                      onLongPress: () => _showSessionMenu(context, s),
                    ),
                ],
                for (final g in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                    child: Text(g.$1,
                        style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: muted)),
                  ),
                  for (final s in g.$2)
                    _SessionRow(
                      session: s,
                      active: s.id == current,
                      text: text,
                      selected: selected,
                      onTap: () => _open(s),
                      onLongPress: () => _showSessionMenu(context, s),
                    ),
                ],
              ],
            );
          })),
          // Footer hint
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text('Long-press a chat to rename, pin, or delete it',
                style: GoogleFonts.inter(
                    fontSize: 12, color: muted.withValues(alpha: 0.8))),
          ),
        ]),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final ChatSession session;
  final bool active;
  final Color text;
  final Color selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SessionRow({
    required this.session,
    required this.active,
    required this.text,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: active ? selected : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          splashFactory: NoSplash.splashFactory,
          highlightColor: selected,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(children: [
              Expanded(
                child: Text(session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        letterSpacing: -0.15,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w400,
                        color: text)),
              ),
              if (session.pinned)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.push_pin_rounded,
                      size: 13, color: text.withValues(alpha: 0.5)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
