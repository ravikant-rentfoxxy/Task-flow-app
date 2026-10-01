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
import '../../widgets/brand_ui.dart';
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
  static const palette = [TF.ink, TF.coral, TF.green, TF.sky, TF.violet, TF.amber];

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
    // Phones: icon-only send button so the board name keeps some room.
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: BrandTitle(
          child: InkWell(
            onTap: _rename,
            // One text run (name + pencil) so it ellipsizes instead of overflowing.
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: boardName),
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.edit_outlined, size: 16, color: TF.muted),
                  ),
                ),
              ]),
              key: const Key('board-name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
            padding: EdgeInsets.only(right: compact ? 8 : 12, left: 4),
            child: compact
                ? IconButton.filled(
                    key: const Key('board-send'),
                    tooltip: exporting ? 'Exporting…' : 'Send as task',
                    style: IconButton.styleFrom(backgroundColor: Brand.navy, foregroundColor: Brand.lime),
                    onPressed: exporting ? null : _sendAsTask,
                    icon: exporting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Brand.lime))
                        : const Icon(Icons.send_rounded, size: 19),
                  )
                : FilledButton.icon(
                    key: const Key('board-send'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Brand.lime,
                      foregroundColor: Brand.navy,
                      minimumSize: const Size(0, 38),
                      side: const BorderSide(color: Brand.navy, width: 1.5),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    onPressed: exporting ? null : _sendAsTask,
                    icon: const Icon(Icons.send_rounded, size: 17),
                    label: Text(exporting ? 'Exporting…' : 'Send as task'),
                  ),
          ),
        ],
      ),
      body: Column(children: [
        _statusStrip(),
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
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.outline),
              boxShadow: Brand.shadow,
            ),
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
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.outline)),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(children: [
                  for (final c in palette)
                    GestureDetector(
                      onTap: () => setState(() => (color = c, eraser = false)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 30,
                        height: 30,
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: !eraser && color == c ? Brand.navy : Colors.transparent, width: 2),
                        ),
                        child: Container(decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                      ),
                    ),
                  _divider(),
                  for (final w in [2.0, 4.0, 8.0])
                    _tool(
                      tooltip: 'Stroke ${w.toInt()}',
                      selected: width == w,
                      onPressed: () => setState(() => width = w),
                      icon: Container(width: 18, height: w, decoration: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(9))),
                    ),
                  _tool(
                    tooltip: 'Eraser',
                    selected: eraser,
                    onPressed: () => setState(() => eraser = !eraser),
                    icon: const Icon(Icons.auto_fix_normal_outlined, size: 20),
                  ),
                  _divider(),
                  _tool(key: const Key('board-undo'), tooltip: 'Undo', onPressed: strokes.isEmpty ? null : _undo, icon: const Icon(Icons.undo_rounded, size: 20)),
                  _tool(
                    tooltip: 'Redo',
                    onPressed: redo.isEmpty
                        ? null
                        : () => setState(() {
                              strokes.add(redo.removeLast());
                              dirty = true;
                            }),
                    icon: const Icon(Icons.redo_rounded, size: 20),
                  ),
                  _tool(
                    key: const Key('board-clear'),
                    tooltip: 'Clear',
                    danger: true,
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
                    icon: const Icon(Icons.layers_clear_outlined, size: 20),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// Slim line above the canvas: save state tag and stroke count.
  Widget _statusStrip() {
    final label = saving
        ? 'Saving…'
        : boardId == null || fromWeb
            ? 'Not saved yet'
            : dirty
                ? 'Unsaved changes'
                : 'Saved';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Row(children: [
        Flexible(child: LimeTag(label)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${strokes.length} stroke${strokes.length == 1 ? '' : 's'}${eraser ? ' · eraser on' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Brand.onVariant),
          ),
        ),
      ]),
    );
  }

  Widget _divider() => Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 6), color: Brand.outline);

  Widget _tool({Key? key, required String tooltip, required Widget icon, required VoidCallback? onPressed, bool selected = false, bool danger = false}) => IconButton(
        key: key,
        tooltip: tooltip,
        isSelected: selected,
        style: IconButton.styleFrom(
          foregroundColor: danger ? brandRed : Brand.navy,
          backgroundColor: selected ? Brand.limeLight : null,
          side: selected ? const BorderSide(color: Brand.limeDim) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        icon: icon,
      );
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
          subtitle: boards == null ? null : '${boards!.length} saved board${boards!.length == 1 ? '' : 's'}',
          trailing: FilledButton.icon(
            key: const Key('board-new'),
            style: FilledButton.styleFrom(
              backgroundColor: Brand.lime,
              foregroundColor: Brand.navy,
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
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
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                      for (final b in boards!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: BrandCard(
                            key: ValueKey('board-${b.id}'),
                            onTap: () => Navigator.pop(context, b),
                            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                            child: Row(children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(color: Brand.limeLight, borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.gesture_rounded, size: 18, color: Brand.navy),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(
                                    b.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Brand.navy),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Updated ${timeAgo(b.updatedAt)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5, color: Brand.onVariant),
                                  ),
                                ]),
                              ),
                              IconButton(
                                tooltip: 'Delete board',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline_rounded, size: 19, color: brandRed),
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
                            ]),
                          ),
                        ),
                    ]),
        ),
      ]);
}
