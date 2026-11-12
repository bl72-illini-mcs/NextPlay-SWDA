-- Run AFTER schema.sql in the Supabase SQL editor (as postgres).
-- All temporary records and tests are rolled back.
begin;
insert into auth.users(id) values('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
insert into public.team_members(id,name) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Alice');
insert into public.labels(id,name) values('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Feature');
select public.save_task('{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","title":"A private task"}',array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa']::uuid[],array['bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb']::uuid[]);
insert into public.comments(task_id,body) values('cccccccc-cccc-4ccc-8ccc-cccccccccccc','First comment');
select public.save_task('{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","title":"Updated task","status":"in_progress"}',array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa']::uuid[],array['bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb']::uuid[]);
do $$ begin
  if not exists(select 1 from public.task_activity where body='Moved from To Do → In Progress') then raise exception 'Status log missing'; end if;
  begin
    insert into public.task_activity(task_id,user_id,body) values('cccccccc-cccc-4ccc-8ccc-cccccccccccc',auth.uid(),'Forged');
    raise exception 'Forged activity accepted';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
do $$ begin
  if exists(select 1 from public.tasks) or exists(select 1 from public.comments) or exists(select 1 from public.task_activity) or exists(select 1 from public.team_members) or exists(select 1 from public.labels) or exists(select 1 from public.task_assignees) or exists(select 1 from public.task_labels) then raise exception 'Guest isolation failed'; end if;
  begin
    perform public.save_task('{"title":"Invalid assignment"}',array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa']::uuid[],'{}'::uuid[]);
    raise exception 'Cross-owner assignment accepted';
  exception when foreign_key_violation then null; end;
  if exists(select 1 from public.tasks) then raise exception 'Atomic rollback failed'; end if;
  begin
    insert into public.comments(task_id,body) values('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Unauthorized');
    raise exception 'Cross-owner comment accepted';
  exception when foreign_key_violation then null; end;
  begin
    perform public.save_task('{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","title":"Hijacked"}');
    raise exception 'Cross-owner overwrite accepted';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.tasks(title,user_id) values('Spoofed','11111111-1111-4111-8111-111111111111');
    raise exception 'Owner spoofing accepted';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
do $$ begin
  if (select title from public.tasks where id='cccccccc-cccc-4ccc-8ccc-cccccccccccc') <> 'Updated task' then raise exception 'Task modified by wrong guest'; end if;
end $$;
delete from public.tasks where id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
do $$ begin
  if exists(select 1 from public.task_activity) or exists(select 1 from public.comments) or exists(select 1 from public.task_assignees) or exists(select 1 from public.task_labels) then raise exception 'Cascade cleanup failed'; end if;
end $$;
rollback;
