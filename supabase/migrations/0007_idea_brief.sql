-- 아이디어 요약(idea_brief): 아이디어 연구소가 승격 후보를 구조화하며 이미 정리한 내용을 버리지 않고 넘긴다.
-- 디자인실은 이것을 출발점으로 삼고, 대표는 대시보드에서 "한 판의 흐름"을 보고 판단한다.
-- add_idea는 그대로 두고, 입고 직후 set_idea_brief로 붙인다.
--
-- idea_brief: {
--   "play": ["한 판의 흐름을 순서대로 3~8줄"],
--   "in_run": "한 판 안에서 달라지고 쌓이는 것",
--   "between_runs": "판과 판 사이에 남는 것(없으면 '없음')",
--   "systems": "맞물리는 시스템과 서로 주는 영향",
--   "tenth_run": "열 번째 판이 첫 판과 다른 점",
--   "input": "모바일 입력 방식"
-- }

alter table public.games add column idea_brief jsonb;

create function public.check_idea_brief(p_brief jsonb) returns void
language plpgsql immutable set search_path = public as $$
declare
  k text;
  n int;
begin
  if p_brief is null then return; end if;
  if jsonb_typeof(p_brief) <> 'object' then
    raise exception 'BRIEF_INVALID: idea_brief는 객체여야 합니다';
  end if;
  if jsonb_typeof(p_brief -> 'play') is distinct from 'array' then
    raise exception 'BRIEF_INVALID: play는 배열이어야 합니다';
  end if;
  n := jsonb_array_length(p_brief -> 'play');
  if n not between 3 and 8 then
    raise exception 'BRIEF_INVALID: play는 3~8줄';
  end if;
  if exists (select 1 from jsonb_array_elements(p_brief -> 'play') e
             where jsonb_typeof(e) <> 'string' or length(e #>> '{}') not between 1 and 200) then
    raise exception 'BRIEF_INVALID: play의 각 줄은 1~200자 문자열';
  end if;
  foreach k in array array['in_run','between_runs','systems','tenth_run','input'] loop
    if jsonb_typeof(p_brief -> k) is distinct from 'string' or length(p_brief ->> k) not between 1 and 400 then
      raise exception 'BRIEF_INVALID: % 는 1~400자 문자열이어야 합니다', k;
    end if;
  end loop;
end $$;

-- 입고된 아이디어에 요약을 붙이거나 고친다. 디자인실이 가져가기 전(stage='idea')에만.
create function public.set_idea_brief(p_slug text, p_brief jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_brief is null then
    raise exception 'BRIEF_INVALID: idea_brief가 비었습니다';
  end if;
  perform check_idea_brief(p_brief);
  update games set idea_brief = p_brief where slug = p_slug and stage = 'idea';
  if not found then
    raise exception '대기 중인 아이디어가 아닙니다: %', p_slug;
  end if;
end $$;

revoke execute on function public.set_idea_brief(text,jsonb) from public, anon, authenticated;
grant execute on function public.set_idea_brief(text,jsonb) to service_role;
