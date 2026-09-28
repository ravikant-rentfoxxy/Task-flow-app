import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../tasks/composer_sheet.dart';
import '../shell/top_bar.dart';

class Stroke {
  Stroke({required this.color, required this.width, List<Offset>? points}) : points = points ?? [];
  final Color color;
  final double width;
  final List<Offset> points;

  Map<String, dynamic> toJson() => {
        'c': color.toARGB32(),
        'w': width,
        'p': [for (final p in points) [double.parse(p.dx.toStringAsFixed(1)), double.parse(p.dy.toStringAsFixed(1))]],
      };

  factory Stroke.fromJson(Map<String, dynamic> j) => Stroke(
        color: Color((j['c'] as num).toInt()),
        width: (j['w'] as num).toDouble(),
        points: [for (final p in (j['p'] as List)) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
      );
}

const sceneFormat = 'taskflow-flutter';

/// Board scene JSON written by this app.
Map<String, dynamic> encodeScene(List<Stroke> strokes) => {'format': sceneFormat, 'strokes': [for (final s in strokes) s.toJson()]};

/// Reads a saved scene. Web (Excalidraw) boards are converted best-effort from
/// their freehand/line elements and flagged so saving creates a copy.
({List<Stroke> strokes, bool fromWeb}) decodeScene(String? raw) {
  if (raw == null || raw.isEmpty) return (strokes: <Stroke>[], fromWeb: false);
  dynamic scene;
  try {
    scene = jsonDecode(raw);
  } catch (_) {
    return (strokes: <Stroke>[], fromWeb: false);
  }
  if (scene is Map && scene['format'] == sceneFormat) {
    return (strokes: [for (final s in (scene['strokes'] as List? ?? [])) Stroke.fromJson(Map<String, dynamic>.from(s as Map))], fromWeb: false);
  }
  final strokes = <Stroke>[];
  final elements = scene is Map ? scene['elements'] : null;
  if (elements is List) {
    for (final e in elements.whereType<Map>()) {
      if (e['isDeleted'] == true || e['points'] is! List) continue;
      final x = (e['x'] as num?)?.toDouble() ?? 0;
      final y = (e['y'] as num?)?.toDouble() ?? 0;
      strokes.add(Stroke(
        color: _hex(e['strokeColor']?.toString()) ?? TF.ink,
        width: ((e['strokeWidth'] as num?)?.toDouble() ?? 2) * 1.5,
        points: [for (final p in (e['points'] as List)) Offset(x + (p[0] as num).toDouble(), y + (p[1] as num).toDouble())],
      ));
    }
  }
  return (strokes: strokes, fromWeb: scene is Map && scene['format'] != sceneFormat);
}

Color? _hex(String? s) {
  if (s == null || !s.startsWith('#') || s.length != 7) return null;
  final v = int.tryParse(s.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

class ScribbleScreen extends StatefulWidget {
  const ScribbleScreen({super.key});

  @override
  State<ScribbleScreen> createState() => _ScribbleScreenState();
}

class _ScribbleScreenState extends State<ScribbleScreen> {
  static const palette = [TF.ink, TF.coral, TF.primary, TF.sky, TF.violet, TF.amber];

  final List<Stroke> strokes = [];
  final List<Stroke> redo = [];
  final boundary = GlobalKey();
  Color color = TF.ink;
  double width = 3;
  bool eraser = false;
  int? boardId;
  String boardName = 'Untitled board';
  bool fromWeb = false;
  bool dirty = false;
  bool saving = false;
  bool exporting = false;
  Timer? _autosave;

  TaskFlowApi get api => Get.find<TaskFlowApi>();

  @override
  void initState() {
    super.initState();
    _autosave = Timer.periodic(const Duration(seconds: 5), (_) {
      if (dirty && boardId != null && !fromWeb && !saving) _save(quiet: true);
    });
  }

  @override
  void dispose() {
    _autosave?.cancel();
    super.dispose();
  }

  Future<void> _save({bool quiet = false}) async {
    setState(() => saving = true);
    try {
      final isNew = boardId == null || fromWeb;
      final id = await api.saveBoard(id: isNew ? null : boardId, name: boardName, scene: encodeScene(strokes));
      setState(() {
        boardId = id;
        fromWeb = false;
        dirty = false;
      });
      if (!quiet) toast(isNew ? 'Board created' : 'Board saved');
    } catch (e) {
      if (!quiet) toastError(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _rename() async {
    final v = await promptText(context, title: 'Board name', initial: boardName, maxLines: 1, confirmLabel: 'Rename');
    if (v != null) setState(() => (boardName = v, dirty = true));
  }

  void _newBoard() => setState(() {
        strokes.clear();
        redo.clear();
        boardId = null;
        boardName = 'Untitled board';
        fromWeb = false;
        dirty = false;
      });

  Future<void> _openBoards() async {
    final picked = await showAppSheet<Board>(context, expand: true, builder: (_) => _BoardsSheet(onNew: _newBoard));
    if (picked == null) return;
    final scene = decodeScene(picked.scene);
    setState(() {
      strokes
        ..clear()
        ..addAll(scene.strokes);
      redo.clear();
      boardId = picked.id;
      boardName = picked.name;
      fromWeb = scene.fromWeb;
      dirty = false;
    });
  }

  Future<void> _sendAsTask() async {
    if (strokes.isEmpty) return toast('Draw something first 🙂');
    setState(() => exporting = true);
    try {
      final obj = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await obj.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final a = await api.upload(png!.buffer.asUint8List(), '${boardName.replaceAll(RegExp(r'[^\w\- ]'), '')}.png', mimeType: 'image/png');
      if (!mounted) return;
      setState(() => exporting = false);
      await showComposer(context, presetAttachmentIds: [a.id], presetBoardId: fromWeb ? null : boardId, presetTitle: boardName == 'Untitled board' ? '' : boardName);
    } catch (e) {
      toastError(e, 'Export failed');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  void _undo() {
    if (strokes.isEmpty) return;
    setState(() {
      redo.add(strokes.removeLast());
      dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BrandTitle(
          child: InkWell(
          onTap: _rename,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(boardName, key: const Key('board-name'), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            const Icon(Icons.edit_outlined, size: 16, color: TF.muted),
          ]),
          ),
        ),
        actions: [
          IconButton(key: const Key('boards-open'), tooltip: 'My boards', onPressed: _openBoards, icon: const Icon(Icons.folder_open_rounded)),
          IconButton(
            key: const Key('board-save'),
            tooltip: 'Save',
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(dirty ? Icons.save_rounded : Icons.cloud_done_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: FilledButton.icon(
              key: const Key('board-send'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
              onPressed: exporting ? null : _sendAsTask,
              icon: const Icon(Icons.send_rounded, size: 17),
              label: Text(exporting ? 'Exporting…' : 'Send as task'),
            ),
          ),
        ],
      ),
      body: Column(children: [
        if (fromWeb)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: InfoBanner(
              icon: Icons.info_outline_rounded,
              fg: Color(0xFF8A5A0B),
              bg: TF.amberSoft,
              text: 'This board was drawn on the web. Freehand strokes are shown; saving here creates a new copy.',
            ),
          ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(TF.radius), border: Border.all(color: TF.line)),
            clipBehavior: Clip.antiAlias,
            child: RepaintBoundary(
              key: boundary,
              child: GestureDetector(
                key: const Key('canvas'),
                onPanStart: (d) => setState(() {
                  redo.clear();
                  strokes.add(Stroke(color: eraser ? Colors.white : color, width: eraser ? width * 5 : width, points: [d.localPosition]));
                  dirty = true;
                }),
                onPanUpdate: (d) => setState(() => strokes.last.points.add(d.localPosition)),
                child: CustomPaint(painter: _BoardPainter(strokes), size: Size.infinite),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final c in palette)
                  GestureDetector(
                    onTap: () => setState(() => (color = c, eraser = false)),
                    child: Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: !eraser && color == c ? TF.ink : Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 3)],
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                for (final w in [2.0, 4.0, 8.0])
                  IconButton(
                    tooltip: 'Stroke ${w.toInt()}',
                    isSelected: width == w,
                    style: IconButton.styleFrom(backgroundColor: width == w ? TF.primarySoft : null),
                    onPressed: () => setState(() => width = w),
                    icon: Container(width: 18, height: w, decoration: BoxDecoration(color: TF.ink, borderRadius: BorderRadius.circular(9))),
                  ),
                IconButton(
                  tooltip: 'Eraser',
                  style: IconButton.styleFrom(backgroundColor: eraser ? TF.primarySoft : null),
                  onPressed: () => setState(() => eraser = !eraser),
                  icon: const Icon(Icons.auto_fix_normal_outlined),
                ),
                IconButton(key: const Key('board-undo'), tooltip: 'Undo', onPressed: strokes.isEmpty ? null : _undo, icon: const Icon(Icons.undo_rounded)),
                IconButton(
                  tooltip: 'Redo',
                  onPressed: redo.isEmpty
                      ? null
                      : () => setState(() {
                            strokes.add(redo.removeLast());
                            dirty = true;
                          }),
                  icon: const Icon(Icons.redo_rounded),
                ),
                IconButton(
                  key: const Key('board-clear'),
                  tooltip: 'Clear',
                  onPressed: strokes.isEmpty
                      ? null
                      : () async {
                          if (await confirmDialog(context, title: 'Clear board?', message: 'Remove every stroke on this board?', confirmLabel: 'Clear', destructive: true)) {
                            setState(() {
                              strokes.clear();
                              redo.clear();
                              dirty = true;
                            });
                          }
                        },
                  icon: const Icon(Icons.layers_clear_outlined),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.strokes);
  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final dot = Paint()..color = const Color(0xFFEDEBE5);
    for (double x = 12; x < size.width; x += 24) {
      for (double y = 12; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, s.width / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (var i = 1; i < s.points.length; i++) {
        final a = s.points[i - 1];
        final b = s.points[i];
        path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      }
      path.lineTo(s.points.last.dx, s.points.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}

class _BoardsSheet extends StatefulWidget {
  const _BoardsSheet({required this.onNew});
  final VoidCallback onNew;

  @override
  State<_BoardsSheet> createState() => _BoardsSheetState();
}

class _BoardsSheetState extends State<_BoardsSheet> {
  List<Board>? boards;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await Get.find<TaskFlowApi>().boards();
      if (mounted) setState(() => boards = b);
    } catch (e) {
      toastError(e);
      if (mounted) setState(() => boards = []);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SheetTitle(
          'My boards',
          trailing: FilledButton.icon(
            key: const Key('board-new'),
            onPressed: () {
              widget.onNew();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New board'),
          ),
        ),
        Expanded(
          child: boards == null
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(height: 56))
              : boards!.isEmpty
                  ? const EmptyState(icon: Icons.gesture_rounded, title: 'No saved boards yet')
                  : ListView(children: [
                      for (final b in boards!)
                        ListTile(
                          key: ValueKey('board-${b.id}'),
                          leading: const Icon(Icons.gesture_rounded, color: TF.violet),
                          title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Updated ${timeAgo(b.updatedAt)}'),
                          onTap: () => Navigator.pop(context, b),
                          trailing: IconButton(
                            tooltip: 'Delete board',
                            icon: const Icon(Icons.delete_outline_rounded, color: TF.coral),
                            onPressed: () async {
                              if (!await confirmDialog(context, title: 'Delete board?', message: 'Delete "${b.name}"?', confirmLabel: 'Delete', destructive: true)) return;
                              try {
                                if (!context.mounted) return;
                                await Get.find<TaskFlowApi>().deleteBoard(b.id);
                                toast('Board deleted');
                                _load();
                              } catch (e) {
                                toastError(e);
                              }
                            },
                          ),
                        ),
                    ]),
        ),
      ]);
}
