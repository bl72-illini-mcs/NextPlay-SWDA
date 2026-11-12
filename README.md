# Forma — Task workspace

A responsive, dependency-free Kanban frontend with Supabase Auth and PostgreSQL integration. All seven advanced feature groups are included. No service-role credentials or paid services are required.

## Run locally

Requires Python 3 (or any static HTTP server).

```sh
python3 -m http.server 5173 --directory dist
```

Open http://localhost:5173. No installation or build step is needed. Source: `dist/app.js`, `dist/style.css`, `dist/index.html`.

## Supabase setup

1. Create a free Supabase project.
2. Run `supabase/schema.sql` once in its SQL editor against a new project.
3. Enable **Authentication → Sign In / Providers → Anonymous Sign-Ins**.
4. Copy the project URL and public anon/publishable key from project settings.
5. In Forma, select **Connect to Supabase**, enter those public values, and connect.

The published frontend includes the project URL and public publishable key supplied by the owner. New visitors connect automatically and receive their own guest session; they do not need to enter settings. The app automatically creates a guest session. Its access token is refreshed before expiry. Only the public key is accepted; secret keys and service-role JWTs are rejected. The connection and guest session persist in browser localStorage. Do not clear browser storage if you need to retain that guest identity. For production, configure Supabase abuse protection / CAPTCHA as appropriate and add permanent-account upgrade/recovery.

Demo mode remains available through Connection settings → Back to local demo, with sample tasks saved independently in localStorage. Demo tasks never automatically upload to Supabase. A new Supabase guest starts with an empty board. Demo mode is a single browser-local workspace and does not provide server-side access control.

## Features

- Four columns: To Do, In Progress, In Review, Done.
- Native drag-and-drop; equivalent status select for keyboard and touch.
- Task creation, editing and deletion; optional description, priority and due date.
- Team members with names and custom avatar colors; multiple assignees per task.
- Timestamped comments in chronological order.
- Database-generated task activity for creation, edits, status, assignments and labels.
- Custom colored labels, multiple labels per task, label filtering.
- Overdue and due-soon card indicators; completed tasks never show overdue.
- Combined title search, priority, assignee and label filters.
- Whole-workspace statistics: total, in progress, completed and overdue.
- Board and list views, responsive layout, empty/loading/error states, accessible dialogs with focus trapping and return.

## Schema and security

`tasks`, `team_members`, `labels`, `task_assignees`, `task_labels`, `comments`, `task_activity`.

All tables enable RLS. Guest sign-ins use the authenticated role. Policies bind all reads and writes to auth.uid(). Composite foreign keys ensure task links and comments cannot cross owners. Multiple assignments use a junction table instead of a single assignee_id. Tasks and linked records cascade on deletion. Required fields, statuses, priorities, colors and input lengths have database constraints. `save_task` is a SECURITY INVOKER transaction: tasks, labels and assignments save together or roll back. Activity is trigger-generated and clients have read access only. SECURITY DEFINER triggers have a fixed empty search path and fully qualified table references.

## Validation

Run `node --check dist/app.js` for syntax. For the automated DOM and PostgreSQL integration suite, run `npm install` then `npm test` (dev dependencies only; none are needed to serve the frontend). The tests use PGlite PostgreSQL with a small auth.uid() shim; run the supplied SQL against Supabase for platform-level verification. `tests/schema_test.sql` is a rollback-only SQL security/integration test for the Supabase SQL editor after installing the schema. It checks owner isolation, assignment integrity, transaction rollback, change logging and delete cascades using two temporary test users.

Manual browser acceptance: create a task; add members and labels; assign several of each; move by drag and by status menu; edit details; comment; inspect activity; combine filters; reload; use keyboard and mobile widths. In two independent browser profiles, connect the same Supabase project and verify guest A's records never appear for guest B.

## Hosting and repository

The frontend is static and can run on Cloudflare Pages, Netlify or Vercel (publish `dist`). This workspace is also configured for private Sites hosting. The source repository backing the private deployment is managed by Sites, not GitHub. A GitHub repository must be created under your account separately if needed for assessment submission. The assessment PDF is not included in source or deployment.

## Tradeoffs

Team members are assignment records, not invited users. Each guest owns an independent workspace. Saves refresh from Supabase after completion; no realtime subscription or background polling is included. Card ordering within columns is creation order. Search operates on loaded tasks, suited to a small assessment workspace; pagination and server-side search are future improvements. This app does not provision a Supabase project automatically. RLS tests require the supplied schema to be installed in your own project. Guest accounts have no recovery after storage loss. The public key is browser configuration, while access tokens are persisted for the guest session; a stricter production threat model could use a server-mediated cookie session.


Automated verification completed: PostgreSQL schema installation, guest ownership isolation, cross-owner assignment/comment/overwrite denial, forged activity denial, atomic save rollback, trigger logs and delete cascades; DOM task creation, drag/drop handler, comments, team/label forms, filters, local persistence, list view and deletion. Visual browser verification remains outstanding. Live Supabase verification subsequently passed anonymous sign-in, task creation and updates, multiple-record assignment/label storage, comments, activity, and owner isolation across all seven tables. Temporary test task, member, label, comment and activity records were removed.


Netlify deployment: upload the contents of `dist/` (with index.html at the deploy root) to the existing project at https://beomjong-nextplay-swda.netlify.app. The browser defaults use the public Supabase URL/key. No environment variables or build step are needed. Guest accounts and data stay separate for each browser.
