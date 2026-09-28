# TaskFlow Mobile — Features

TaskFlow is RentFoxxy's task management app for iOS and Android. It uses the same server and accounts as the TaskFlow website, so tasks, chats and reports are the same everywhere, in real time.

## Signing in

- Sign in with your RentFoxxy work email and password.
- **Forgot password:** get a 6-digit code by email, enter it and choose a new password. You can resend the code after 30 seconds.
- **Stay signed in:** your session is saved on the device, so reopening the app takes you straight in. With no internet, it still opens with your saved profile.
- Logins that have expired renew in the background, without asking you to sign in again.

## Dashboard

The home screen shows your day at a glance, with four counters:

- **Accept response:** new tasks waiting for you to accept (30-minute response time).
- **Escalated:** overdue tasks that need an explanation.
- **In progress:** tasks you've accepted or started.
- **Due today.**

Below the counters, tasks are grouped into sections: to accept, escalated, due today, in progress, assigned by you and still open, and recently done. New tasks can be accepted straight from their card.

You can filter the dashboard by due date (today or a date range). Admins and the CEO can also view any person's or team's dashboard and see who is online, then tap someone to start a chat.

## Tasks

The Tasks tab has these filters:

- **Views:** My tasks, Created by me, Team (managers), All (Admin/CEO).
- **Search** by title or description.
- **Status:** open tasks, all tasks, or one of the 10 statuses.
- **Due date:** any, today, or a date range.
- **Person or team** (Admin/CEO).

Results are shown 15 per page, and one tap resets all filters.

Each task card shows:

- its status, colour-coded;
- priority, task type and blocked state;
- the response countdown, or "No response" once it has run out;
- the assignee, creator and project;
- due date and ETA, with overdue dates in red;
- subtask progress and the comment count.

An **Action needed** badge appears when the task needs your decision: for example, the assignee wants to discuss it, rejected it, is blocked, or needs information from you.

From a card you can change the status, open comments, chat with the other person on the task, reassign it, add a subtask, or delete it (Admin/CEO).

## Creating tasks

The task form supports:

- **One task**, or **several at once** (one title per line).
- **Assigning** to a person or a whole team. After picking a team, you can tap one of its members to assign that person instead.
- **Task type**, optional; the choices match the assignee's team.
- **Due date**, with quick picks (today at 7 PM, tomorrow at noon, in 2 days) or any date and time.
- **Priority:** Urgent, High, Normal or Low.
- **Project**, subtasks, collaborators (can view and comment) and watchers (can view only).
- **File attachments**, and **links** in the description that can be tapped.

## Task workflow

The task detail screen only shows the actions allowed for your role on that task:

- **Accept + ETA:** accepting a task requires an estimated completion time.
- **Discuss** or **Reject**, with a reason.
- **Start**, then **Mark done**.
- **Blocked / Unblock**, with a reason.
- **Update ETA:** every change is kept, and you can view the history.
- **Request information:** the assignee asks for something they need, such as access or files. The creator provides it in the app, and the assignee continues working.
- **Reopen** or **Cancel**, with a reason.
- **Escalations:** a task that passes its due date becomes escalated. The assignee must explain the delay and propose a new ETA, and an Admin or the CEO accepts or rejects the explanation.
- Closing a task with open subtasks needs a written reason from the creator or an Admin.

You can also:

- manage collaborators and watchers;
- tick off and reassign subtasks;
- open attachments;
- see the activity history.

**Comments** are threaded: reply, react with an emoji, and edit your own. Watchers can read comments but can't post.

## Projects

- A project groups related work. Each one has four tabs:
  - **Overview:** description, team notes (can be pinned) and members.
  - **Tasks:** every task in the project; new tasks created here join it automatically.
  - **Files:** shared documents.
  - **Activity:** a timeline of changes.
- Project managers can add and remove members.

## Chat

- Private chats with anyone in the company.
- Group chats, created by an Admin or the CEO.
- Replies, reactions, editing, deleting, and photos or files in messages.
- @mentions in group chats.
- You can see when someone is typing, and who is online.
- Share a task in a conversation with a tappable link, or create and assign a task from inside a chat.
- Unread counts on the Chat tab and in notifications.

## Notifications

- The bell shows your unread task notifications and chat messages.
- Notifications cover new assignments, comments, response-time warnings and missed deadlines, escalations, completed tasks and ETA changes.
- Tap a notification to open its task. You can mark everything read or clear the list.
- Live updates also pop up briefly while you're using the app.

## Reports

- **Scope:** reports adjust to your role: the whole company for Admin/CEO, your team for managers, and your own work for everyone else.
- **Numbers:**
  - open tasks;
  - overdue tasks;
  - missed response times;
  - escalations waiting for an explanation, and explanations waiting for review;
  - tasks due this week;
  - completed tasks;
  - on-time completion rate;
  - average response time.
- **Drill down:** tap any number to see the tasks behind it.
- **Breakdowns:** by task type and by person, with extra columns for QA staff.
- **Filters:** team, task type, and period (today, 7, 30 or 90 days, or a custom range).
- **CSV export** of the per-person report.

## Admin and management

- **Task types:** create, rename, turn on or off, and delete if unused.
- **Users** (Admin only): create them with a WhatsApp number, change role or team, make them active or inactive, reset passwords, and delete.
- **Teams** (Admin only): create, rename, set the manager, choose members, and delete.

## Scribble

- A sketchpad with several colours and line widths, an eraser, undo/redo and clear.
- **Boards:** name and save them to your account. After the first save, changes save automatically.
- **Send as task:** turns the drawing into an image attached to a new task.

## Design and platform

- A clean light theme with colour-coded statuses and priorities.
- Designed for phones, with a layout that also works on tablets.
- Pull down to refresh; lists also update live when data changes.
- Every action confirms with a short message, and errors are explained in plain language.
- Runs on **iOS 14+ and Android**.
