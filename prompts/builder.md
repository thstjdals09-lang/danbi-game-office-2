# 빌드실 · 예약 작업 프롬프트

> 권장 주기: 매시간. 기획서를 Godot 4.7 프로젝트로 만든다. 한 번에 한 게임.

```
단비의 게임회사2의 빌드실을 실행하세요.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기/쓰기)
- 기준 문서: docs/OPERATING_MODEL.md 의 "게임 저장소 규칙"
- 참고 구현: games/first-lantern/ (구조, debug 훅, tests/smoke.gd 작성 방식)

순서
1. select run_start('builder'); 로 run_id를 받는다. owner = 'builder:<run_id>'.
2. select * from claim('builder', '<owner>');
   - 행이 없으면 run_finish('<run_id>', 'noop', '빌드할 게임 없음') 후 종료.
   - attempt가 1이면 새 빌드, 2 이상이면 수리 빌드다. 수리 빌드는 fix_notes에 적힌 것을 먼저 고친다.
3. 게임 폴더
   - games/<slug>/가 없으면 games/_template/을 복사해 만든다
     (로컬에서 가능하면: python tools/new_game.py <slug> --title ... --pitch ... --orientation ...).
   - games/<slug>/SPEC.md에 DB의 spec을 사람이 읽을 수 있게 옮긴다 (spec_version 표시).
4. 구현
   - spec의 screens, core_loop, controls, win_lose, art_direction을 구현한다. not_now는 만들지 않는다.
   - 글자는 res://assets/fonts/NotoSansKR-Medium.ttf 로 그린다 (ThemeDB.fallback_font는 웹에서 한글이 깨진다).
   - 입력은 InputEventScreenTouch로 받는다 (마우스는 project.godot 설정으로 터치가 된다).
   - tests/smoke.gd에 must_work마다 check("M<n>", ...)를 하나 이상 둔다.
     입력은 메인 씬의 debug_* 함수로 흉내 낸다. 마지막에 "SMOKE PASS"를 출력하고 실패가 있으면 exit 1.
   - Godot를 실행할 수 있는 환경이면 직접 검사해 PASS를 확인한다. 리눅스(클라우드 작업)라면:
       export GODOT="$(bash tools/install_godot.sh)"; python3 tools/smoke.py games/<slug>
     FAIL이면 고쳐서 다시 돌린다. PASS가 나올 때까지 반복하되, 시간이 모자라면 실패 상태로 제출한다.
5. main에 커밋하고 push한다. 메시지: "<slug>: build <attempt> — <한 줄 요약>"
   (작업 브랜치에서 일하는 환경이면 git push origin HEAD:main)
6. select submit_build('<game_id>', '<owner>', '<커밋 SHA>', <smoke 결과>, '<무엇을 만들었고 무엇을 고쳤는지>');
   - <smoke 결과>: 직접 smoke.py를 돌렸으면 true/false, 못 돌렸으면 null (검수실이 CI 결과로 확정한다).
   - false면 빌드 대기로 되돌아간다. 실패 원인을 notes에 적는다.
7. select run_finish('<run_id>', 'success', '<제목> 빌드 <attempt>회차 · <SHA 7자리>', '<game_id>');

막혔을 때
- 기획서대로는 구현이 성립하지 않으면(모순, 빠진 규칙):
  select escalate('<game_id>', '<owner>', '<어느 항목이 왜 안 되는지>'); run_finish(..., 'blocked', ...)
- 시간 부족, GitHub/도구 오류: 커밋하지 못했으면
  select release('<game_id>', '<owner>', '<오류 요약>'); run_finish(..., 'failed', ...)
  (임대가 만료되면 다음 실행이 이어받는다)

하지 말 것
- 다른 게임 폴더, tools/, .github/, supabase/ 를 고치지 않는다.
- smoke 검사를 통과시키려고 check를 약하게 만들지 않는다. must_work의 check 문장 그대로 확인한다.
```
