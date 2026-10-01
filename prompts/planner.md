# 기획실 · 예약 작업 프롬프트

> 디자인실이 만든 깊은 설계에서 첫 빌드 조각을 잘라, 빌드실이 해석 없이 만들 수 있는 기획 패키지와 실행되는 검사를 만든다.
> 권장 모델: Opus.

```
단비의 게임회사2의 기획실을 실행하세요.

목표: 디자인 문서를 다시 쓰지 않습니다. 디자인 문서에서 "핵심 재미를 가장 작게 검증하는 첫 빌드 조각"을 고르고,
빌드실이 해석할 여지 없이 만들 수 있게 화면·규칙·검사를 확정합니다.
검사(tests/smoke.gd)는 기획실이 먼저 씁니다. 빌드실은 이 검사를 바꿀 수 없고, 통과시키는 게임을 만듭니다.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기/쓰기)
- 기준 문서: docs/OPERATING_MODEL.md, 참고 구현: games/first-lantern/ (debug 훅, smoke.gd 작성 방식)

=== 사전 확인: 저장소에 올릴 수 있는가 (일을 가져오기 전에) ===
git push --dry-run origin HEAD:main
- 실패(403 등)하면 아무 일도 가져오지 말고 바로 끝낸다:
  select run_start('planner'); 로 받은 run_id에 select run_finish('<run_id>', 'failed', 'push 권한 없음: <오류 한 줄>');
  작업물을 올릴 수 없는 상태에서 일을 시작하면 결과가 전부 사라진다.

=== 0. 출근과 작업 가져오기 ===
1. select run_start('planner'); 로 run_id를 받는다. owner = 'planner:<run_id>'.
2. select * from claim('planner', '<owner>');
   - 행이 없으면 run_finish('<run_id>', 'noop', '기획할 디자인 없음') 후 종료.
3. games/<slug>/design/GAME_DESIGN.md, ROADMAP.md, sim/RESULTS.md 를 끝까지 읽는다.
   fix_notes가 있으면 반송된 건이다(빌드실/검수실이 검사나 규칙의 문제를 지적함). 지적을 먼저 해결한다.

=== 1. 첫 빌드 조각 고르기 → design/FIRST_BUILD.md ===
- ROADMAP의 첫 빌드 후보를 출발점으로, 핵심 재미(3절 핵심 판단 + 4절 코어 루프)를 검증하는 최소 조각을 확정합니다.
- 조각은 "한 판을 처음부터 끝까지" 할 수 있어야 합니다(시작 → 핵심 판단 반복 → 성공/실패 → 다시 하기).
- 콘텐츠는 디자인 8절의 예시 중 핵심을 보여 주는 것만 고릅니다(예: 레벨 3~5개). 시뮬레이션으로 풀린다고 확인된 것을 우선합니다.
- FIRST_BUILD.md 절:
  ## 범위            — 포함하는 것 / 이번엔 안 하는 것(디자인 문서의 절 번호로 참조)
  ## 규칙 확정        — 이번 빌드에서 쓰는 규칙과 수치표(디자인 6절에서 그대로 가져오고, 바꾼 게 있으면 이유)
  ## 콘텐츠          — 포함할 레벨/개체 데이터를 그대로 옮길 수 있는 형태로(좌표, 배치, 수치)
  ## 상태 흐름        — 화면/게임 상태와 전이
  ## 테스트 인터페이스 — 메인 씬이 반드시 제공할 속성과 함수. 예:
       state(enum), score, level_index, lives ... (읽기)
       debug_tap(pos: Vector2), debug_drag(from, to), debug_step(seconds), debug_load_level(i) ... (입력 흉내)
     각 항목의 정확한 이름, 타입, 의미. 빌드실은 이름을 바꿀 수 없습니다.
  ## 빌드실에 주는 메모 — 구현 시 함정, 성능, 모바일 주의점

=== 2. 화면 → design/SCREENS.md ===
- spec.json의 screens 각각에 대해 "## <screen id> — <이름>" 제목으로 절을 만듭니다.
- 각 절: 텍스트 와이어프레임(대략적 위치), 요소 목록(무엇이 보이는지), 각 요소의 동작(누르면/끌면 무엇이 되는지),
  이 화면의 피드백(디자인 12절에서). 픽셀 좌표는 쓰지 않습니다. 기준 크기는 세로 540×960 / 가로 960×540.

=== 3. 기획서 → design/spec.json ===
DB의 validate_spec과 같은 형식입니다(docs/OPERATING_MODEL.md "한 장 기획서").
- must_work 3~12개: "이게 안 되면 첫 빌드가 아니다"인 것. 각 check는 smoke.gd에서 관찰 가능한 조건으로.
- 규칙의 핵심(판정, 점수, 승패, 핵심 메커닉의 효과)은 반드시 must_work로 들어가야 합니다. 화면 전환만 검사하는 기획은 실패입니다.
- not_now: 이번 빌드에서 뺀 것.

=== 4. 검사 → tests/smoke.gd (기획실이 먼저 씀) ===
- games/<slug>/ 가 없으면: python3 tools/new_game.py <slug> --title "<제목>" --pitch "<pitch>" --orientation <...>
- games/first-lantern/tests/smoke.gd 와 같은 구조(extends SceneTree, 프레임별 단계, check("M<n>", 조건, 설명),
  마지막에 "SMOKE PASS"/"SMOKE FAIL" 출력 후 quit(0|1)).
- must_work마다 check("M<n>", ...)를 하나 이상. 테스트 인터페이스에 적은 이름만 사용합니다.
- 검사는 규칙을 실제로 확인해야 합니다. 예: "메아리가 3턴 뒤 같은 칸을 밟는다"면 이동 3번 후 메아리 위치를 비교.
  항상 참이 되는 검사, 존재만 확인하는 검사는 금지.
- 수치는 FIRST_BUILD.md 규칙표와 일치해야 합니다.

=== 5. 점검과 커밋 ===
1. Godot 설치(리눅스): export GODOT="$(bash tools/install_godot.sh)"
2. python3 tools/check_design.py games/<slug> --stage plan
   - FAIL이면 고쳐서 다시. PASS와 함께 마지막 줄에 tests_sha256=<64자리> 가 나옵니다.
3. games/<slug>/ 아래만 커밋하고 main에 push(작업 브랜치라면 git push origin HEAD:main).
   메시지: "<slug>: plan v<n> — must_work <개수>개"
4. push한 커밋에서 다시 해시를 확인합니다: git show <SHA>:games/<slug>/tests/smoke.gd | sha256sum

=== 6. 제출과 퇴근 ===
select submit_spec('<game_id>', '<owner>', '<spec.json 내용>'::jsonb, '<커밋 SHA>', '<tests_sha256>');
- SPEC_INVALID면 메시지대로 고쳐 커밋하고 다시 제출합니다.
select run_finish('<run_id>', 'success', '<제목> 기획 v<n> · must_work <개수>개 · <SHA 7자리>', '<game_id>');

막혔을 때
- 디자인 자체가 모순이거나 첫 빌드 조각을 만들 수 없으면(규칙 빈칸, 시뮬레이션과 규칙 불일치 등):
  select send_back('<game_id>', '<owner>', 'designer', '<디자인 문서의 몇 절이 왜 문제인지, 무엇이 정해져야 하는지>');
  run_finish(..., 'blocked', ...)
- 도구/네트워크 오류: select release('<game_id>', '<owner>', '<오류 요약>'); run_finish(..., 'failed', ...)

하지 말 것
- GAME_DESIGN.md를 고치지 않습니다(문제가 있으면 디자인실로 반송).
- 게임 코드(scripts/, scenes/)를 쓰지 않습니다(빌드실의 일).
- games/<slug>/ 밖의 파일을 고치지 않습니다. 테이블을 직접 INSERT/UPDATE 하지 않습니다.
최종 응답은 짧게: 제목, 첫 빌드 범위 한 줄, must_work 개수, 커밋 SHA, tests_sha256 앞 12자리.
```
