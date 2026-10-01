-- 아트실: 검수를 통과한 게임의 핵심 화면 하나를 골라 아트 방향 3가지(A·B·C) 이미지를 만든다.
-- 제작 흐름(단계)을 막지 않는 옆 작업이다. 플레이 대기·합격작 중 아직 아트가 없는 게임을 가져간다.
--
-- games.art 형식:
-- {
--   "key_screen": "shots/07-floor3-intents.png",        -- 고른 핵심 화면(게임 폴더 기준 경로)
--   "key_reason": "왜 이 화면인지 한두 문장",
--   "directions": [
--     {"id": "A", "name": "먹선 대나무 숲", "description": "분위기·색·재질 한두 문장", "image": "art/A.png"},
--     {"id": "B", ...}, {"id": "C", ...}
--   ]
-- }

alter table public.runs drop constraint runs_role_check;
alter table public.runs add constraint runs_role_check check (role in ('idea_lab','designer','planner','builder','qa','artist'));

alter table public.games
  add column art jsonb,
  add column art_commit text check (art_commit is null or art_commit ~ '^[0-9a-f]{7,40}$'),
  add column art_pick text check (art_pick is null or art_pick in ('A','B','C')),
  add column art_lease_owner text,
  add column art_lease_until timestamptz;

-- 순서: ★ → 플레이 대기에 먼저 온 순
create function public.claim_art(p_owner text, p_minutes int default 60)
returns setof games language plpgsql security definer set search_path = public as $$
declare g games;
begin
  select * into g from games
   where stage in ('playtest','kept') and art is null
     and (art_lease_until is null or art_lease_until < now())
   order by starred desc, stage_changed_at limit 1 for update skip locked;
  if not found then return; end if;
  update games set art_lease_owner = p_owner, art_lease_until = now() + make_interval(mins => p_minutes)
   where id = g.id returning * into g;
  return next g;
end $$;

create function public.validate_art(p jsonb) returns text[]
language plpgsql immutable as $$
declare errs text[] := '{}'; item jsonb; ids text[] := '{}';
begin
  if jsonb_typeof(p) <> 'object' then return array['art는 객체여야 합니다']; end if;
  if coalesce(p->>'key_screen', '') = '' then errs := errs || 'key_screen 필요'; end if;
  if coalesce(p->>'key_reason', '') = '' then errs := errs || 'key_reason 필요'; end if;
  if jsonb_typeof(p->'directions') <> 'array' or jsonb_array_length(p->'directions') <> 3 then
    return errs || 'directions는 정확히 3개';
  end if;
  for item in select * from jsonb_array_elements(p->'directions') loop
    ids := ids || coalesce(item->>'id', '');
    if coalesce(item->>'name', '') = '' then errs := errs || format('%s: name 필요', item->>'id'); end if;
    if coalesce(item->>'description', '') = '' then errs := errs || format('%s: description 필요', item->>'id'); end if;
    if coalesce(item->>'image', '') !~ '^art/[A-Za-z0-9_.-]+\.(png|jpg|jpeg|webp)$' then
      errs := errs || format('%s: image는 art/<파일>.png|jpg|webp', item->>'id');
    end if;
  end loop;
  if ids <> array['A','B','C'] then errs := errs || 'directions의 id는 순서대로 A, B, C'; end if;
  return errs;
end $$;

create function public.submit_art(p_game uuid, p_owner text, p_art jsonb, p_commit text)
returns void language plpgsql security definer set search_path = public as $$
declare g games; errs text[];
begin
  select * into g from games where id = p_game for update;
  if not found or g.art_lease_owner is distinct from p_owner or g.art_lease_until <= now() then
    raise exception '아트 임대가 없습니다';
  end if;
  errs := validate_art(p_art);
  if coalesce(p_commit, '') !~ '^[0-9a-fA-F]{7,40}$' then errs := errs || 'commit 형식 오류'; end if;
  if array_length(errs, 1) > 0 then
    raise exception 'ART_INVALID: %', array_to_string(errs, ' / ');
  end if;
  update games set art = p_art, art_commit = lower(p_commit), art_pick = null,
                   art_lease_owner = null, art_lease_until = null
   where id = p_game;
  perform log_event(p_game, 'art', format('%s 아트 방향 3안 · %s', g.title, left(lower(p_commit), 7)));
end $$;

create function public.release_art(p_game uuid, p_owner text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare g games;
begin
  select * into g from games where id = p_game for update;
  if not found or g.art_lease_owner is distinct from p_owner then raise exception '아트 임대 소유자가 아닙니다'; end if;
  update games set art_lease_owner = null, art_lease_until = null where id = p_game;
  perform log_event(p_game, 'release', format('%s 아트 작업 중단(운영): %s', g.title, p_reason));
end $$;

-- 대표: 마음에 드는 아트 방향을 고른다(다시 누르면 바꿀 수 있다). null이면 선택 취소.
create function public.ceo_pick_art(p_game uuid, p_pick text)
returns void language plpgsql security definer set search_path = public as $$
declare g games;
begin
  perform require_ceo();
  select * into g from games where id = p_game for update;
  if not found or g.art is null then raise exception '아트 방향이 아직 없습니다'; end if;
  if p_pick is not null and p_pick not in ('A','B','C') then raise exception 'pick은 A|B|C'; end if;
  update games set art_pick = p_pick where id = p_game;
  if p_pick is not null then
    perform log_event(p_game, 'art', format('%s 아트 방향 %s 선택', g.title, p_pick));
  end if;
end $$;

do $$
declare f text;
begin
  foreach f in array array['claim_art(text,int)', 'submit_art(uuid,text,jsonb,text)', 'release_art(uuid,text,text)'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
  revoke execute on function public.ceo_pick_art(uuid,text) from public, anon;
  grant execute on function public.ceo_pick_art(uuid,text) to authenticated, service_role;
end $$;
