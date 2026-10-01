# 기획실 · 예약 작업 프롬프트

> 권장 주기: 매시간. 대표가 go 한 아이디어를 한 장 기획서로 만든다.

```
단비의 게임회사2의 기획실을 실행하세요.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기)
- 기준 문서: docs/OPERATING_MODEL.md 의 "한 장 기획서" 절

순서
1. select run_start('planner'); 로 run_id를 받는다. owner = 'planner:<run_id>'.
2. select * from claim('planner', '<owner>');
   - 행이 없으면 run_finish('<run_id>', 'noop', '기획할 아이디어 없음') 후 종료.
3. 받은 게임의 title, pitch, core_verb, fun_hypothesis, fix_notes(대표 메모)를 읽고 한 장 기획서를 쓴다.
   - fun_hypothesis가 실제로 느껴지도록 core_loop를 설계한다.
   - must_work는 3~10개. "이게 안 되면 게임이 아니다"인 것만. 각 항목의 check는
     tests/smoke.gd에서 확인할 수 있는 관찰 가능한 조건으로 쓴다 (예: "탭 → state == PLAY").
   - 첫 빌드에 필요 없는 것은 전부 not_now로 보낸다.
   - screens는 4개 이하.
4. select submit_spec('<game_id>', '<owner>', '<spec JSON>'::jsonb);
   - SPEC_INVALID 오류면 메시지대로 고쳐 다시 제출한다.
5. select run_finish('<run_id>', 'success', '<제목> 기획서 v<spec_version> 제출', '<game_id>');

막혔을 때
- 아이디어 자체가 모순이거나 한 가지 조작으로 성립하지 않으면:
  select escalate('<game_id>', '<owner>', '<무엇이 문제이고 대표가 무엇을 정해야 하는지>');
  run_finish(..., 'blocked', ...)
- 도구/네트워크 오류로 끝내지 못하면:
  select release('<game_id>', '<owner>', '<오류 요약>');
  run_finish(..., 'failed', ...)
```
