-- 기획실이 대표 승인 없이 아이디어를 가져간다.
-- 대표의 분류는 게이트가 아니라 우선순위다:
--   go(만들자) = ★ 우선 처리, hold = 보류(가져가지 않음), drop = 버림.
-- stage 'planning'은 이제 "기획 중"(임대 보유)을 뜻한다.

create or replace function public.claim(p_role text, p_owner text, p_minutes int default 50)
returns setof games language plpgsql security definer set search_path = public as $$
declare g games;
begin
  if p_role = 'planner' then
    if not has_room('ready') then return; end if;
    -- 대표 승인 없이 아이디어 대기에서 바로 가져간다.
    -- 순서: ★(starred) → 중단된 기획(임대 만료) → 아이디어가 들어온 순.
    select * into g from games
     where stage = 'idea'
        or (stage = 'planning' and (lease_until is null or lease_until < now()))
     order by starred desc, (stage = 'planning') desc, created_at limit 1 for update skip locked;
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
    raise exception 'role은 planner|builder|qa 중 하나';
  end if;
  return next g;
end $$;


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
      -- 아이디어: 우선 처리 표시만 한다. 기획실이 먼저 가져간다.
      update games set starred = true, fix_notes = coalesce(p_note, fix_notes) where id = p_game;
    else
      -- 보류/판단 필요 건: 다시 흐름에 넣는다.
      update games set stage = case when spec is null then 'idea' else 'ready' end,
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
