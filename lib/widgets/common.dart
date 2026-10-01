import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/task_logic.dart';
import '../data/taskflow_api.dart';
import '../theme/app_theme.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// The round "Work+" brand mark.
/// Font for the "Work Plus" wordmark, matching the logo lettering.
const kBrandFont = 'Montserrat';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/logo/work_plus_logo.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    semanticLabel: 'Work Plus',
  );
}

void toast(String message) {
  messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
}

void toastError(Object error, [String fallback = 'Something went wrong']) {
  final msg = error is ApiException ? error.message : fallback;
  messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFFFB4A6), size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      duration: const Duration(seconds: 4),
    ));
}

String errorText(Object e, [String fallback = 'Something went wrong']) => e is ApiException ? e.message : fallback;

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 32, this.online = false, this.dark = false});

  final String? name;
  final double size;
  final bool online;
  final bool dark;

  static const _tints = [
    (Color(0xFFE3F1EC), Color(0xFF0A4F42)),
    (Color(0xFFFFEEE2), Color(0xFFB4471B)),
    (Color(0xFFE5F0FA), Color(0xFF1F5F94)),
    (Color(0xFFEEEBFB), Color(0xFF4F3FAE)),
    (Color(0xFFFBF1DD), Color(0xFF8A5A0B)),
    (Color(0xFFFDE8EE), Color(0xFF9F1239)),
  ];

  @override
  Widget build(BuildContext context) {
    final tint = _tints[(name ?? '').codeUnits.fold<int>(0, (a, b) => a + b) % _tints.length];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: dark ? TF.ink : tint.$1, shape: BoxShape.circle),
          child: Text(
            initials(name),
            style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: dark ? Colors.white : tint.$2),
          ),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: size * 0.32,
              height: size * 0.32,
              decoration: BoxDecoration(
                color: TF.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.fg = TF.inkSoft, this.bg = TF.sunken, this.icon, this.dot = false, this.onTap});

  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final bool dot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
        ),
      ]),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(99), onTap: onTap, child: child),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.onTap});
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = TF.status(status);
    return Pill(
      statusLabel(status),
      fg: c.fg,
      bg: c.bg,
      dot: true,
      onTap: onTap,
      key: ValueKey('status-$status'),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.icon, this.color = TF.primary, this.count, this.trailing});

  final String title;
  final IconData? icon;
  final Color color;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        if (icon != null) ...[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: TF.ink)),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(color: TF.primarySoft, borderRadius: BorderRadius.circular(99)),
            child: Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TF.primaryDeep)),
          ),
        ],
        const Spacer(),
        ?trailing,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.color = TF.primary});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: 4),
          Text(message!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ],
        if (action != null) ...[const SizedBox(height: 18), action!],
      ]),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          color: TF.coral,
          title: 'Could not load',
          message: message,
          action: onRetry == null ? null : OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ),
      );
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.height = 96});
  final int count;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(
          count,
          (i) => Container(
            height: height,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: TF.sunken, borderRadius: BorderRadius.circular(TF.radius)),
          ),
        ),
      );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text, this.title, this.fg = TF.primaryDeep, this.bg = TF.primarySoft, this.icon, this.child});

  final String? title;
  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(title!.toUpperCase(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: fg)),
                ),
              SelectableText(text, style: TextStyle(color: fg, fontSize: 12.5, height: 1.4)),
              if (child != null) ...[const SizedBox(height: 10), child!],
            ]),
          ),
        ]),
      );
}

/// Renders text containing `[label](href)` links and `@[Name](user:id)` mentions.
class RichBody extends StatelessWidget {
  const RichBody(this.text, {super.key, this.style, this.linkColor = TF.primary, this.onLink});

  final String text;
  final TextStyle? style;
  final Color linkColor;
  final void Function(String href)? onLink;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium!;
    final spans = <InlineSpan>[];
    for (final line in text.split('\n').asMap().entries) {
      if (line.key > 0) spans.add(const TextSpan(text: '\n'));
      final legacy = RegExp(r'^/tasks/(\d+)$').firstMatch(line.value.trim());
      if (legacy != null) {
        spans.add(_link('Tap to view', line.value.trim(), base));
        continue;
      }
      for (final p in parseRichText(line.value)) {
        spans.add(switch (p) {
          PlainPart(:final text) => TextSpan(text: text),
          LinkPart(:final label, :final href) => _link(label, href, base),
          MentionPart(:final name) => TextSpan(
              text: '@$name',
              style: TextStyle(fontWeight: FontWeight.w700, color: linkColor, backgroundColor: linkColor.withValues(alpha: 0.08)),
            ),
        });
      }
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }

  InlineSpan _link(String label, String href, TextStyle base) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: onLink == null ? null : () => onLink!(href),
          child: Text(label,
              style: base.copyWith(
                color: linkColor,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: linkColor.withValues(alpha: 0.5),
              )),
        ),
      );
}

/// Image served by `/api/uploads/:id` (needs the auth header).
class AuthImage extends StatelessWidget {
  const AuthImage({super.key, required this.attachmentId, this.fit = BoxFit.cover, this.height, this.width});

  final int attachmentId;
  final BoxFit fit;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final client = Get.find<TaskFlowApi>().client;
    return Image.network(
      client.uploadUrl(attachmentId),
      headers: client.authHeaders,
      fit: fit,
      height: height,
      width: width,
      errorBuilder: (_, _, _) => Container(
        height: height,
        width: width,
        color: TF.sunken,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: TF.faint),
      ),
    );
  }
}

// ---- Sheets & dialogs --------------------------------------------------------

Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder, bool expand = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: expand
          ? SizedBox(height: MediaQuery.of(ctx).size.height * 0.88, child: builder(ctx))
          : builder(ctx),
    ),
  );
}

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          ?trailing,
        ]),
      );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: TF.coral) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? message,
  String? hint,
  String initial = '',
  String confirmLabel = 'Submit',
  bool required = true,
  int minLength = 0,
  int maxLines = 4,
  bool obscure = false,
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final value = ctrl.text.trim();
      final valid = (!required || value.isNotEmpty) && value.length >= minLength;
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (message != null) ...[Text(message, style: Theme.of(ctx).textTheme.bodySmall), const SizedBox(height: 12)],
            TextField(
              key: const Key('prompt-field'),
              controller: ctrl,
              autofocus: true,
              obscureText: obscure,
              minLines: obscure ? 1 : (maxLines > 1 ? 3 : 1),
              maxLines: obscure ? 1 : maxLines,
              decoration: InputDecoration(hintText: hint),
              onChanged: (_) => setState(() {}),
            ),
            if (minLength > 0 && value.isNotEmpty && value.length < minLength)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('At least $minLength characters', style: const TextStyle(color: TF.coral, fontSize: 11.5)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            key: const Key('prompt-submit'),
            onPressed: valid ? () => Navigator.pop(ctx, value) : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    }),
  );
}

/// Date + time picker in one flow.
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial, DateTime? firstDate}) async {
  final now = DateTime.now();
  final init = initial ?? now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: init,
    firstDate: firstDate ?? DateTime(now.year - 1),
    lastDate: DateTime(now.year + 5),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(init));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Quick picks used for due dates and ETAs.
DateTime quickTime(String key, [DateTime? from]) {
  final n = from ?? DateTime.now();
  return switch (key) {
    'eod' => DateTime(n.year, n.month, n.day, 19),
    'tomorrow' => DateTime(n.year, n.month, n.day + 1, 12),
    '2d' => DateTime(n.year, n.month, n.day + 2, 19),
    '24h' => n.add(const Duration(hours: 24)),
    '48h' => n.add(const Duration(hours: 48)),
    _ => n,
  };
}

class DateTimeField extends StatelessWidget {
  const DateTimeField({super.key, required this.value, required this.onChanged, this.label = 'Pick date & time', this.quick = const []});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String label;
  final List<(String, String)> quick;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (quick.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final q in quick)
            ActionChip(label: Text(q.$2), onPressed: () => onChanged(quickTime(q.$1))),
        ]),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        key: const Key('datetime-field'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46), alignment: Alignment.centerLeft),
        onPressed: () async {
          final d = await pickDateTime(context, initial: value);
          if (d != null) onChanged(d);
        },
        icon: const Icon(Icons.event_rounded, size: 18),
        label: Text(value == null ? label : fmtDateTime(value)),
      ),
    ]);
  }
}

class PickerOption<T> {
  const PickerOption({required this.value, required this.label, this.subtitle, this.group, this.leading});
  final T value;
  final String label;
  final String? subtitle;
  final String? group;
  final Widget? leading;
}

/// Searchable single-choice list in a bottom sheet.
Future<T?> showSearchPicker<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
  String searchHint = 'Search…',
}) {
  return showAppSheet<T>(
    context,
    expand: true,
    builder: (ctx) => _SearchPicker<T>(title: title, options: options, selected: selected, searchHint: searchHint),
  );
}

class _SearchPicker<T> extends StatefulWidget {
  const _SearchPicker({required this.title, required this.options, this.selected, required this.searchHint});
  final String title;
  final List<PickerOption<T>> options;
  final T? selected;
  final String searchHint;

  @override
  State<_SearchPicker<T>> createState() => _SearchPickerState<T>();
}

class _SearchPickerState<T> extends State<_SearchPicker<T>> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final query = q.trim().toLowerCase();
    final filtered = widget.options
        .where((o) => query.isEmpty || o.label.toLowerCase().contains(query) || (o.subtitle?.toLowerCase().contains(query) ?? false))
        .toList();
    String? lastGroup;
    return Column(children: [
      SheetTitle(widget.title),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          key: const Key('picker-search'),
          autofocus: false,
          decoration: InputDecoration(hintText: widget.searchHint, prefixIcon: const Icon(Icons.search_rounded, size: 20)),
          onChanged: (v) => setState(() => q = v),
        ),
      ),
      Expanded(
        child: filtered.isEmpty
            ? const EmptyState(icon: Icons.search_off_rounded, title: 'No matches')
            : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final o = filtered[i];
                  final header = o.group != null && o.group != lastGroup;
                  lastGroup = o.group;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (header)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                        child: Text(o.group!.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
                      ),
                    ListTile(
                      key: ValueKey('pick-${o.label}'),
                      leading: o.leading,
                      title: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      subtitle: o.subtitle == null ? null : Text(o.subtitle!, style: Theme.of(context).textTheme.bodySmall),
                      trailing: o.value == widget.selected ? const Icon(Icons.check_rounded, color: TF.primary) : null,
                      onTap: () => Navigator.pop(context, o.value),
                    ),
                  ]);
                },
              ),
      ),
    ]);
  }
}

/// Tap-to-open field showing the current picker choice.
class PickerField extends StatelessWidget {
  const PickerField({super.key, required this.label, required this.onTap, this.icon, this.placeholder = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool placeholder;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            prefixIcon: icon == null ? null : Icon(icon, size: 19),
            suffixIcon: const Icon(Icons.unfold_more_rounded, size: 19),
            enabled: onTap != null,
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: placeholder ? TF.faint : TF.ink)),
        ),
      );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TF.inkSoft)),
      );
}

class Surface extends StatelessWidget {
  const Surface({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = TF.surface, this.borderColor = TF.line});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(TF.radius),
          border: Border.all(color: borderColor),
          // Raised white cards, flat tinted ones — same as the dashboard.
          boxShadow: color == TF.surface ? Brand.shadow : null,
        ),
        child: child,
      );
}

/// Centers content and caps its width on large screens.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 1100});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
