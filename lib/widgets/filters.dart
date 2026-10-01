import 'package:flutter/material.dart';

import '../core/format.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// all | today | range — due-date filter for task lists.
class DueFilter {
  const DueFilter({this.mode = 'all', this.from, this.to});
  final String mode;
  final DateTime? from;
  final DateTime? to;

  bool get isActive => mode != 'all';

  Map<String, dynamic> toQuery() {
    if (mode == 'today') {
      final b = todayBounds();
      return {'dueFrom': b.from, 'dueTo': b.to};
    }
    if (mode == 'range') {
      final b = rangeBounds(from, to);
      if (b == null) return {};
      return {'dueFrom': b.from, 'dueTo': b.to};
    }
    return {};
  }
}

class DueFilterBar extends StatelessWidget {
  const DueFilterBar({super.key, required this.value, required this.onChanged});
  final DueFilter value;
  final ValueChanged<DueFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final rangeLabel = value.mode == 'range' && value.from != null && value.to != null
        ? '${fmtShortDate(value.from)} – ${fmtShortDate(value.to)}'
        : 'Date range';
    return Wrap(spacing: 8, runSpacing: 8, children: [
      ChoiceChip(
        key: const Key('due-all'),
        label: const Text('Any due date'),
        selected: value.mode == 'all',
        onSelected: (_) => onChanged(const DueFilter()),
      ),
      ChoiceChip(
        key: const Key('due-today'),
        label: const Text('Due today'),
        selected: value.mode == 'today',
        onSelected: (_) => onChanged(const DueFilter(mode: 'today')),
      ),
      ChoiceChip(
        key: const Key('due-range'),
        avatar: Icon(Icons.date_range_rounded, size: 16, color: value.mode == 'range' ? Colors.white : TF.muted),
        label: Text(rangeLabel),
        selected: value.mode == 'range',
        onSelected: (_) async {
          final now = DateTime.now();
          final r = await showDateRangePicker(
            context: context,
            firstDate: DateTime(now.year - 2),
            lastDate: DateTime(now.year + 3),
            initialDateRange: value.from != null && value.to != null ? DateTimeRange(start: value.from!, end: value.to!) : null,
          );
          if (r != null) onChanged(DueFilter(mode: 'range', from: r.start, to: r.end));
        },
      ),
    ]);
  }
}

/// Admin/CEO filter by a user (`u:<id>`) or team (`t:<id>`).
Future<String?> pickUserOrTeam(
  BuildContext context, {
  required List<AppUser> users,
  required List<Team> teams,
  String? selected,
  String emptyLabel = 'All users / teams',
}) async {
  final v = await showSearchPicker<String>(
    context,
    title: 'Filter by person or team',
    selected: selected ?? '',
    searchHint: 'Search users or teams…',
    options: [
      PickerOption(value: '', label: emptyLabel),
      for (final u in users.where((u) => u.isActive))
        PickerOption(value: 'u:${u.id}', label: u.name, subtitle: u.teamName, group: 'People', leading: Avatar(u.name)),
      for (final t in teams) PickerOption(value: 't:${t.id}', label: t.name, subtitle: '${t.memberCount} members', group: 'Teams'),
    ],
  );
  return v;
}

String userOrTeamLabel(String? v, List<AppUser> users, List<Team> teams, {String empty = 'All users / teams'}) {
  if (v == null || v.isEmpty) return empty;
  final id = int.tryParse(v.substring(2));
  if (v.startsWith('t:')) return 'Team · ${teams.where((t) => t.id == id).firstOrNull?.name ?? id}';
  return users.where((u) => u.id == id).firstOrNull?.name ?? 'User #$id';
}

/// Chip that opens a menu of string options.
class MenuChip extends StatelessWidget {
  const MenuChip({super.key, required this.label, required this.options, required this.onSelected, this.icon, this.active = false});

  final String label;
  final List<(String, String)> options;
  final ValueChanged<String> onSelected;
  final IconData? icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o.$1, child: Text(o.$2))],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? TF.primarySoft : TF.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: active ? TF.primary.withValues(alpha: 0.3) : TF.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: active ? TF.primaryDeep : TF.muted), const SizedBox(width: 6)],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? TF.primaryDeep : TF.inkSoft)),
          const SizedBox(width: 2),
          Icon(Icons.expand_more_rounded, size: 18, color: active ? TF.primaryDeep : TF.muted),
        ]),
      ),
    );
  }
}
