-- 디자인실 추가: 기획은 깊게(디자인실), 첫 빌드 범위는 좁게(기획실).
--
-- idea ─디자인실─▶ designing ─▶ designed ─기획실─▶ planning ─▶ ready ─빌드실─▶ building ─▶ qa ─검수실─▶ playtest
--
-- - 디자인실: games/<slug>/design/GAME_DESIGN.md, design/sim/, design/ROADMAP.md 를 커밋하고 submit_design.
-- - 기획실: design/FIRST_BUILD.md, design/SCREENS.md, design/spec.json, tests/smoke.gd 를 커밋하고 submit_spec.
--   smoke.gd의 sha256을 함께 저장한다. 빌드실은 이 파일을 바꿀 수 없다(빌드/검수 제출 때 해시 대조).
-- - 빌드실/검수실/기획실은 규칙·검사·설계 자체가 틀렸으면 send_back으로 앞 부서에 반송한다(3회째면 held).

-- ---------------------------------------------------------------- 단계, 역할, 컬럼

alter table public.games drop constraint games_stage_check;
alter table public.games add constraint games_stage_check check (stage in
  ('idea','designing','designed','planning','ready','building','qa','playtest','kept','held','dropped'));

alter table public.runs drop constraint runs_role_check;
alter table public.runs add constraint runs_role_check check (role in ('idea_lab','designer','planner','builder','qa'));

alter table public.games
  add column design_commit text check (design_commit is null or design_commit ~ '^[0-9a-f]{7,40}$'),
  add column design_version int not null default 0,
  add column design_summary text check (design_summary is null or length(design_summary) <= 800),
  add column sim_status text check (sim_status is null or sim_status in ('passed','skipped')),
  add column spec_commit text check (spec_commit is null or spec_commit ~ '^[0-9a-f]{7,40}$'),
  add column tests_sha256 text check (tests_sha256 is null or tests_sha256 ~ '^[0-9a-f]{64}$'),
  add column bounces int not null default 0;

-- ---------------------------------------------------------------- 작업 가져가기

create or replace function public.claim(p_role text, p_owner text, p_minutes int default 50)
returns setof games language plpgsql security definer set search_path = public as $$
declare g games;
begin
  if p_role = 'designer' then
    -- 순서: ★ → 중단된 디자인(임대 만료) → 아이디어가 들어온 순
    select * into g from games
     where stage = 'idea'
        or (stage = 'designing' and (lease_until is null or lease_until < now()))
     order by starred desc, (stage = 'designing') desc, created_at limit 1 for update skip locked;
    if not found then return; end if;
    update games set stage = 'designing', lease_owner = p_owner, lease_until = now() + make_interval(mins => p_minutes)
     where id = g.id returning * into g;

  elsif p_role = 'planner' then
    if not has_room('ready') then return; end if;
    -- 순서: ★ → 중단된 기획(임대 만료) → 디자인이 끝난 순
    select * into g from games
     where stage = 'designed'
        or (stage = 'planning' and (lease_until is null or lease_until < now()))
     order by starred desc, (stage = 'planning') desc, stage_changed_at limit 1 for update skip locked;
    if not found then return; end if;
    update games set stage = 'planning', lease_owner = p_owner, lease_until = now() + make_interval(mins => p_minutes)
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
    raise exception 'role은 designer|planner|builder|qa 중 하나';
  end if;
  return next g;
end $$;

-- ---------------------------------------------------------------- 디자인실

-- p_summary: 대표가 대시보드에서 읽을 3~6줄 요약 (무슨 게임인지, 핵심 판단, 시뮬레이션 결론)
-- p_sim_status: passed(규칙 시뮬레이션으로 검증) | skipped(시뮬레이션이 의미 없는 장르, 사유는 문서에)
create function public.submit_design(p_game uuid, p_owner text, p_commit text, p_summary text, p_sim_status text)
returns void language plpgsql security definer set search_path = public as $$
declare g games;
begin
  select * into g from games where id = p_game for update;
  if not found or g.stage <> 'designing' or not lease_ok(g, p_owner) then
    raise exception '디자인 임대가 없습니다';
  end if;
  if coalesce(trim(p_summary), '') = '' then raise exception '요약이 필요합니다'; end if;
  if p_sim_status not in ('passed','skipped') then raise exception 'sim_status는 passed|skipped'; end if;
  update games set stage = 'designed', design_commit = lower(p_commit), design_version = design_version + 1,
                   design_summary = p_summary, sim_status = p_sim_status, fix_notes = null,
                   lease_owner = null, lease_until = null
   where id = p_game;
  perform log_event(p_game, 'design', format('%s 디자인 v%s · %s', g.title, g.design_version + 1, left(lower(p_commit), 7)));
end $$;

-- ---------------------------------------------------------------- 기획실

-- 첫 빌드 범위는 must_work 3~12개.
create or replace function public.validate_spec(p jsonb) returns text[]
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
    if n < 1 or n > 6 then errs := errs || format('screens는 1~6개 (지금 %s)', n); end if;
  end if;

  if jsonb_typeof(p->'must_work') <> 'array' then errs := errs || 'must_work 배열 필요';
  else
    n := jsonb_array_length(p->'must_work');
    if n < 3 or n > 12 then errs := errs || format('must_work는 3~12개 (지금 %s)', n); end if;
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

drop function public.submit_spec(uuid, text, jsonb);

-- p_commit: 기획 패키지(design/FIRST_BUILD.md, SCREENS.md, spec.json, tests/smoke.gd) 커밋
-- p_tests_sha256: 그 커밋의 games/<slug>/tests/smoke.gd sha256 (python tools/check_design.py가 출력)
create function public.submit_spec(p_game uuid, p_owner text, p_spec jsonb, p_commit text, p_tests_sha256 text)
returns void language plpgsql security definer set search_path = public as $$
declare g games; errs text[];
begin
  select * into g from games where id = p_game for update;
  if not found or g.stage <> 'planning' or not lease_ok(g, p_owner) then
    raise exception '기획 임대가 없습니다';
  end if;
  if g.design_commit is null then raise exception '디자인 문서가 없는 게임입니다'; end if;
  errs := validate_spec(p_spec);
  if coalesce(p_commit, '') !~ '^[0-9a-fA-F]{7,40}$' then errs := errs || 'commit 형식 오류'; end if;
  if coalesce(p_tests_sha256, '') !~ '^[0-9a-fA-F]{64}$' then errs := errs || 'tests_sha256는 64자리 hex'; end if;
  if array_length(errs, 1) > 0 then
    raise exception 'SPEC_INVALID: %', array_to_string(errs, ' / ');
  end if;
  update games set spec = p_spec, spec_version = spec_version + 1, spec_commit = lower(p_commit),
                   tests_sha256 = lower(p_tests_sha256), stage = 'ready', attempt = 0, fix_notes = null,
                   lease_owner = null, lease_until = null
   where id = p_game;
  perform log_event(p_game, 'spec', format('%s 기획 v%s · must_work %s개 · %s', g.title, g.spec_version + 1,
                    jsonb_array_length(p_spec->'must_work'), left(lower(p_commit), 7)));
end $$;

-- ---------------------------------------------------------------- 반송

-- 앞 부서의 산출물 자체가 틀렸을 때(규칙 모순, 검사가 규칙과 다름, 구현 불가 범위).
-- p_to: 'planner'(기획 패키지 수정) | 'designer'(디자인 수정). 같은 게임이 3번째 반송되면 held.
create function public.send_back(p_game uuid, p_owner text, p_to text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare g games; v_stage text;
begin
  select * into g from games where id = p_game for update;
  if not found or g.stage not in ('planning','building','qa') or not lease_ok(g, p_owner) then
    raise exception '반송할 수 있는 임대가 없습니다';
  end if;
  if coalesce(trim(p_reason), '') = '' then raise exception '반송 사유가 필요합니다'; end if;
  if p_to = 'designer' then v_stage := 'idea';
  elsif p_to = 'planner' and g.stage <> 'planning' then v_stage := 'designed';
  else raise exception 'p_to는 designer|planner (기획실은 designer로만)';
  end if;
  if g.bounces >= 2 then v_stage := 'held'; end if;
  update games set stage = v_stage, bounces = bounces + 1, attempt = 0,
                   fix_notes = format('[%s 반송 · %s] %s', g.stage, p_to, p_reason),
                   lease_owner = null, lease_until = null
   where id = p_game;
  perform log_event(p_game, 'send_back', format('%s %s → %s: %s', g.title, g.stage, v_stage, p_reason));
end $$;

-- ---------------------------------------------------------------- 빌드/검수: 검사 파일 해시 대조

drop function public.submit_build(uuid, text, text, boolean, text);

create function public.submit_build(p_game uuid, p_owner text, p_commit text, p_smoke_passed boolean, p_notes text,
                                    p_tests_sha256 text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare g games; v_build uuid;
begin
  select * into g from games where id = p_game for update;
  if not found or g.stage <> 'building' or not lease_ok(g, p_owner) then
    raise exception '빌드 임대가 없습니다';
  end if;
  if g.tests_sha256 is not null and p_tests_sha256 is distinct from g.tests_sha256 then
    raise exception 'TESTS_CHANGED: tests/smoke.gd가 기획실 버전과 다릅니다. 검사 파일은 바꿀 수 없습니다 (틀렸다면 send_back)';
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

drop function public.submit_qa(uuid, text, text, boolean, jsonb, text);

create function public.submit_qa(p_game uuid, p_owner text, p_verdict text, p_ci_passed boolean, p_checks jsonb, p_notes text,
                                 p_tests_sha256 text default null)
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
    if g.tests_sha256 is not null and p_tests_sha256 is distinct from g.tests_sha256 then
      raise exception 'TESTS_CHANGED: 빌드 커밋의 tests/smoke.gd가 기획실 버전과 다릅니다';
    end if;
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

-- ---------------------------------------------------------------- 대표: 판단 필요 건을 다시 흐름에

create or replace function public.ceo_triage(p_game uuid, p_decision text, p_note text default null)
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
    if g.stage = 'idea' then
      update games set starred = true, fix_notes = coalesce(p_note, fix_notes) where id = p_game;
    else
      -- 판단 필요 건: 가장 앞선 산출물이 있는 단계로 되돌린다. 반송 횟수는 초기화.
      update games set stage = case when spec is not null then 'ready'
                                    when design_commit is not null then 'designed'
                                    else 'idea' end,
                       bounces = 0, attempt = 0,
                       lease_owner = null, lease_until = null,
                       fix_notes = coalesce(p_note, fix_notes)
       where id = p_game;
    end if;
  elsif p_decision = 'hold' then
    update games set stage = 'held', lease_owner = null, lease_until = null where id = p_game;
  elsif p_decision = 'drop' then
    update games set stage = 'dropped', lease_owner = null, lease_until = null where id = p_game;
  else
    raise exception 'decision은 go|hold|drop 중 하나';
  end if;
  insert into reviews(game_id, reviewer, verdict, notes) values (p_game, 'ceo', p_decision, p_note);
end $$;

-- ---------------------------------------------------------------- 권한

do $$
declare f text;
begin
  foreach f in array array[
    'submit_design(uuid,text,text,text,text)', 'submit_spec(uuid,text,jsonb,text,text)',
    'send_back(uuid,text,text,text)', 'submit_build(uuid,text,text,boolean,text,text)',
    'submit_qa(uuid,text,text,boolean,jsonb,text,text)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end $$;
