-- Forma: run once in a new Supabase project's SQL editor.
-- In Authentication > Sign In / Providers, enable Anonymous Sign-Ins.
-- The browser uses only the public anon/publishable key. Never use a service key.
begin;
create extension if not exists pgcrypto;

create table public.team_members (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 80),
  color text not null default '#8eaa95' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at timestamptz not null default now(),
  unique(id,user_id), unique(user_id,name)
);
create table public.labels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 80),
  color text not null default '#8ba3bd' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at timestamptz not null default now(),
  unique(id,user_id), unique(user_id,name)
);
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(btrim(title)) between 1 and 200),
  status text not null default 'todo' check (status in ('todo','in_progress','in_review','done')),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  description text not null default '' check (length(description)<=10000),
  priority text not null default 'normal' check (priority in ('low','normal','high')),
  due_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id,user_id)
);
-- Multiple assignees replace the optional single assignee_id field.
-- Composite foreign keys prevent links across different guests' workspaces.
create table public.task_assignees (
  task_id uuid not null,
  member_id uuid not null,
  user_id uuid not null default auth.uid(),
  primary key(task_id,member_id),
  foreign key(task_id,user_id) references public.tasks(id,user_id) on delete cascade,
  foreign key(member_id,user_id) references public.team_members(id,user_id) on delete cascade
);
create table public.task_labels (
  task_id uuid not null,
  label_id uuid not null,
  user_id uuid not null default auth.uid(),
  primary key(task_id,label_id),
  foreign key(task_id,user_id) references public.tasks(id,user_id) on delete cascade,
  foreign key(label_id,user_id) references public.labels(id,user_id) on delete cascade
);
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null,
  user_id uuid not null default auth.uid(),
  body text not null check (length(btrim(body)) between 1 and 5000),
  created_at timestamptz not null default now(),
  foreign key(task_id,user_id) references public.tasks(id,user_id) on delete cascade
);
create table public.task_activity (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null,
  user_id uuid not null,
  body text not null,
  created_at timestamptz not null default now(),
  foreign key(task_id,user_id) references public.tasks(id,user_id) on delete cascade
);

create index tasks_user_status_idx on public.tasks(user_id,status);
create index tasks_user_due_idx on public.tasks(user_id,due_date);
create index members_user_idx on public.team_members(user_id);
create index labels_user_idx on public.labels(user_id);
create index assignees_user_idx on public.task_assignees(user_id,member_id);
create index task_labels_user_idx on public.task_labels(user_id,label_id);
create index comments_task_time_idx on public.comments(user_id,task_id,created_at);
create index activity_task_time_idx on public.task_activity(user_id,task_id,created_at);

-- Anonymous sign-in creates an authenticated Postgres role, not an anon role.
do $$
declare tab text;
begin
  foreach tab in array array['tasks','team_members','labels','task_assignees','task_labels','comments'] loop
    execute format('alter table public.%I enable row level security',tab);
    execute format('create policy own_select on public.%I for select to authenticated using ((select auth.uid()) = user_id)',tab);
    execute format('create policy own_insert on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)',tab);
    execute format('create policy own_update on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)',tab);
    execute format('create policy own_delete on public.%I for delete to authenticated using ((select auth.uid()) = user_id)',tab);
    execute format('revoke all on public.%I from anon',tab);
    execute format('grant select,insert,update,delete on public.%I to authenticated',tab);
  end loop;
end $$;
alter table public.task_activity enable row level security;
create policy own_select on public.task_activity for select to authenticated using ((select auth.uid()) = user_id);
-- Clients cannot forge activity. Only the database trigger writes these records.
revoke all on public.task_activity from anon,authenticated;
grant select on public.task_activity to authenticated;

create function public.touch_task() returns trigger language plpgsql set search_path='' as $$
begin
  new.updated_at=now();
  new.created_at=old.created_at;
  return new;
end $$;
create trigger tasks_touch before update on public.tasks for each row execute function public.touch_task();

create function public.task_status_name(s text) returns text language sql immutable set search_path='' as $$
  select case s when 'todo' then 'To Do' when 'in_progress' then 'In Progress' when 'in_review' then 'In Review' when 'done' then 'Done' else s end;
$$;
create function public.record_task_activity() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    insert into public.task_activity(task_id,user_id,body) values(new.id,new.user_id,'Created this task');
  else
    if new.user_id is distinct from old.user_id then raise exception 'Task ownership cannot change'; end if;
    if new.status is distinct from old.status then
      insert into public.task_activity(task_id,user_id,body) values(new.id,new.user_id,'Moved from '||public.task_status_name(old.status)||' → '||public.task_status_name(new.status));
    end if;
    if (new.title,new.description,new.priority,new.due_date) is distinct from (old.title,old.description,old.priority,old.due_date) then
      insert into public.task_activity(task_id,user_id,body) values(new.id,new.user_id,'Updated task details');
    end if;
  end if;
  return new;
end $$;
create trigger tasks_activity after insert or update on public.tasks for each row execute function public.record_task_activity();

create function public.record_link_activity() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_task uuid; v_user uuid; v_text text;
begin
  if tg_op='DELETE' then v_task=old.task_id; v_user=old.user_id; else v_task=new.task_id; v_user=new.user_id; end if;
  v_text=case when tg_table_name='task_assignees' then 'Updated assignees' else 'Updated labels' end;
  -- A task cascade deletion should not create a new activity row.
  if exists(select 1 from public.tasks where id=v_task and user_id=v_user) then
    insert into public.task_activity(task_id,user_id,body) values(v_task,v_user,v_text);
  end if;
  return null;
end $$;
create trigger assignees_activity after insert or update or delete on public.task_assignees for each row execute function public.record_link_activity();
create trigger labels_activity after insert or update or delete on public.task_labels for each row execute function public.record_link_activity();

-- Atomic save: a bad assignment or label rolls the entire save back.
-- SECURITY INVOKER ensures all statements retain the caller's RLS policies.
create function public.save_task(p_task jsonb,p_assignees uuid[] default '{}',p_labels uuid[] default '{}')
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_id uuid; v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Sign in first'; end if;
  if p_assignees is null or p_labels is null then raise exception 'Assignments and labels must be arrays'; end if;
  v_id=coalesce((p_task->>'id')::uuid,gen_random_uuid());
  insert into public.tasks(id,user_id,title,description,status,priority,due_date)
    values(v_id,v_user,btrim(p_task->>'title'),coalesce(p_task->>'description',''),coalesce(p_task->>'status','todo'),coalesce(p_task->>'priority','normal'),nullif(p_task->>'due_date','')::date)
  on conflict(id) do update set title=excluded.title,description=excluded.description,status=excluded.status,priority=excluded.priority,due_date=excluded.due_date;
  delete from public.task_assignees where task_id=v_id and user_id=v_user and not(member_id=any(p_assignees));
  insert into public.task_assignees(task_id,member_id,user_id)
    select v_id,x,v_user from (select distinct unnest(p_assignees) x) a
    on conflict(task_id,member_id) do nothing;
  delete from public.task_labels where task_id=v_id and user_id=v_user and not(label_id=any(p_labels));
  insert into public.task_labels(task_id,label_id,user_id)
    select v_id,x,v_user from (select distinct unnest(p_labels) x) a
    on conflict(task_id,label_id) do nothing;
  return v_id;
end $$;
revoke all on function public.save_task(jsonb,uuid[],uuid[]) from public,anon;
grant execute on function public.save_task(jsonb,uuid[],uuid[]) to authenticated;
revoke all on function public.record_task_activity() from public,anon,authenticated;
revoke all on function public.record_link_activity() from public,anon,authenticated;
commit;
