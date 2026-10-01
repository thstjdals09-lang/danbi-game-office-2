-- 단비의 게임회사2 · 초기 스키마
--
-- 흐름: idea → planning → ready → building → qa → playtest → kept
--        (대표 분류)  (기획)   (빌드 대기) (빌드)   (검수)  (대표 플레이)
-- 옆길: held(대표 판단 대기), dropped(버림)
--
-- 원칙
-- 1. 모든 상태 변경은 아래 함수로만 한다. 테이블 직접 UPDATE 금지.
-- 2. wip_limits에 상한이 있는 단계가 꽉 차면 앞 단계는 일을 가져가지 않는다. 기본은 빌드 1개만 제한.
-- 3. 대기열은 대표 별표 우선, 그다음 오래 기다린 순서.

-- ---------------------------------------------------------------- 테이블

create table public.wip_limits (
  stage text primary key,
  max_items int not null check (max_items > 0),
  note text
);

-- 행이 없는 단계는 무제한. 아이디어는 많이 쌓아 두는 게 정상이라 상한을 두지 않는다.
-- 필요해지면 행만 추가하면 된다. 예: insert into wip_limits values ('playtest', 5, '대표 플레이 대기');
insert into public.wip_limits(stage, max_items, note) values
  ('building', 1, '빌드는 한 번에 하나');

create table public.games (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) <= 48),
  title text not null check (length(title) between 1 and 80),
  pitch text not null check (length(pitch) between 1 and 300),
  core_verb text not null check (length(core_verb) between 1 and 60),
  fun_hypothesis text not null check (length(fun_hypothesis) between 1 and 300),
  stage text not null default 'idea'
    check (stage in ('idea','planning','ready','building','qa','playtest','kept','held','dropped')),
  attempt int not null default 0,
  starred boolean not null default false,
  spec jsonb,
  spec_version int not null default 0,
  fix_notes text,
  lease_owner text,
  lease_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  stage_changed_at timestamptz not null default now()
);
create index games_stage_idx on public.games(stage, starred desc, stage_changed_at);

create table public.builds (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  attempt int not null,
  commit_sha text not null check (commit_sha ~ '^[0-9a-f]{7,40}$'),
  smoke_passed boolean,  -- null: CI 결과 미확인
  notes text,
  created_at timestamptz not null default now()
);
create index builds_game_idx on public.builds(game_id, created_at desc);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  build_id uuid references public.builds(id) on delete set null,
  reviewer text not null check (reviewer in ('qa','ceo')),
  verdict text not null check (verdict in ('go','hold','drop','pass','fail','keep','fix')),
  checks jsonb,
  notes text,
  created_at timestamptz not null default now()
);
create index reviews_game_idx on public.reviews(game_id, created_at desc);

create table public.events (
  id bigint generated always as identity primary key,
  game_id uuid references public.games(id) on delete cascade,
  kind text not null,
  message text not null,
  created_at timestamptz not null default now()
);
create index events_time_idx on public.events(created_at desc);

create table public.runs (
  id uuid primary key default gen_random_uuid(),
  role text not null check (role in ('idea_lab','planner','builder','qa')),
  status text not null default 'running' check (status in ('running','success','noop','blocked','failed')),
  game_id uuid references public.games(id) on delete set null,
  summary text,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);
create index runs_role_idx on public.runs(role, started_at desc);

create table public.ceo_emails (
  email text primary key check (email = lower(email))
);

-- ---------------------------------------------------------------- 공개 읽기, 쓰기는 함수로만

alter table public.wip_limits enable row level security;
alter table public.games      enable row level security;
alter table public.builds     enable row level security;
alter table public.reviews    enable row level security;
alter table public.events     enable row level security;
alter table public.runs       enable row level security;
alter table public.ceo_emails enable row level security;

create policy read_all on public.wip_limits for select using (true);
create policy read_all on public.games      for select using (true);
create policy read_all on public.builds     for select using (true);
create policy read_all on public.reviews    for select using (true);
create policy read_all on public.events     for select using (true);
create policy read_all on public.runs       for select using (true);
-- ceo_emails: 정책 없음 → 브라우저에서 읽을 수 없음

revoke insert, update, delete, truncate on all tables in schema public from anon, authenticated;

-- ---------------------------------------------------------------- 공통

create function public.log_event(p_game uuid, p_kind text, p_message text)
returns void language sql security definer set search_path = public as $$
  insert into events(game_id, kind, message) values (p_game, p_kind, p_message);
$$;

create function public.on_stage_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if new.stage is distinct from old.stage then
    new.stage_changed_at := now();
    insert into events(game_id, kind, message)
    values (new.id, 'stage', format('%s: %s → %s', new.title, old.stage, new.stage));
  end if;
  return new;
end $$;

create trigger games_stage_change before update on public.games
for each row execute function public.on_stage_change();

create function public.has_room(p_stage text) returns boolean
language sql stable security definer set search_path = public as $$
  select (select count(*) from games where stage = p_stage)
       < coalesce((select max_items from wip_limits where stage = p_stage), 2147483647);
$$;

-- 대표 판단: 대시보드 로그인(ceo_emails 등록 메일) 또는 DB 직접 접속/service_role
create function public.is_ceo() returns boolean
language sql stable security definer set search_path = public as $$
  select session_user <> 'authenticator'
      or coalesce(auth.jwt()->>'role', '') = 'service_role'
      or exists (select 1 from ceo_emails where email = lower(coalesce(auth.jwt()->>'email', '')));
$$;

create function public.require_ceo() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_ceo() then
    raise exception '대표만 할 수 있습니다' using errcode = '42501';
  end if;
end $$;

create function public.lease_ok(g games, p_owner text) returns boolean
language sql immutable as $$
  select g.lease_owner = p_owner and g.lease_until > now();
$$;

-- ---------------------------------------------------------------- 작업 기록(출근부)

create function public.run_start(p_role text) returns uuid
language sql security definer set search_path = public as $$
  insert into runs(role) values (p_role) returning id;
$$;

create function public.run_finish(p_run uuid, p_status text, p_summary text, p_game uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_status not in ('success','noop','blocked','failed') then
    raise exception 'status는 success|noop|blocked|failed 중 하나';
  end if;
  update runs set status = p_status, summary = p_summary, game_id = coalesce(p_game, game_id), finished_at = now()
  where id = p_run;
  if not found then raise exception 'run % 없음', p_run; end if;
end $$;

-- ---------------------------------------------------------------- 아이디어 연구소

create function public.add_idea(p_slug text, p_title text, p_pitch text, p_core_verb text, p_fun text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not has_room('idea') then
    raise exception 'NO_ROOM: 대표 분류 대기가 꽉 찼습니다' using errcode = 'P0001';
  end if;
  insert into games(slug, title, pitch, core_verb, fun_hypothesis)
  values (p_slug, p_title, p_pitch, p_core_verb, p_fun)
  returning id into v_id;
  perform log_event(v_id, 'idea', format('새 아이디어: %s', p_title));
  return v_id;
end $$;

-- ---------------------------------------------------------------- 대표

-- 아이디어/보류 건 분류: go(기획으로) | hold | drop
create function public.ceo_triage(p_game uuid, p_decision text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare g games;
begin
  perform require_ceo();
  select * into g from games where id = p_game for update;
  if not found then raise exception '게임 없음'; end if;
  if g.stage not in ('idea','held') then
    raise exception '분류할 수 있는 단계가 아닙니다: %', g.stage;
  end if;
  if p_decision = 'go' then
    update games set stage = case when spec is null then 'planning' else 'ready' end,
                     lease_owner = null, lease_until = null,
                     fix_notes = coalesce(p_note, fix_notes)
    where id = p_game;
  elsif p_decision = 'hold' then
    update games set stage = 'held', lease_owner = null, lease_until = null where id = p_game;
  elsif p_decision = 'drop' then
    update games set stage = 'dropped', lease_owner = null, lease_until = null where id = p_game;
  else
    raise exception 'decision은 go|hold|drop 중 하나';
  end if;
  insert into reviews(game_id, reviewer, verdict, notes) values (p_game, 'ceo', p_decision, p_note);
end $$;

-- 플레이테스트 판정: keep(합격) | fix(고쳐서 다시) | drop
create function public.ceo_playtest(p_game uuid, p_verdict text, p_notes text default null)
returns void language plpgsql security definer set search_path = public as $$
declare g games; v_build uuid;
begin
  perform require_ceo();
  select * into g from games where id = p_game for update;
  if not found then raise exception '게임 없음'; end if;
  if g.stage <> 'playtest' then raise exception '플레이테스트 단계가 아닙니다: %', g.stage; end if;
  select id into v_build from builds where game_id = p_game order by created_at desc limit 1;

  if p_verdict = 'keep' then
    update games set stage = 'kept' where id = p_game;
  elsif p_verdict = 'fix' then
    if coalesce(trim(p_notes), '') = '' then raise exception '무엇을 고칠지 적어 주세요'; end if;
    update games set stage = 'ready', fix_notes = p_notes where id = p_game;
  elsif p_verdict = 'drop' then
    update games set stage = 'dropped' where id = p_game;
  else
    raise exception 'verdict는 keep|fix|drop 중 하나';
  end if;
  insert into reviews(game_id, build_id, reviewer, verdict, notes) values (p_game, v_build, 'ceo', p_verdict, p_notes);
end $$;

create function public.ceo_star(p_game uuid, p_starred boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform require_ceo();
  update games set starred = p_starred where id = p_game;
end $$;

-- ---------------------------------------------------------------- 작업 가져가기

-- role: planner | builder | qa
-- 다음 단계에 자리가 없으면 아무것도 돌려주지 않는다(= 오늘은 쉼).
create function public.claim(p_role text, p_owner text, p_minutes int default 50)
returns setof games language plpgsql security definer set search_path = public as $$
declare g games;
begin
  if p_role = 'planner' then
    if not has_room('ready') then return; end if;
    select * into g from games
     where stage = 'planning' and (lease_until is null or lease_until < now())
     order by starred desc, stage_changed_at limit 1 for update skip locked;
    if not found then return; end if;
    update games set lease_owner = p_owner, lease_until = now() + make_interval(mins => p_minutes)
     where id = g.id returning * into g;

  elsif p_role = 'builder' then
    -- 멈춘 빌드(임대 만료)를 먼저 이어받는다
    select * into g from games
     where stage = 'building' and lease_until < now()
     order by stage_changed_at limit 1 for update skip locked;
    if found then
      update games set lease_owner = p_owner, lease_until = now() + make_interval(mins => p_minutes)
       where id = g.id returning * into g;
    else
      if not has_room('building') or not has_room('qa') then return; end if;
      select * into g from games
       where stage = 'ready'
       order by starred desc, stage_changed_at limit 1 for update skip locked;
      if not found then return; end if;
      update games set stage = 'building', attempt = attempt + 1,
                       lease_owner = p_owner, lease_until = now() + make_interval(mins => p_minutes)
       where id = g.id returning * into g;
    end if;

  elsif p_role = 'qa' then
    if not has_room('playtest') then return; end if;
    select * into g from games
     where stage = 'qa' and (lease_until is null or lease_until < now())
     order by starred desc, stage_changed_at limit 1 for update skip locked;
    if not found then return; end if;
    update games set lease_owner = p_owner, lease_until = now() + make_interval(mins => p_minutes)
     where id = g.id returning * into g;

  else
    raise exception 'role은 planner|builder|qa 중 하나';
  end if;
  return next g;
end $$;

-- 운영 장애(네트워크, 권한, 도구 오류)로 중단할 때. 게임 상태는 그대로 두고 임대만 푼다.
create function public.release(p_game uuid, p_owner text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare g games;
begin
  select * into g from games where id = p_game for update;
  if not found or g.lease_owner is distinct from p_owner then raise exception '임대 소유자가 아닙니다'; end if;
  if g.stage = 'building' then
    update games set stage = 'ready', attempt = greatest(attempt - 1, 0), lease_owner = null, lease_until = null where id = p_game;
  else
    update games set lease_owner = null, lease_until = null where id = p_game;
  end if;
  perform log_event(p_game, 'release', format('%s 작업 중단(운영): %s', g.title, p_reason));
end $$;

-- 게임 자체의 문제로 진행 불가할 때(기획이 모순, 구현 불가 등). 대표 판단으로 넘긴다.
create function public.escalate(p_game uuid, p_owner text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare g games;
begin
  select * into g from games where id = p_game for update;
  if not found or not lease_ok(g, p_owner) then raise exception '유효한 임대가 없습니다'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception '사유가 필요합니다'; end if;
  update games set stage = 'held', fix_notes = p_reason, lease_owner = null, lease_until = null where id = p_game;
  perform log_event(p_game, 'held', format('%s 대표 판단 필요: %s', g.title, p_reason));
end $$;

-- ---------------------------------------------------------------- 기획실

-- 한 장 기획서 검증 규칙은 docs/OPERATING_MODEL.md와 같다.
create function public.validate_spec(p jsonb) returns text[]
language plpgsql immutable as $$
declare errs text[] := '{}'; item jsonb; ids text[] := '{}'; n int;
begin
  if jsonb_typeof(p) <> 'object' then return array['spec은 객체여야 합니다']; end if;
  if coalesce(p->>'one_liner', '') = '' then errs := errs || 'one_liner 필요'; end if;
  if coalesce(p->>'orientation', '') not in ('portrait','landscape') then errs := errs || 'orientation은 portrait|landscape'; end if;
  if coalesce(p->>'controls', '') = '' then errs := errs || 'controls 필요'; end if;
  if coalesce(p->>'win_lose', '') = '' then errs := errs || 'win_lose 필요'; end if;

  if jsonb_typeof(p->'screens') <> 'array' then errs := errs || 'screens 배열 필요';
  else
    n := jsonb_array_length(p->'screens');
    if n < 1 or n > 4 then errs := errs || format('screens는 1~4개 (지금 %s)', n); end if;
  end if;

  if jsonb_typeof(p->'must_work') <> 'array' then errs := errs || 'must_work 배열 필요';
  else
    n := jsonb_array_length(p->'must_work');
    if n < 3 or n > 10 then errs := errs || format('must_work는 3~10개 (지금 %s)', n); end if;
    for item in select * from jsonb_array_elements(p->'must_work') loop
      if coalesce(item->>'id', '') !~ '^M[0-9]+$' then errs := errs || format('must_work id 형식 오류: %s', item->>'id');
      elsif (item->>'id') = any(ids) then errs := errs || format('must_work id 중복: %s', item->>'id');
      else ids := ids || (item->>'id'); end if;
      if coalesce(item->>'text', '') = '' then errs := errs || format('%s: text 필요', item->>'id'); end if;
      if coalesce(item->>'check', '') = '' then errs := errs || format('%s: check(확인 방법) 필요', item->>'id'); end if;
    end loop;
  end if;

  if p ? 'not_now' and jsonb_typeof(p->'not_now') <> 'array' then errs := errs || 'not_now는 배열'; end if;
  return errs;
end $$;

create function public.submit_spec(p_game uuid, p_owner text, p_spec jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare g games; errs text[];
begin
  select * into g from games where id = p_game for update;
  if not found or g.stage <> 'planning' or not lease_ok(g, p_owner) then
    raise exception '기획 임대가 없습니다';
  end if;
  errs := validate_spec(p_spec);
  if array_length(errs, 1) > 0 then
    raise exception 'SPEC_INVALID: %', array_to_string(errs, ' / ');
  end if;
  update games set spec = p_spec, spec_version = spec_version + 1, stage = 'ready',
                   lease_owner = null, lease_until = null
   where id = p_game;
end $$;

-- ---------------------------------------------------------------- 빌드실

-- p_smoke_passed: 빌더가 직접 tools/smoke.py를 돌렸으면 그 결과, 못 돌렸으면 null(검수실이 CI 결과로 확정).
-- false면 검수로 넘기지 않고 빌드 대기로 되돌린다(3회째면 대표 판단).
create function public.submit_build(p_game uuid, p_owner text, p_commit text, p_smoke_passed boolean, p_notes text)
returns uuid language plpgsql security definer set search_path = public as $$
declare g games; v_build uuid;
begin
  select * into g from games where id = p_game for update;
  if not found or g.stage <> 'building' or not lease_ok(g, p_owner) then
    raise exception '빌드 임대가 없습니다';
  end if;
  insert into builds(game_id, attempt, commit_sha, smoke_passed, notes)
  values (p_game, g.attempt, lower(p_commit), p_smoke_passed, p_notes) returning id into v_build;

  if p_smoke_passed is not false then
    update games set stage = 'qa', lease_owner = null, lease_until = null where id = p_game;
    perform log_event(p_game, 'build', format('%s 빌드 %s회차 · %s', g.title, g.attempt, left(lower(p_commit), 7)));
  elsif g.attempt >= 3 then
    update games set stage = 'held', fix_notes = coalesce(p_notes, '자동 검사 3회 실패'),
                     lease_owner = null, lease_until = null where id = p_game;
  else
    update games set stage = 'ready', fix_notes = coalesce(p_notes, fix_notes),
                     lease_owner = null, lease_until = null where id = p_game;
  end if;
  return v_build;
end $$;

-- ---------------------------------------------------------------- 검수실

-- checks: [{"id":"M1","ok":true,"note":"..."}] — 기획서 must_work 전부를 덮어야 한다.
-- p_ci_passed: 최신 빌드 커밋에 대한 GitHub Actions "ci" 결과. 검수실이 확인해서 기록한다.
-- pass 조건: CI 통과 + 모든 항목 ok.
create function public.submit_qa(p_game uuid, p_owner text, p_verdict text, p_ci_passed boolean, p_checks jsonb, p_notes text)
returns void language plpgsql security definer set search_path = public as $$
declare g games; b builds; required text[]; given text[]; missing text[]; failed text[];
begin
  select * into g from games where id = p_game for update;
  if not found or g.stage <> 'qa' or not lease_ok(g, p_owner) then
    raise exception '검수 임대가 없습니다';
  end if;
  select * into b from builds where game_id = p_game order by created_at desc limit 1;
  if not found then raise exception '빌드 기록이 없습니다'; end if;
  if p_ci_passed is null then raise exception 'CI 결과를 확인한 뒤 제출하세요'; end if;
  update builds set smoke_passed = p_ci_passed where id = b.id;
  b.smoke_passed := p_ci_passed;

  if jsonb_typeof(p_checks) <> 'array' then raise exception 'checks는 배열'; end if;
  select array_agg(x->>'id') into required from jsonb_array_elements(g.spec->'must_work') x;
  select array_agg(x->>'id') into given from jsonb_array_elements(p_checks) x;
  select array_agg(r) into missing from unnest(required) r where r <> all(coalesce(given, '{}'));
  if missing is not null then raise exception 'CHECKS_MISSING: %', array_to_string(missing, ', '); end if;
  select array_agg(x->>'id') into failed from jsonb_array_elements(p_checks) x where (x->>'ok')::boolean is not true;

  if p_verdict = 'pass' then
    if not b.smoke_passed then raise exception 'CI를 통과하지 못한 빌드는 합격시킬 수 없습니다'; end if;
    if failed is not null then raise exception '실패 항목이 있으면 합격시킬 수 없습니다: %', array_to_string(failed, ', '); end if;
    update games set stage = 'playtest', fix_notes = null, lease_owner = null, lease_until = null where id = p_game;
  elsif p_verdict = 'fail' then
    if failed is null and coalesce(trim(p_notes), '') = '' then
      raise exception '불합격이면 실패 항목이나 사유가 있어야 합니다';
    end if;
    update games set stage = case when attempt >= 3 then 'held' else 'ready' end,
                     fix_notes = p_notes, lease_owner = null, lease_until = null
     where id = p_game;
  else
    raise exception 'verdict는 pass|fail';
  end if;
  insert into reviews(game_id, build_id, reviewer, verdict, checks, notes)
  values (p_game, b.id, 'qa', p_verdict, p_checks, p_notes);
end $$;

-- ---------------------------------------------------------------- 권한

do $$
declare f text;
begin
  -- 워커 함수: service_role(및 DB 직접 접속)만
  foreach f in array array[
    'log_event(uuid,text,text)', 'run_start(text)', 'run_finish(uuid,text,text,uuid)',
    'add_idea(text,text,text,text,text)', 'claim(text,text,int)', 'release(uuid,text,text)',
    'escalate(uuid,text,text)', 'submit_spec(uuid,text,jsonb)', 'submit_build(uuid,text,text,boolean,text)',
    'submit_qa(uuid,text,text,boolean,jsonb,text)', 'has_room(text)', 'require_ceo()', 'on_stage_change()'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
  -- 대표 함수: 로그인 사용자만 호출 가능, 안에서 ceo_emails 확인
  foreach f in array array[
    'ceo_triage(uuid,text,text)', 'ceo_playtest(uuid,text,text)', 'ceo_star(uuid,boolean)', 'is_ceo()'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
end $$;
