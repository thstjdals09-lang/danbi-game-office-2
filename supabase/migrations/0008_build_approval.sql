-- 빌드 결재: 디자인이 끝나면 바로 기획·빌드로 가지 않고 대표가 "이대로 만들자"를 눌러야 넘어간다.
-- 빌드가 가장 비싼 단계이므로, 설계 요약과 주 화면 시안(design/mock/main.png)만 보고 빨리 걸러 낸다.
-- 새 단계 proposed(빌드 결재 대기): designing → proposed → (대표 go) → designed → planning …
-- 프로덕션 차수(milestone 2 이상)는 이미 합격한 게임이라 결재 없이 designed 로 간다.

alter table public.games drop constraint games_stage_check;
alter table public.games add constraint games_stage_check check (stage in
  ('idea','designing','proposed','designed','planning','ready','building','qa','playtest','kept','held','dropped','done'));

create or replace function public.submit_design(p_game uuid, p_owner text, p_commit text, p_summary text, p_sim_status text)
returns void language plpgsql security definer set search_path = public as $$
declare g games; v_stage text;
begin
  select * into g from games where id = p_game for update;
  if not found or g.stage <> 'designing' or not lease_ok(g, p_owner) then
    raise exception '디자인 임대가 없습니다';
  end if;
  if coalesce(trim(p_summary), '') = '' then raise exception '요약이 필요합니다'; end if;
  if p_sim_status not in ('passed','skipped') then raise exception 'sim_status는 passed|skipped'; end if;
  v_stage := case when g.milestone >= 2 then 'designed' else 'proposed' end;
  update games set stage = v_stage, design_commit = lower(p_commit), design_version = design_version + 1,
                   design_summary = p_summary, sim_status = p_sim_status, fix_notes = null,
                   lease_owner = null, lease_until = null
   where id = p_game;
  perform log_event(p_game, 'design', format('%s 디자인 v%s · %s%s', g.title, g.design_version + 1, left(lower(p_commit), 7),
    case when v_stage = 'proposed' then ' · 빌드 결재 대기' else '' end));
end $$;

-- 대표의 빌드 결재.
--   go   : 이대로 만든다 → designed (기획실이 가져간다). 메모가 있으면 기획실이 읽는다.
--   redo : 설계를 다시 → idea (디자인실이 fix_notes 를 읽고 새 판을 만든다). 메모 필수.
--   hold : 보류 → held,  drop : 버림 → dropped
create or replace function public.ceo_design(p_game uuid, p_decision text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare g games; v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  perform require_ceo();
  select * into g from games where id = p_game for update;
  if not found then raise exception '게임 없음'; end if;
  if g.stage <> 'proposed' then raise exception '빌드 결재를 기다리는 게임이 아닙니다: %', g.stage; end if;
  if p_decision = 'go' then
    update games set stage = 'designed',
                     fix_notes = case when v_note is null then null else '[대표 빌드 결재 메모] ' || v_note end
     where id = p_game;
  elsif p_decision = 'redo' then
    if v_note is null then raise exception '무엇을 고칠지 메모가 필요합니다'; end if;
    update games set stage = 'idea', starred = true, fix_notes = '[대표: 설계 다시] ' || v_note where id = p_game;
  elsif p_decision = 'hold' then
    update games set stage = 'held' where id = p_game;
  elsif p_decision = 'drop' then
    update games set stage = 'dropped' where id = p_game;
  else
    raise exception 'decision은 go|redo|hold|drop 중 하나';
  end if;
  insert into reviews(game_id, reviewer, verdict, notes)
  values (p_game, 'ceo', case p_decision when 'redo' then 'fix' else p_decision end, '[빌드 결재] ' || coalesce(v_note, ''));
  perform log_event(p_game, 'ceo', format('%s 빌드 결재: %s', g.title,
    case p_decision when 'go' then '만든다' when 'redo' then '설계 다시' when 'hold' then '보류' else '버림' end));
end $$;

revoke all on function public.ceo_design(uuid,text,text) from public, anon;
grant execute on function public.ceo_design(uuid,text,text) to authenticated, service_role;
