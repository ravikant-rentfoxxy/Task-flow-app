import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

const quickEmojis = ['👍', '❤️', '😂', '🎉'];

/// Threaded task comments with reactions, replies and editing.
class CommentsPanel extends StatefulWidget {
  const CommentsPanel({super.key, required this.taskId, this.onChanged, this.canComment = true});

  final int taskId;
  final VoidCallback? onChanged;
  final bool canComment;

  @override
  State<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends State<CommentsPanel> {
  List<Comment>? comments;
  final input = TextEditingController();
  final editCtrl = TextEditingController();
  Comment? replyTo;
  int? editingId;
  bool busy = false;

  TaskFlowApi get api => Get.find<TaskFlowApi>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CommentsPanel old) {
    super.didUpdateWidget(old);
    if (old.taskId != widget.taskId) _load();
  }

  Future<void> _load() async {
    try {
      final c = await api.comments(widget.taskId);
      if (mounted) setState(() => comments = c);
    } catch (e) {
      if (mounted) setState(() => comments = const []);
      toastError(e);
    }
  }

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    setState(() => busy = true);
    try {
      await api.addComment(widget.taskId, text, parentId: replyTo?.id);
      toast(replyTo != null ? 'Reply posted' : 'Comment posted');
      input.clear();
      replyTo = null;
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      toastError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveEdit(int id) async {
    final text = editCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await api.editComment(widget.taskId, id, text);
      toast('Comment updated');
      setState(() => editingId = null);
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      toastError(e);
    }
  }

  Future<void> _react(int id, String emoji) async {
    try {
      await api.toggleCommentReaction(widget.taskId, id, emoji);
      await _load();
    } catch (e) {
      toastError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = comments;
    final byParent = <int?, List<Comment>>{};
    for (final c in list ?? const <Comment>[]) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    final roots = byParent[null] ?? const [];

    return ColoredBox(
      color: Brand.surface,
      child: Column(children: [
        Expanded(
          child: list == null
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 2, height: 70))
              : roots.isEmpty
                  ? const Center(
                      child: EmptyState(
                        icon: Icons.mode_comment_outlined,
                        color: Brand.navy,
                        title: 'No comments yet',
                        message: 'Start the conversation below.',
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      children: [for (final c in roots) ..._thread(c, byParent, 0)],
                    ),
        ),
        if (widget.canComment) _composer() else _readOnlyNote(),
      ]),
    );
  }

  List<Widget> _thread(Comment c, Map<int?, List<Comment>> byParent, int depth) => [
        _item(c, depth),
        for (final r in byParent[c.id] ?? const <Comment>[]) ..._thread(r, byParent, depth + 1),
      ];

  Widget _item(Comment c, int depth) {
    final meId = Get.find<AuthController>().me?.id;
    final editing = editingId == c.id;
    final readOnly = !widget.canComment;
    return Container(
      key: ValueKey('comment-${c.id}'),
      margin: EdgeInsets.only(left: (depth.clamp(0, 4)) * 18.0, bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: depth == 0 ? Colors.white : Brand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.outline),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(c.authorName, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(displayName(c.authorName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Brand.navy)),
              ),
              const SizedBox(width: 8),
              Text(timeAgo(c.createdAt), style: const TextStyle(fontSize: 11, color: Brand.onVariant)),
              if (c.edited) const Text(' · edited', style: TextStyle(fontSize: 11, color: Brand.onVariant, fontStyle: FontStyle.italic)),
            ]),
            const SizedBox(height: 4),
            if (editing) ...[
              TextField(key: const Key('edit-comment-field'), controller: editCtrl, minLines: 2, maxLines: 5, autofocus: true),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Brand.navy, foregroundColor: Brand.lime, minimumSize: const Size(0, 40)),
                  onPressed: () => _saveEdit(c.id),
                  child: const Text('Save'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Brand.onVariant),
                  onPressed: () => setState(() => editingId = null),
                  child: const Text('Cancel'),
                ),
              ]),
            ] else
              SelectableText(c.content, style: const TextStyle(fontSize: 13, color: Brand.navy, height: 1.45)),
            if (!editing) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final r in c.reactions)
                  InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: readOnly ? null : () => _react(c.id, r.emoji),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: r.mine ? Brand.limeLight : Brand.surfaceLow,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: r.mine ? Brand.limeDim : Brand.outline),
                      ),
                      child: Text('${r.emoji} ${r.count}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Brand.navy)),
                    ),
                  ),
                if (!readOnly) ...[
                  PopupMenuButton<String>(
                    key: ValueKey('react-${c.id}'),
                    tooltip: 'React',
                    icon: const Icon(Icons.add_reaction_outlined, size: 18, color: Brand.onVariant),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (e) => _react(c.id, e),
                    itemBuilder: (_) => [
                      for (final e in quickEmojis) PopupMenuItem(value: e, height: 40, child: Text(e, style: const TextStyle(fontSize: 18))),
                    ],
                  ),
                  TextButton(
                    style: _linkStyle,
                    onPressed: () => setState(() {
                      replyTo = c;
                      editingId = null;
                    }),
                    child: const Text('Reply'),
                  ),
                  if (c.authorId == meId)
                    TextButton(
                      style: _linkStyle,
                      onPressed: () => setState(() {
                        editingId = c.id;
                        editCtrl.text = c.content;
                        replyTo = null;
                      }),
                      child: const Text('Edit'),
                    ),
                ],
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  static final _linkStyle = TextButton.styleFrom(
    foregroundColor: Brand.navy,
    minimumSize: const Size(0, 30),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
  );

  Widget _composer() => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Brand.outline))),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (replyTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(
                  color: Brand.limeLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Brand.limeDim.withValues(alpha: 0.6)),
                ),
                child: Row(children: [
                  const Icon(Icons.reply_rounded, size: 16, color: Brand.navy),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Replying to ${displayName(replyTo!.authorName)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.navy)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18, color: Brand.navy),
                    onPressed: () => setState(() => replyTo = null),
                  ),
                ]),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              decoration: BoxDecoration(
                color: Brand.surfaceLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Brand.outline),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: TextField(
                    key: const Key('comment-input'),
                    controller: input,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(fontSize: 13, color: Brand.navy),
                    decoration: const InputDecoration(
                      hintText: 'Write a response or question…',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  key: const Key('comment-send'),
                  tooltip: 'Send',
                  style: IconButton.styleFrom(
                    backgroundColor: Brand.navy,
                    foregroundColor: Brand.lime,
                    disabledBackgroundColor: Brand.surfaceMid,
                    disabledForegroundColor: Brand.onVariant,
                    fixedSize: const Size(42, 42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                  onPressed: busy || input.text.trim().isEmpty ? null : _send,
                  icon: const Icon(Icons.send_rounded, size: 19),
                ),
              ]),
            ),
          ]),
        ),
      );

  Widget _readOnlyNote() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: Brand.surfaceLow,
        child: const Text('You are watching this task — comments are read-only.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Brand.onVariant)),
      );
}
