-- 아이디어 연구소 v2: 장르, 비평 점수, 승격 이유, 다음 검증 질문을 함께 입고한다.
-- 대표가 분류할 때 대시보드에서 이 정보를 보고 판단한다.

alter table public.games
  add column genre text check (genre is null or length(genre) <= 60),
  add column idea_scores jsonb,
  add column why_promoted text[],
  add column next_test text check (next_test is null or length(next_test) <= 300);

drop function public.add_idea(text, text, text, text, text);

-- p_scores: {"hook":0-100,"core_loop":..,"mobile_fit":..,"prototype":..,"asset":..,"visual":..,"growth":..}
create function public.add_idea(
  p_slug text, p_title text, p_pitch text, p_core_verb text, p_fun text,
  p_genre text default null, p_scores jsonb default null,
  p_why text[] default null, p_next_test text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  k text;
  v jsonb;
  keys text[] := array['hook','core_loop','mobile_fit','prototype','asset','visual','growth'];
begin
  if not has_room('idea') then
    raise exception 'NO_ROOM: 대표 분류 대기가 꽉 찼습니다' using errcode = 'P0001';
  end if;
  if p_scores is not null then
    foreach k in array keys loop
      v := p_scores -> k;
      if v is null or jsonb_typeof(v) <> 'number' or (v::text)::numeric <> floor((v::text)::numeric)
         or (v::text)::int not between 0 and 100 then
        raise exception 'SCORES_INVALID: % 는 0~100 정수여야 합니다', k;
      end if;
    end loop;
  end if;
  if p_why is not null and (cardinality(p_why) not between 1 and 4) then
    raise exception 'WHY_INVALID: why_promoted는 1~4개';
  end if;

  insert into games(slug, title, pitch, core_verb, fun_hypothesis, genre, idea_scores, why_promoted, next_test)
  values (p_slug, p_title, p_pitch, p_core_verb, p_fun, p_genre, p_scores, p_why, p_next_test)
  returning id into v_id;
  perform log_event(v_id, 'idea', format('새 아이디어: %s', p_title));
  return v_id;
end $$;

revoke execute on function public.add_idea(text,text,text,text,text,text,jsonb,text[],text) from public, anon, authenticated;
grant execute on function public.add_idea(text,text,text,text,text,text,jsonb,text[],text) to service_role;
