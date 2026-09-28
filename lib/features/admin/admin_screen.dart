import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
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
        appBar: TopBar(title: 'Admin'),
        body: Center(child: EmptyState(icon: Icons.lock_outline_rounded, title: 'Admin or Team Head access only')),
      );
    }
    final isAdmin = me?.isAdmin ?? false;
    return Scaffold(
      appBar: TopBar(title: isAdmin ? 'Admin' : 'Manage'),
      body: !loaded
          ? (error != null ? ErrorView(message: error!, onRetry: _load) : const Padding(padding: EdgeInsets.all(16), child: SkeletonList()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
                PageBody(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _taskTypes(me!),
                    if (isAdmin) ...[
                      const SizedBox(height: 26),
                      _users(me),
                      const SizedBox(height: 26),
                      _teams(),
                    ],
                    const SizedBox(height: 26),
                    const Surface(
                      color: TF.sunken,
                      borderColor: Colors.transparent,
                      child: Text(
                        'Working hours: 10:00 – 19:00 IST, Mon–Sat · Response SLA: 30 working minutes · '
                        'Escalation: automatic when a task passes its due date. The backend sweeps SLAs automatically.',
                        style: TextStyle(fontSize: 12.5, color: TF.muted, height: 1.5),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
    );
  }

  // ---- Task types -------------------------------------------------------------

  Widget _taskTypes(Me me) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        title: 'Task types',
        icon: Icons.sell_outlined,
        count: types.length,
        trailing: TextButton.icon(
          key: const Key('add-type'),
          onPressed: () => _addType(me),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add type'),
        ),
      ),
      Surface(
        padding: EdgeInsets.zero,
        child: types.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Text('No task types yet.', style: TextStyle(color: TF.muted)))
            : Column(children: [
                for (final t in types.asMap().entries) ...[
                  if (t.key > 0) const Divider(),
                  ListTile(
                    key: ValueKey('type-${t.value.id}'),
                    title: Text(t.value.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${t.value.teamName ?? '—'} · used by ${t.value.usedCount} task${t.value.usedCount == 1 ? '' : 's'}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Pill(
                        t.value.isActive ? 'Active' : 'Inactive',
                        key: ValueKey('type-toggle-${t.value.id}'),
                        fg: t.value.isActive ? TF.green : TF.muted,
                        bg: t.value.isActive ? TF.greenSoft : TF.sunken,
                        onTap: () => _run(
                          () => api.updateTaskType(t.value.id, {'isActive': !t.value.isActive}),
                          t.value.isActive ? 'Task type deactivated' : 'Task type activated',
                        ),
                      ),
                      IconButton(
                        key: ValueKey('type-edit-${t.value.id}'),
                        tooltip: 'Rename',
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        onPressed: () async {
                          final v = await promptText(context, title: 'Rename task type', initial: t.value.name, maxLines: 1, confirmLabel: 'Save');
                          if (v != null) _run(() => api.updateTaskType(t.value.id, {'name': v}), 'Task type updated');
                        },
                      ),
                      IconButton(
                        key: ValueKey('type-delete-${t.value.id}'),
                        tooltip: t.value.usedCount > 0 ? 'In use — deactivate instead' : 'Delete',
                        icon: Icon(Icons.delete_outline_rounded, size: 19, color: t.value.usedCount > 0 ? TF.faint : TF.coral),
                        onPressed: t.value.usedCount > 0
                            ? null
                            : () async {
                                if (await confirmDialog(context,
                                    title: 'Delete task type?', message: 'Delete "${t.value.name}"? This cannot be undone.', confirmLabel: 'Delete', destructive: true)) {
                                  _run(() => api.deleteTaskType(t.value.id), 'Task type deleted');
                                }
                              },
                      ),
                    ]),
                  ),
                ],
              ]),
      ),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        title: 'Users',
        icon: Icons.person_outline_rounded,
        color: TF.violet,
        count: users.length,
        trailing: TextButton.icon(
          key: const Key('add-user'),
          onPressed: _addUser,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('Add user'),
        ),
      ),
      Surface(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (final u in users.asMap().entries) ...[
            if (u.key > 0) const Divider(),
            _userRow(u.value, me),
          ],
        ]),
      ),
    ]);
  }

  Widget _userRow(AppUser u, Me me) => Padding(
        key: ValueKey('user-${u.id}'),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(children: [
          Avatar(u.name, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text([u.email, u.phone].whereType<String>().join(' · '), style: const TextStyle(fontSize: 12, color: TF.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill(u.role, fg: TF.primaryDeep, bg: TF.primarySoft),
                Pill(u.teamName ?? 'No team'),
                Pill(
                  u.isActive ? 'Active' : 'Inactive',
                  key: ValueKey('user-active-${u.id}'),
                  fg: u.isActive ? TF.green : TF.muted,
                  bg: u.isActive ? TF.greenSoft : TF.sunken,
                  onTap: () => _run(() => api.updateUser(u.id, {'isActive': !u.isActive}), 'User updated'),
                ),
              ]),
            ]),
          ),
          PopupMenuButton<String>(
            key: ValueKey('user-menu-${u.id}'),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        title: 'Teams',
        icon: Icons.groups_2_outlined,
        color: TF.sky,
        count: teams.length,
        trailing: TextButton.icon(
          key: const Key('add-team'),
          onPressed: () => _teamForm(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add team'),
        ),
      ),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 800 ? 3 : (c.maxWidth >= 500 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final t in teams)
            SizedBox(
              width: w,
              child: Surface(
                key: ValueKey('team-${t.id}'),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.name, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text('Manager: ${t.managerName ?? '—'}', style: const TextStyle(fontSize: 12.5, color: TF.muted)),
                      Text('${t.memberCount} member${t.memberCount == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12.5, color: TF.faint)),
                    ]),
                  ),
                  IconButton(
                    key: ValueKey('team-edit-${t.id}'),
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined, size: 19),
                    onPressed: () => _teamForm(team: t),
                  ),
                  IconButton(
                    key: ValueKey('team-delete-${t.id}'),
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline_rounded, size: 19, color: TF.coral),
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
