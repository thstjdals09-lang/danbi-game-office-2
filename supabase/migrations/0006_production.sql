-- 합격 뒤의 프로덕션(본 개발) 루프와 대표 결정 요청.
--
-- 합격(kept)은 끝이 아니라 "로드맵의 다음 조각으로 넘어간다"는 뜻이다.
--   kept ─프로덕션 디자인실─▶ designing(차수+1) ─▶ designed ─프로덕션 기획실─▶ planning ─▶ ready
--        ─프로덕션 개발실─▶ building ─▶ qa ─검수실─▶ playtest ─대표─▶ kept(다시) | done(여기까지)
--
-- 단계(stage)는 "어디에 있나", 차수(milestone)는 "몇 번째 빌드인가"다.
-- 같은 단계라도 차수 1은 프로토타입 부서(디자인실·기획실·빌드실)가, 차수 2 이상은 프로덕션 부서가 가져간다.
-- 그래서 부서 프롬프트 안에서 "첫 빌드면 …, 2차면 …" 하고 경우를 나누지 않는다.

alter table public.games drop constraint games_stage_check;
alter table public.games add constraint games_stage_check check (stage in
  ('idea','designing','designed','planning','ready','building','qa','playtest','kept','held','dropped','done'));

alter table public.runs drop constraint runs_role_check;
alter table public.runs add constraint runs_role_check check (role in
  ('idea_lab','designer','planner','builder','qa','artist','prod_designer','prod_planner','prod_developer'));

alter table public.games
  add column milestone int not null default 1 check (milestone >= 1),
  add column keep_notes text;

-- ---------------------------------------------------------------- 대표 결정 요청
-- 부서가 선택지를 2~4개로 추리고 추천을 달아 올린다. 대표는 고르기만 한다.
-- 결정을 기다리느라 공장이 멈추지는 않는다: 결정 전에는 추천안을 가정하고 진행하되, 가정했다는 것을 문서에 적는다.

create table public.decisions (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  topic text not null check (length(topic) between 1 and 40),        -- 예: business_model
  question text not null check (length(question) between 1 and 300),
  options jsonb not null,                                            -- [{"id","label","detail","pros","cons"}]
  recommended text not null,
  reason text,                                                       -- 추천 이유
  asked_by text not null,
  chosen text,
  note text,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  unique (game_id, topic)
);
alter table public.decisions enable row level security;
create policy read_all on public.decisions for select using (true);
revoke insert, update, delete, truncate on public.decisions from anon, authenticated;

-- 같은 게임·같은 주제는 하나만 둔다. 아직 결정 전이면 새 선택지로 바꾸고, 이미 결정됐으면 그대로 둔다(결정을 뒤엎지 않는다).
create function public.ask_decision(p_game uuid, p_asked_by text, p_topic text, p_question text,
                                    p_options jsonb, p_recommended text, p_reason text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; item jsonb; ids text[] := '{}'; n int; d decisions;
begin
  if jsonb_typeof(p_options) <> 'array' then raise exception 'options는 배열'; end if;
  n := jsonb_array_length(p_options);
  if n < 2 or n > 4 then raise exception 'DECISION_INVALID: 선택지는 2~4개 (지금 %)', n; end if;
  for item in select * from jsonb_array_elements(p_options) loop
    if coalesce(item->>'id', '') = '' or coalesce(item->>'label', '') = '' or coalesce(item->>'detail', '') = '' then
      raise exception 'DECISION_INVALID: 선택지마다 id, label, detail 필요';
    end if;
    ids := ids || (item->>'id');
  end loop;
  if not (p_recommended = any(ids)) then raise exception 'DECISION_INVALID: recommended는 선택지 id 중 하나'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'DECISION_INVALID: 추천 이유 필요'; end if;

  select * into d from decisions where game_id = p_game and topic = p_topic;
  if found then
    if d.chosen is not null then return d.id; end if;
    update decisions set question = p_question, options = p_options, recommended = p_recommended,
                         reason = p_reason, asked_by = p_asked_by, created_at = now()
     where id = d.id;
    return d.id;
  end if;
  insert into decisions(game_id, topic, question, options, recommended, reason, asked_by)
  values (p_game, p_topic, p_question, p_options, p_recommended, p_reason, p_asked_by) returning id into v_id;
  perform log_event(p_game, 'decision', format('대표 결정 요청: %s', p_question));
  return v_id;
end $$;

create function public.ceo_decide(p_decision uuid, p_choice text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare d decisions;
begin
  perform require_ceo();
  select * into d from decisions where id = p_decision for update;
  if not found then raise exception '결정 요청 없음'; end if;
  if not exists (select 1 from jsonb_array_elements(d.options) x where x->>'id' = p_choice) then
    raise exception '선택지에 없는 값: %', p_choice;
  end if;
  update decisions set chosen = p_choice, note = p_note, decided_at = now() where id = p_decision;
  perform log_event(d.game_id, 'decision', format('대표 결정: %s → %s', d.question, p_choice));
end $$;

-- ---------------------------------------------------------------- 대표: 합격 메모 저장, 여기까지

create or replace function public.ceo_playtest(p_game uuid, p_verdict text, p_notes text default null)
returns void language plpgsql security definer set search_path = public as $$
declare g games; v_build uuid;
begin
  perform require_ceo();
  select * into g from games where id = p_game for update;
  if not found then raise exception '게임 없음'; end if;
  if g.stage <> 'playtest' then raise exception '플레이테스트 단계가 아닙니다: %', g.stage; end if;
  select id into v_build from builds where game_id = p_game order by created_at desc limit 1;

  if p_verdict = 'keep' then
    -- 합격: 로드맵의 다음 조각으로. 메모는 프로덕션 디자인실이 가장 먼저 읽는다.
    update games set stage = 'kept', keep_notes = p_notes where id = p_game;
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

-- 여기까지: 더 키우지 않는다(완성 또는 보관). 플레이 대기·합격 상태에서만.
create function public.ceo_finish(p_game uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare g games;
begin
  perform require_ceo();
  select * into g from games where id = p_game for update;
  if not found then raise exception '게임 없음'; end if;
  if g.stage not in ('playtest','kept') then raise exception '플레이 대기·합격 상태에서만 끝낼 수 있습니다: %', g.stage; end if;
  update games set stage = 'done', keep_notes = coalesce(p_note, keep_notes), lease_owner = null, lease_until = null where id = p_game;
  insert into reviews(game_id, reviewer, verdict, notes) values (p_game, 'ceo', 'hold', coalesce(p_note, '여기까지'));
end $$;

-- ---------------------------------------------------------------- 작업 가져가기: 차수로 부서를 나눈다

create or replace function public.claim(p_role text, p_owner text, p_minutes int default 50)
returns setof games language plpgsql security definer set search_path = public as $$
declare g games; v_prod boolean := p_role like 'prod\_%';
begin
  if p_role = 'designer' then
    -- 첫 디자인: ★ → 중단된 디자인 → 아이디어가 들어온 순
    select * into g from games
     where milestone = 1 and (stage = 'idea' or (stage = 'designing' and (lease_until is null or lease_until < now())))
     order by starred desc, (stage = 'designing') desc, created_at limit 1 for update skip locked;
    if not found then return; end if;
    update games set stage = 'designing', lease_owner = p_owner, lease_until = now() + make_interval(mins => p_minutes)
     where id = g.id returning * into g;

  elsif p_role = 'prod_designer' then
    -- 프로덕션 디자인: 중단된 것 먼저, 그다음 합격한 순. 합격작을 가져갈 때 차수가 1 오른다.
    select * into g from games
     where (stage = 'designing' and milestone >= 2 and (lease_until is null or lease_until < now()))
        or stage = 'kept'
     order by (stage = 'designing') desc, starred desc, stage_changed_at limit 1 for update skip locked;
    if not found then return; end if;
    update games set milestone = case when g.stage = 'kept' then milestone + 1 else milestone end,
                     bounces = case when g.stage = 'kept' then 0 else bounces end,
                     stage = 'designing', lease_owner = p_owner, lease_until = now() + make_interval(mins => p_minutes)
     where id = g.id returning * into g;

  elsif p_role in ('planner', 'prod_planner') then
    if not has_room('ready') then return; end if;
    select * into g from games
     where (milestone >= 2) = v_prod
       and (stage = 'designed' or (stage = 'planning' and (lease_until is null or lease_until < now())))
     order by starred desc, (stage = 'planning') desc, stage_changed_at limit 1 for update skip locked;
    if not found then return; end if;
    update games set stage = 'planning', lease_owner = p_owner, lease_until = now() + make_interval(mins => p_minutes)
     where id = g.id returning * into g;

  elsif p_role in ('builder', 'prod_developer') then
    -- 멈춘 빌드(임대 만료)를 먼저 이어받는다
    select * into g from games
     where (milestone >= 2) = v_prod and stage = 'building' and lease_until < now()
     order by stage_changed_at limit 1 for update skip locked;
    if found then
      update games set lease_owner = p_owner, lease_until = now() + make_interval(mins => p_minutes)
       where id = g.id returning * into g;
    else
      if not has_room('building') or not has_room('qa') then return; end if;
      select * into g from games
       where (milestone >= 2) = v_prod and stage = 'ready'
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
    raise exception 'role은 designer|planner|builder|prod_designer|prod_planner|prod_developer|qa 중 하나';
  end if;
  return next g;
end $$;

-- 반송: 차수 2 이상에서 디자인으로 돌려보낼 때는 차수를 유지한 채 "중단된 디자인"으로 둔다(프로덕션 디자인실이 이어받는다).
create or replace function public.send_back(p_game uuid, p_owner text, p_to text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare g games; v_stage text;
begin
  select * into g from games where id = p_game for update;
  if not found or g.stage not in ('planning','building','qa') or not lease_ok(g, p_owner) then
    raise exception '반송할 수 있는 임대가 없습니다';
  end if;
  if coalesce(trim(p_reason), '') = '' then raise exception '반송 사유가 필요합니다'; end if;
  if p_to = 'designer' then v_stage := case when g.milestone >= 2 then 'designing' else 'idea' end;
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

-- ---------------------------------------------------------------- 권한

do $$
begin
  revoke execute on function public.ask_decision(uuid,text,text,text,jsonb,text,text) from public, anon, authenticated;
  grant execute on function public.ask_decision(uuid,text,text,text,jsonb,text,text) to service_role;
  revoke execute on function public.ceo_decide(uuid,text,text) from public, anon;
  grant execute on function public.ceo_decide(uuid,text,text) to authenticated, service_role;
  revoke execute on function public.ceo_finish(uuid,text) from public, anon;
  grant execute on function public.ceo_finish(uuid,text) to authenticated, service_role;
end $$;
