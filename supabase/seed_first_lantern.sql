-- 파이프라인 시험 게임 First Lantern을 실제 제작 함수로 한 바퀴 돌려 playtest에 올린다.
-- 새 DB에서 한 번만 실행 (DB 직접 접속 또는 SQL Editor).
do $$
declare
  v_game uuid;
  v_run uuid;
  v_owner text;
  v_spec jsonb := $j${
    "one_liner": "꺼지기 전에 등불을 눌러 밝힌다",
    "orientation": "portrait",
    "controls": "화면 탭 한 가지",
    "core_loop": ["등불이 나타남", "꺼지기 전에 탭", "놓치면 목숨 -1", "점점 빨라짐"],
    "screens": [
      {"id": "title", "what": "제목, 시작 안내, 최고 기록"},
      {"id": "play", "what": "등불들, 점수, 남은 시간, 목숨"},
      {"id": "result", "what": "점수, 최고 기록, 다시 하기"}
    ],
    "win_lose": "45초가 지나거나 3번 놓치면 끝",
    "session_seconds": 45,
    "art_direction": "어두운 남색 밤, 따뜻한 노란 불빛. 도형과 기본 폰트만 사용",
    "must_work": [
      {"id": "M1", "text": "타이틀 화면에서 시작한다", "check": "실행 직후 state == TITLE"},
      {"id": "M2", "text": "탭하면 플레이가 시작된다", "check": "타이틀에서 탭 → state == PLAY"},
      {"id": "M3", "text": "등불을 누르면 점수가 1 오른다", "check": "등불 근처 탭 → score == 1"},
      {"id": "M4", "text": "놓친 등불은 목숨을 1 깎는다", "check": "등불 수명 초과 → lives == 2"},
      {"id": "M5", "text": "목숨이 0이면 결과 화면으로 가고 최고 기록이 남는다", "check": "lives = 0 → state == RESULT, best >= 1"},
      {"id": "M6", "text": "결과 화면에서 탭하면 다시 시작한다", "check": "탭 → state == PLAY, score == 0"}
    ],
    "not_now": ["사운드", "랭킹", "튜토리얼", "난이도 선택"]
  }$j$;
begin
  v_game := add_idea('first-lantern', 'First Lantern', '꺼지기 전에 등불을 눌러 밝힌다. 파이프라인 시험 게임.', '탭',
                     '점점 빨라지는 불빛을 놓치지 않으려는 긴장감');
  perform ceo_triage(v_game, 'go', '파이프라인 시험');

  v_run := run_start('planner'); v_owner := 'planner:' || v_run;
  perform claim('planner', v_owner);
  perform submit_spec(v_game, v_owner, v_spec);
  perform run_finish(v_run, 'success', 'First Lantern 기획서 v1 제출 (시드)', v_game);

  v_run := run_start('builder'); v_owner := 'builder:' || v_run;
  perform claim('builder', v_owner);
  perform submit_build(v_game, v_owner, '3044466', true, '시드 빌드: 한글 폰트 포함, smoke 6/6 통과');
  perform run_finish(v_run, 'success', 'First Lantern 빌드 1회차 · 3044466 (시드)', v_game);

  v_run := run_start('qa'); v_owner := 'qa:' || v_run;
  perform claim('qa', v_owner);
  perform submit_qa(v_game, v_owner, 'pass', true,
    '[{"id":"M1","ok":true,"note":"tests/smoke.gd"},{"id":"M2","ok":true,"note":"tests/smoke.gd"},
      {"id":"M3","ok":true,"note":"tests/smoke.gd"},{"id":"M4","ok":true,"note":"tests/smoke.gd"},
      {"id":"M5","ok":true,"note":"tests/smoke.gd"},{"id":"M6","ok":true,"note":"tests/smoke.gd"}]'::jsonb,
    'CI smoke/first-lantern success');
  perform run_finish(v_run, 'success', 'First Lantern 검수 pass (시드)', v_game);
end $$;
