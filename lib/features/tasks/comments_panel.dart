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

    return Column(children: [
      Expanded(
        child: list == null
            ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 2, height: 70))
            : roots.isEmpty
                ? const Center(
                    child: EmptyState(icon: Icons.mode_comment_outlined, title: 'No comments yet', message: 'Start the conversation below.'),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    children: [for (final c in roots) ..._thread(c, byParent, 0)],
                  ),
      ),
      if (widget.canComment) _composer() else _readOnlyNote(),
    ]);
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: depth == 0 ? TF.surface : TF.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TF.line),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(c.authorName, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(displayName(c.authorName),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              ),
              const SizedBox(width: 8),
              Text(timeAgo(c.createdAt), style: const TextStyle(fontSize: 11.5, color: TF.muted)),
              if (c.edited) const Text('  · edited', style: TextStyle(fontSize: 11.5, color: TF.muted, fontStyle: FontStyle.italic)),
            ]),
            const SizedBox(height: 4),
            if (editing) ...[
              TextField(key: const Key('edit-comment-field'), controller: editCtrl, minLines: 2, maxLines: 5, autofocus: true),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton(onPressed: () => _saveEdit(c.id), child: const Text('Save')),
                const SizedBox(width: 8),
                TextButton(onPressed: () => setState(() => editingId = null), child: const Text('Cancel')),
              ]),
            ] else
              SelectableText(c.content, style: const TextStyle(fontSize: 14, color: TF.ink, height: 1.4)),
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
                        color: r.mine ? TF.primarySoft : TF.paper,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: r.mine ? TF.primary.withValues(alpha: 0.3) : TF.line),
                      ),
                      child: Text('${r.emoji} ${r.count}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (!readOnly) ...[
                  PopupMenuButton<String>(
                    key: ValueKey('react-${c.id}'),
                    tooltip: 'React',
                    icon: const Icon(Icons.add_reaction_outlined, size: 18, color: TF.muted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (e) => _react(c.id, e),
                    itemBuilder: (_) => [
                      for (final e in quickEmojis) PopupMenuItem(value: e, height: 40, child: Text(e, style: const TextStyle(fontSize: 20))),
                    ],
                  ),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => setState(() {
                      replyTo = c;
                      editingId = null;
                    }),
                    child: const Text('Reply'),
                  ),
                  if (c.authorId == meId)
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 8)),
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

  Widget _composer() => Container(
        decoration: const BoxDecoration(color: TF.surface, border: Border(top: BorderSide(color: TF.line))),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (replyTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(color: TF.primarySoft, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.reply_rounded, size: 16, color: TF.primaryDeep),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Replying to ${displayName(replyTo!.authorName)}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: TF.primaryDeep)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => replyTo = null),
                  ),
                ]),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  key: const Key('comment-input'),
                  controller: input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(hintText: 'Write a comment…'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const Key('comment-send'),
                style: IconButton.styleFrom(backgroundColor: TF.primary, minimumSize: const Size(46, 46)),
                onPressed: busy || input.text.trim().isEmpty ? null : _send,
                icon: const Icon(Icons.send_rounded, size: 20),
              ),
            ]),
          ]),
        ),
      );

  Widget _readOnlyNote() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: TF.sunken,
        child: const Text('You are watching this task — comments are read-only.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: TF.muted)),
      );
}
