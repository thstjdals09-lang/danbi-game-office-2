# 빌드실 · 예약 작업 프롬프트

> 기획 패키지를 Godot 4.7 게임으로 만든다. 기획실이 쓴 tests/smoke.gd를 통과시키는 것이 목표. 한 번에 한 게임.
> 권장 모델: Opus.

```
단비의 게임회사2의 빌드실을 실행하세요.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기/쓰기)
- 기준 문서: docs/OPERATING_MODEL.md 의 "게임 저장소 규칙"
- 참고 구현: games/first-lantern/ (구조, debug 훅, 그리기, 입력)

=== 0. 출근과 작업 가져오기 ===
1. select run_start('builder'); 로 run_id를 받는다. owner = 'builder:<run_id>'.
2. select * from claim('builder', '<owner>');
   - 행이 없으면 run_finish('<run_id>', 'noop', '빌드할 게임 없음') 후 종료.
   - attempt가 1이면 새 빌드, 2 이상이면 수리 빌드다. 수리 빌드는 fix_notes에 적힌 것을 먼저 고친다.
3. 읽을 것(이 순서로): games/<slug>/design/FIRST_BUILD.md → SCREENS.md → spec.json → tests/smoke.gd → GAME_DESIGN.md(필요한 절)
   - FIRST_BUILD.md가 이번 빌드의 기준이다. GAME_DESIGN.md의 나머지는 만들지 않는다(not_now).

=== 1. 구현 ===
- games/<slug>/scripts/, scenes/, assets/ 안에서 구현한다. project.godot은 화면 방향/크기 외에는 템플릿 그대로.
- FIRST_BUILD.md "테스트 인터페이스"의 속성과 함수를 정확한 이름·타입으로 메인 씬에 제공한다.
- 규칙과 수치는 FIRST_BUILD.md 규칙표 그대로. 바꾸고 싶으면 바꾸지 말고 반송한다.
- 화면은 SCREENS.md의 배치와 동작, 피드백을 따른다. 도형·색·기본 폰트로 읽히게 그린다.
- 글자는 res://assets/fonts/NotoSansKR-Medium.ttf (ThemeDB.fallback_font는 웹에서 한글이 깨진다).
- 입력은 InputEventScreenTouch(마우스는 project.godot 설정으로 터치가 된다). 드래그는 InputEventScreenDrag.

=== 2. 검사 ===
- tests/smoke.gd는 기획실이 쓴 파일이다. 한 글자도 바꾸지 않는다(해시로 대조되어 바뀌면 제출이 거절된다).
- export GODOT="$(bash tools/install_godot.sh)"; python3 tools/smoke.py games/<slug>
  FAIL이면 게임 코드를 고쳐 다시 돌린다. PASS가 나올 때까지 반복하되, 시간이 모자라면 실패 상태로 제출한다.
- 검사 자체가 FIRST_BUILD.md 규칙과 모순되거나, 테스트 인터페이스로는 확인할 수 없는 걸 요구하면 → 아래 "반송".

=== 3. 커밋과 제출 ===
0. games/<slug>/BUILD.md 를 쓴다(없으면 만들고, 있으면 맨 위에 추가): 빌드 회차, 기획 버전(spec_version),
   무엇을 만들었는지, smoke 결과, 알려진 한계. 이 파일이 있어야 CI가 이 게임을 검사·배포한다.
1. games/<slug>/ 아래만 커밋하고 main에 push(작업 브랜치라면 git push origin HEAD:main).
   메시지: "<slug>: build <attempt> — <한 줄 요약>"
2. 해시: git show <SHA>:games/<slug>/tests/smoke.gd | sha256sum
3. select submit_build('<game_id>', '<owner>', '<커밋 SHA>', <smoke 결과 true|false>,
                       '<무엇을 만들었고 무엇을 고쳤는지, FAIL이면 원인>', '<tests sha256>');
   - TESTS_CHANGED 오류면 tests/smoke.gd를 기획실 버전(git log로 확인)으로 되돌려 다시 커밋한다.
4. select run_finish('<run_id>', 'success', '<제목> 빌드 <attempt>회차 · <SHA 7자리> · smoke <PASS|FAIL>', '<game_id>');

=== 반송 ===
검사나 규칙이 틀렸다고 판단되면 고치지 말고:
  select send_back('<game_id>', '<owner>', 'planner', '<어느 must_work/규칙이 왜 모순인지, 근거>');
  (디자인 자체가 문제면 'designer'). run_finish(..., 'blocked', ...)

막혔을 때
- 시간 부족, GitHub/도구 오류로 커밋하지 못했으면:
  select release('<game_id>', '<owner>', '<오류 요약>'); run_finish(..., 'failed', ...)
  (임대가 만료되면 다음 실행이 이어받는다)

하지 말 것
- tests/smoke.gd, design/ 문서, 다른 게임 폴더, tools/, .github/, supabase/ 를 고치지 않는다.
- 테이블을 직접 INSERT/UPDATE 하지 않는다.
최종 응답은 짧게: 제목, 무엇을 만들었는지 한 줄, smoke 결과, 커밋 SHA.
```
