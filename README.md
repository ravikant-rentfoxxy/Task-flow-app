# TaskFlow (Flutter)

iOS and Android client for the TaskFlow task management system. It talks to the existing **TMS_BE** API (the same backend used by the TMS_FE web app).

**Stack:** GetX (state and dependency injection) · Dio (HTTP) · Hive (stores the signed-in session and user profile) · socket_io_client (realtime updates)

## Features

- **Sign in:** email/password login, and password reset with a 6-digit emailed code. The session and user profile are cached in Hive, so the app opens already signed in, even when offline.
- **Dashboard:** metrics, plus these sections:
  - Accept response (30-min SLA)
  - Escalated
  - Due today
  - In progress
  - Assigned by me
  - Recently done

  Admin/CEO can also filter by person or team and see who is online.
- **Tasks:**
  - Filters: My tasks / Created by me / Team (manager) / All (admin/CEO); search; status; due date (today or a range).
  - Pagination.
  - Per-task actions: comments, chat, create a subtask, delete (admin/CEO), reassign.
- **Task detail:** the full workflow, driven by the permissions the server sends:
  - accept with an ETA, discuss, reject, start, done;
  - block/unblock, reopen, cancel, update the ETA;
  - request information, provide it, and resume work;
  - escalation explanation and review;
  - the "open subtasks" override.

  Also: collaborators and watchers, subtasks, attachments, ETA history, the activity log, and threaded comments with reactions and edits.
- **Composer:**
  - Single task, several tasks at once (one per line), or a subtask.
  - Assign to a person or a team; the task type follows the assignee's team.
  - Due-date quick picks, priority, project, inline subtasks, collaborators and watchers, file attachments.
- **Projects:** list and create. Each project has:
  - an overview, with notes you can pin and a member list;
  - its tasks;
  - file uploads;
  - activity.
- **Chat:**
  - Direct and group chats (admin/CEO can create and manage groups).
  - Replies, reactions, edit and delete, attachments.
  - `@mentions` in groups, typing indicator, online presence.
  - Task links, attaching a task to a message, and assigning a task from inside a chat.
  - Unread counts.
- **Notifications:** task notifications and chat unread counts; mark as read, clear, and tap to open the task.
- **Reports:**
  - Summary stats; tap a stat to see the tasks behind it.
  - Breakdowns by task type and by person, including the QA columns.
  - Filters: team, task type, period.
  - CSV export.
- **Admin / Manage:**
  - Task types: create, rename, activate/deactivate, delete.
  - Users: create; change role, team, phone and active status; reset password; delete.
  - Teams: create, edit (manager and members), delete.
- **Scribble:** freehand boards saved to the server, with "send as task" (attaches a PNG of the board). Boards drawn on the web open read-only as a copy.

## Run

```bash
flutter pub get
flutter run                                             # uses https://task.rentfoxxy.com/api
flutter run --dart-define=API_URL=http://localhost:4000/api      # iOS simulator → local backend
flutter run --dart-define=API_URL=http://10.0.2.2:4000/api       # Android emulator → local backend
```

## Tests

```bash
flutter test test/unit test/widget                     # logic, Dio client, Hive session, every screen (fake backend)
TF_LIVE_API=http://localhost:4000/api flutter test test/live      # every API call against a real TMS_BE
flutter test integration_test -d <iPhone simulator id> \
  --dart-define=API_URL=http://localhost:4000/api      # full UI run: admin assigns → member completes
```

The live test and the integration test use the seeded demo accounts (`admin@rentfoxxy.com` and `neha@rentfoxxy.com`, both with password `password123`).

## Layout

```
lib/core       config, Dio ApiClient, Hive LocalStore, formatting, task rules
lib/data       TaskFlowApi (typed wrapper for each endpoint)
lib/models     data models
lib/state      GetX controllers: auth, realtime socket, chat unread
lib/features   screens (auth, dashboard, tasks, projects, chat, notifications, reports, admin, scribble, shell)
lib/widgets    shared UI (pills, pickers, sheets, attachments, filters)
lib/theme      light theme
```
