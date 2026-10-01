import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_ui.dart';
import '../../widgets/common.dart';
import '../shell/top_bar.dart';

const userRoles = ['MEMBER', 'QA', 'MANAGER', 'CEO', 'ADMIN'];

String? phoneError(String phone) {
  final t = phone.trim();
  if (t.isEmpty) return null;
  return RegExp(r'^\d{10}$').hasMatch(t.replaceAll(RegExp(r'\D'), '')) ? null : 'Enter a valid 10-digit phone number';
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<AppUser> users = [];
  List<Team> teams = [];
  List<TaskType> types = [];
  bool loaded = false;
  String? error;

  /// Admin section filter shown in the hero: all, types, users or teams.
  String section = 'all';

  TaskFlowApi get api => Get.find<TaskFlowApi>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([api.users(), api.teams(), api.taskTypes(manage: true)]);
      if (!mounted) return;
      setState(() {
        users = r[0] as List<AppUser>;
        teams = r[1] as List<Team>;
        types = r[2] as List<TaskType>;
        loaded = true;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  Future<void> _run(Future<void> Function() f, String success) async {
    try {
      await f();
      toast(success);
      await _load();
    } catch (e) {
      toastError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    if (me != null && !me.canManage) {
      return const Scaffold(
        backgroundColor: Brand.surface,
        appBar: TopBar(title: 'Admin'),
        body: Center(child: EmptyState(icon: Icons.lock_outline_rounded, title: 'Admin or Team Head access only')),
      );
    }
    final isAdmin = me?.isAdmin ?? false;
    bool show(String s) => !isAdmin || section == 'all' || section == s;
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: TopBar(title: isAdmin ? 'Admin' : 'Manage'),
      body: !loaded
          ? (error != null ? ErrorView(message: error!, onRetry: _load) : const Padding(padding: EdgeInsets.all(16), child: SkeletonList()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
                PageBody(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _hero(me!, isAdmin),
                    const SizedBox(height: 20),
                    if (show('types')) _taskTypes(me),
                    if (isAdmin && show('users')) ...[
                      if (show('types')) const SizedBox(height: 22),
                      _users(me),
                    ],
                    if (isAdmin && show('teams')) ...[
                      if (show('types') || show('users')) const SizedBox(height: 22),
                      _teams(),
                    ],
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Brand.surfaceLow, borderRadius: BorderRadius.circular(12)),
                      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.schedule_rounded, size: 16, color: Brand.onVariant),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Working hours: 10:00 – 19:00 IST, Mon–Sat · Response SLA: 30 working minutes · '
                            'Escalation: automatic when a task passes its due date. The backend sweeps SLAs automatically.',
                            style: TextStyle(fontSize: 12, color: Brand.onVariant, height: 1.5),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
    );
  }

  // ---- Hero ---------------------------------------------------------------------

  Widget _hero(Me me, bool isAdmin) {
    final activeTypes = types.where((t) => t.isActive).length;
    final activeUsers = users.where((u) => u.isActive).length;
    Widget stat(String value, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, maxLines: 1, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1, letterSpacing: -0.6, color: Brand.lime)),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7))),
          ]),
        );
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HeroEyebrow(isAdmin ? 'Admin console' : 'Team settings'),
        const SizedBox(height: 8),
        HeroTitle(isAdmin ? 'Users, teams & task types' : 'Task types for ${me.team ?? 'your team'}'),
        const SizedBox(height: 14),
        Row(children: [
          if (isAdmin) ...[
            stat('$activeUsers/${users.length}', 'Active users'),
            stat('${teams.length}', teams.length == 1 ? 'Team' : 'Teams'),
          ],
          stat('$activeTypes/${types.length}', 'Active types'),
          if (!isAdmin) stat('${types.fold<int>(0, (a, t) => a + t.usedCount)}', 'Tasks using them'),
        ]),
        if (isAdmin) ...[
          const SizedBox(height: 14),
          HeroSegments(items: [
            for (final (id, label) in const [('all', 'All'), ('types', 'Types'), ('users', 'Users'), ('teams', 'Teams')])
              (ValueKey('admin-section-$id'), label, section == id, () => setState(() => section = id)),
          ]),
        ],
      ]),
    );
  }

  /// Small lime "add" button used in section headers.
  Widget _addButton(Key key, String label, IconData icon, VoidCallback onPressed) => FilledButton.icon(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: Brand.lime,
          foregroundColor: Brand.navy,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );

  Widget _sectionTrailing(int count, Widget button) => Row(mainAxisSize: MainAxisSize.min, children: [CountBubble(count), const SizedBox(width: 8), button]);

  /// White outlined list container with thin dividers between rows.
  Widget _listCard(List<Widget> rows) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Brand.outline)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final r in rows.asMap().entries) ...[
            if (r.key > 0) const Divider(height: 1, thickness: 1, color: Brand.outline),
            r.value,
          ],
        ]),
      );

  Widget _iconSquare(IconData icon, {Color bg = Brand.limeLight, Color fg = Brand.navy}) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: fg),
      );

  Widget _activeToggle(Key key, bool active, VoidCallback onTap) => Pill(
        active ? 'Active' : 'Inactive',
        key: key,
        dot: true,
        fg: active ? TF.green : Brand.onVariant,
        bg: active ? TF.greenSoft : Brand.surfaceLow,
        onTap: onTap,
      );

  static const _meta = TextStyle(fontSize: 11.5, color: Brand.onVariant);
  static const _rowTitle = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Brand.navy);

  // ---- Task types -------------------------------------------------------------

  Widget _taskTypes(Me me) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BrandSectionTitle(
        title: 'Task types',
        trailing: _sectionTrailing(types.length, _addButton(const Key('add-type'), 'Add type', Icons.add_rounded, () => _addType(me))),
      ),
      types.isEmpty
          ? BrandCard(child: const Text('No task types yet.', style: TextStyle(fontSize: 13, color: Brand.onVariant)))
          : _listCard([
              for (final t in types)
                Padding(
                  key: ValueKey('type-${t.id}'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(children: [
                    _iconSquare(Icons.sell_outlined, bg: t.isActive ? Brand.limeLight : Brand.surfaceLow, fg: t.isActive ? Brand.navy : Brand.onVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _rowTitle),
                        const SizedBox(height: 2),
                        Text(
                          '${t.teamName ?? '—'} · used by ${t.usedCount} task${t.usedCount == 1 ? '' : 's'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _meta,
                        ),
                      ]),
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: _activeToggle(
                        ValueKey('type-toggle-${t.id}'),
                        t.isActive,
                        () => _run(() => api.updateTaskType(t.id, {'isActive': !t.isActive}), t.isActive ? 'Task type deactivated' : 'Task type activated'),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('type-edit-${t.id}'),
                      tooltip: 'Rename',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 18, color: Brand.navy),
                      onPressed: () async {
                        final v = await promptText(context, title: 'Rename task type', initial: t.name, maxLines: 1, confirmLabel: 'Save');
                        if (v != null) _run(() => api.updateTaskType(t.id, {'name': v}), 'Task type updated');
                      },
                    ),
                    IconButton(
                      key: ValueKey('type-delete-${t.id}'),
                      tooltip: t.usedCount > 0 ? 'In use — deactivate instead' : 'Delete',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.delete_outline_rounded, size: 18, color: t.usedCount > 0 ? TF.faint : brandRed),
                      onPressed: t.usedCount > 0
                          ? null
                          : () async {
                              if (await confirmDialog(context,
                                  title: 'Delete task type?', message: 'Delete "${t.name}"? This cannot be undone.', confirmLabel: 'Delete', destructive: true)) {
                                _run(() => api.deleteTaskType(t.id), 'Task type deleted');
                              }
                            },
                    ),
                  ]),
                ),
            ]),
    ]);
  }

  Future<void> _addType(Me me) async {
    int? teamId = me.isAdminOrCeo ? null : me.teamId;
    final name = TextEditingController();
    final ok = await showAppSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Add task type', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 14),
              const FieldLabel('Team'),
              if (me.isAdminOrCeo)
                DropdownButtonFormField<int>(
                  key: const Key('type-team'),
                  initialValue: teamId,
                  hint: const Text('Choose team'),
                  items: [for (final t in teams) DropdownMenuItem(value: t.id, child: Text(t.name))],
                  onChanged: (v) => set(() => teamId = v),
                )
              else
                InputDecorator(decoration: const InputDecoration(), child: Text(me.team ?? 'My team')),
              const SizedBox(height: 10),
              const FieldLabel('Type name'),
              TextField(
                key: const Key('type-name'),
                controller: name,
                decoration: const InputDecoration(hintText: 'e.g. Lead Follow-up'),
                onChanged: (_) => set(() {}),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('type-create'),
                onPressed: name.text.trim().isEmpty || teamId == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('Add type'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok == true && teamId != null) _run(() => api.createTaskType(teamId!, name.text.trim()), 'Task type created');
  }

  // ---- Users --------------------------------------------------------------------

  Widget _users(Me me) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BrandSectionTitle(
        title: 'Users',
        trailing: _sectionTrailing(users.length, _addButton(const Key('add-user'), 'Add user', Icons.person_add_alt_1_outlined, _addUser)),
      ),
      users.isEmpty
          ? BrandCard(child: const Text('No users yet.', style: TextStyle(fontSize: 13, color: Brand.onVariant)))
          : _listCard([for (final u in users) _userRow(u, me)]),
    ]);
  }

  Widget _userRow(AppUser u, Me me) => Padding(
        key: ValueKey('user-${u.id}'),
        padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Opacity(opacity: u.isActive ? 1 : 0.5, child: Avatar(u.name, size: 34)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _rowTitle),
              const SizedBox(height: 2),
              Text([u.email, u.phone].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: _meta),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill(u.role, fg: Brand.lime, bg: Brand.navy),
                Pill(u.teamName ?? 'No team', fg: Brand.navy, bg: Brand.surfaceLow),
                _activeToggle(
                  ValueKey('user-active-${u.id}'),
                  u.isActive,
                  () => _run(() => api.updateUser(u.id, {'isActive': !u.isActive}), 'User updated'),
                ),
              ]),
            ]),
          ),
          PopupMenuButton<String>(
            key: ValueKey('user-menu-${u.id}'),
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: Brand.onVariant),
            onSelected: (v) => _userAction(v, u, me),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'role', child: Text('Change role')),
              const PopupMenuItem(value: 'team', child: Text('Change team')),
              const PopupMenuItem(value: 'phone', child: Text('Edit phone')),
              const PopupMenuItem(value: 'password', child: Text('Reset password')),
              if (u.id != me.id) const PopupMenuItem(value: 'delete', child: Text('Delete user', style: TextStyle(color: TF.coral))),
            ],
          ),
        ]),
      );

  Future<void> _userAction(String action, AppUser u, Me me) async {
    switch (action) {
      case 'role':
        final role = await showSearchPicker<String>(context,
            title: 'Role for ${u.name}', selected: u.role, options: [for (final r in userRoles) PickerOption(value: r, label: r)]);
        if (role != null && role != u.role) _run(() => api.updateUser(u.id, {'role': role}), 'User updated');
      case 'team':
        final team = await showSearchPicker<int>(context,
            title: 'Team for ${u.name}',
            selected: u.teamId ?? -1,
            options: [const PickerOption(value: -1, label: 'No team'), for (final t in teams) PickerOption(value: t.id, label: t.name)]);
        if (team != null) _run(() => api.updateUser(u.id, {'teamId': team == -1 ? null : team}), 'User updated');
      case 'phone':
        if (!mounted) return;
        final v = await promptText(context,
            title: 'Edit phone — ${u.name}',
            message: '10-digit mobile number for task WhatsApp notifications. Leave empty to remove.',
            initial: u.phone ?? '',
            required: false,
            maxLines: 1,
            confirmLabel: 'Save');
        if (v == null) return;
        final err = phoneError(v);
        if (err != null) return toast(err);
        _run(() => api.updateUser(u.id, {'phone': v.isEmpty ? null : v.replaceAll(RegExp(r'\D'), '')}), 'Phone updated');
      case 'password':
        final p = await promptText(context, title: 'New password for ${u.name}', minLength: 6, maxLines: 1, obscure: true, confirmLabel: 'Reset');
        if (p != null) _run(() => api.updateUser(u.id, {'password': p}), 'Password reset');
      case 'delete':
        if (u.id == me.id) return toast('You cannot delete your own account');
        final ok = await confirmDialog(context,
            title: 'Delete user?',
            message: 'Permanently delete "${u.name}" and all of their tasks, comments, notifications, projects, and uploads? This cannot be undone.',
            confirmLabel: 'Delete',
            destructive: true);
        if (ok) _run(() => api.deleteUser(u.id), 'User removed');
    }
  }

  Future<void> _addUser() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final phone = TextEditingController();
    String role = 'MEMBER';
    int? teamId;
    final ok = await showAppSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final pErr = phoneError(phone.text);
        final valid = name.text.trim().isNotEmpty && email.text.trim().isNotEmpty && password.text.length >= 6 && pErr == null;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Add user', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              const FieldLabel('Name'),
              TextField(key: const Key('user-name'), controller: name, onChanged: (_) => set(() {})),
              const FieldLabel('Email'),
              TextField(key: const Key('user-email'), controller: email, keyboardType: TextInputType.emailAddress, onChanged: (_) => set(() {})),
              const FieldLabel('Phone (WhatsApp)'),
              TextField(
                key: const Key('user-phone'),
                controller: phone,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: InputDecoration(hintText: '7081002501', counterText: '', errorText: pErr),
                onChanged: (_) => set(() {}),
              ),
              const FieldLabel('Password (min 6)'),
              TextField(key: const Key('user-password'), controller: password, onChanged: (_) => set(() {})),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Role'),
                    DropdownButtonFormField<String>(
                      key: const Key('user-role'),
                      initialValue: role,
                      items: [for (final r in userRoles) DropdownMenuItem(value: r, child: Text(r))],
                      onChanged: (v) => set(() => role = v ?? role),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Team'),
                    DropdownButtonFormField<int>(
                      initialValue: teamId,
                      hint: const Text('None'),
                      items: [
                        const DropdownMenuItem<int>(value: null, child: Text('None')),
                        for (final t in teams) DropdownMenuItem(value: t.id, child: Text(t.name)),
                      ],
                      onChanged: (v) => set(() => teamId = v),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              FilledButton(key: const Key('user-create'), onPressed: valid ? () => Navigator.pop(ctx, true) : null, child: const Text('Create user')),
            ]),
          ),
        );
      }),
    );
    if (ok != true) return;
    _run(
      () => api.createUser({
        'name': name.text.trim(),
        'email': email.text.trim(),
        'password': password.text,
        'phone': phone.text.trim().isEmpty ? null : phone.text.replaceAll(RegExp(r'\D'), ''),
        'role': role,
        'teamId': teamId,
      }),
      'User created',
    );
  }

  // ---- Teams --------------------------------------------------------------------

  Widget _teams() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BrandSectionTitle(
        title: 'Teams',
        trailing: _sectionTrailing(teams.length, _addButton(const Key('add-team'), 'Add team', Icons.add_rounded, () => _teamForm())),
      ),
      if (teams.isEmpty) BrandCard(child: const Text('No teams yet.', style: TextStyle(fontSize: 13, color: Brand.onVariant))),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 800 ? 3 : (c.maxWidth >= 500 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final t in teams)
            SizedBox(
              width: w,
              child: BrandCard(
                key: ValueKey('team-${t.id}'),
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(children: [
                  _iconSquare(Icons.groups_2_outlined, bg: Brand.navy, fg: Brand.lime),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _rowTitle),
                      const SizedBox(height: 2),
                      Text(
                        'Manager: ${t.managerName ?? '—'} · ${t.memberCount} member${t.memberCount == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _meta,
                      ),
                    ]),
                  ),
                  IconButton(
                    key: ValueKey('team-edit-${t.id}'),
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18, color: Brand.navy),
                    onPressed: () => _teamForm(team: t),
                  ),
                  IconButton(
                    key: ValueKey('team-delete-${t.id}'),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: brandRed),
                    onPressed: () async {
                      if (await confirmDialog(context,
                          title: 'Delete team?', message: 'Delete team "${t.name}"? Remove all members first.', confirmLabel: 'Delete', destructive: true)) {
                        _run(() => api.deleteTeam(t.id), 'Team deleted');
                      }
                    },
                  ),
                ]),
              ),
            ),
        ]);
      }),
    ]);
  }

  Future<void> _teamForm({Team? team}) async {
    final name = TextEditingController(text: team?.name ?? '');
    int? managerId = team?.managerId;
    final active = users.where((u) => u.isActive).toList();
    final members = <int>{if (team != null) ...active.where((u) => u.teamId == team.id).map((u) => u.id)};
    final ok = await showAppSheet<bool>(
      context,
      expand: team != null,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final form = <Widget>[
          const FieldLabel('Team name'),
          TextField(key: const Key('team-name'), controller: name, onChanged: (_) => set(() {})),
          const SizedBox(height: 8),
          const FieldLabel('Manager'),
          DropdownButtonFormField<int>(
            key: const Key('team-manager'),
            initialValue: managerId,
            isExpanded: true,
            hint: Text(team == null ? 'Choose later' : 'No manager'),
            items: [
              DropdownMenuItem<int>(value: null, child: Text(team == null ? 'Choose later' : 'No manager')),
              for (final u in active) DropdownMenuItem(value: u.id, child: Text(u.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => set(() => managerId = v),
          ),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: team == null ? MainAxisSize.min : MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(team == null ? 'Add team' : 'Edit ${team.name}', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...form,
              if (team != null) ...[
                const SizedBox(height: 12),
                FieldLabel('Members (${members.length} selected)'),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: TF.line), borderRadius: BorderRadius.circular(12)),
                    child: ListView(children: [
                      for (final u in active)
                        CheckboxListTile(
                          dense: true,
                          value: members.contains(u.id),
                          title: Text(u.name),
                          subtitle: Text(u.role),
                          onChanged: (v) => set(() => v == true ? members.add(u.id) : members.remove(u.id)),
                        ),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('team-save'),
                onPressed: name.text.trim().isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text(team == null ? 'Create team' : 'Save changes'),
              ),
            ]),
          ),
        );
      }),
    );
    if (ok != true) return;
    if (team == null) {
      _run(() => api.createTeam(name.text.trim(), managerId), 'Team created');
    } else {
      if (managerId != null) members.add(managerId!);
      _run(() => api.updateTeam(team.id, {'name': name.text.trim(), 'managerId': managerId, 'memberIds': members.toList()}), 'Team updated');
    }
  }
}
