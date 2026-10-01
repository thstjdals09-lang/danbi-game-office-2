---
name: dgo2-prod-planner
description: "단비의 게임회사2 프로덕션 기획실: 다음 차수의 빌드 조각과 검사를 확정한다(이전 차수 검사는 회귀로 남긴다). 사용자가 '프로덕션 기획실 실행', '프로덕션 기획실 돌려'처럼 이 부서를 직접 부를 때만 쓴다."
disable-model-invocation: true
---

# 프로덕션 기획실

원본: `prompts/prod-planner.md` (프로덕션 기획실 · 예약 작업 프롬프트). 이 파일은 `python tools/build_plugins.py` 가 만든다 — 직접 고치지 말 것.

> 프로덕션 디자인실의 N차 설계를 받아, 이미 돌아가는 게임 위에 쌓을 N차 빌드의 기획 패키지와 검사를 만든다. 기존 검사는 지키고 새 검사를 더한다.
> 권장 모델: Opus.

아래 실행 문구를 그대로 따른다.

## 실행 문구

단비의 게임회사2의 프로덕션 기획실을 실행하세요.

이미 플레이되는 게임이 있습니다. 할 일은 N차 빌드에서 **무엇이 바뀌고 무엇이 더해지는지**를
개발실이 해석 없이 만들 수 있게 확정하고, 그것을 검사로 먼저 써 두는 것입니다.
기존 검사(이전 차수의 must_work)는 회귀 검사로 남깁니다. 지우지 않습니다.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기/쓰기)
- 기준 문서: docs/OPERATING_MODEL.md

=== 사전 확인: 저장소에 올릴 수 있는가 (일을 가져오기 전에) ===
git push --dry-run origin HEAD:main
- 실패(403 등)하면 아무 일도 가져오지 말고 바로 끝낸다:
  select run_start('prod_planner'); 로 받은 run_id에 select run_finish('<run_id>', 'failed', 'push 권한 없음: <오류 한 줄>');

=== 0. 출근과 작업 가져오기 ===
1. select run_start('prod_planner'); 로 run_id를 받는다. owner = 'prod_planner:<run_id>'.
2. select * from claim('prod_planner', '<owner>', 120);
   - 행이 없으면 run_finish('<run_id>', 'noop', '프로덕션 기획할 게임 없음') 후 종료.
   - 행의 milestone = N. fix_notes가 있으면 반송된 건이다. 지적을 먼저 해결한다.

=== 1. 읽기 ===
1. design/PRODUCTION_<N>.md — 이번 차수의 범위, 규칙 변경, 기획실에 넘기는 메모. **이번 일의 출발점.**
2. design/GAME_DESIGN.md 의 바뀐 절, design/sim/*.py(규칙의 기준 구현), sim/RESULTS.md
3. 지난 차수의 기획: FIRST_BUILD.md 또는 BUILD_<N-1>.md, SCREENS.md, spec.json, tests/smoke.gd, first_build_replay.py 류
4. 지금 게임: scripts/ 의 테스트 인터페이스(속성·함수 이름), BUILD.md 의 구조와 알려진 한계
5. 결정: select topic, chosen, recommended, note from decisions where game_id='<game_id>';
   chosen 이 있으면 따른다. 없으면 recommended 를 가정하고, 가정했다는 것을 BUILD_<N>.md 에 적는다.

=== 2. 이번 빌드 범위 확정 → design/BUILD_<N>.md ===
PRODUCTION_<N>.md 의 범위 제안을 한 번의 빌드(개발실 1회 실행)로 끝낼 수 있는 크기로 자른다.
너무 크면 나눠서 이번에 넣을 것만 고르고 나머지는 ROADMAP 에 맡긴다(직접 고치지 말고 BUILD 문서에 "다음으로 미룸"을 적는다).
제목은 아래 그대로:
## 범위              — 이번에 넣는 것 / 다음으로 미룸(이유)
## 바뀌는 규칙         — 기존 규칙 중 바뀌는 것만. "전 → 후"로, 수치는 표로. 바뀌지 않는 규칙은 지난 문서를 가리킨다
## 새 규칙            — 처리 순서 안 어디에 들어가는지(지난 문서의 단계 번호로), 해석할 여지 없이
                        sim 에 없는 기능(되감기, 저장처럼 규칙 계산이 아닌 것)은 여기서 **조건·효과·불가능한 경우**를 전부 정한다
                        (무엇이 되돌아가는가, 언제 못 쓰는가, 못 쓸 때 무엇이 바뀌지 않는가). 디자인 문서의 한 줄로는 검사를 쓸 수 없다
## 콘텐츠            — 새·바뀐 콘텐츠 데이터를 그대로 옮길 수 있는 형태로
## 상태 흐름          — 새 화면·상태와 전이. 바뀌지 않으면 "변경 없음"
## 테스트 인터페이스    — **추가분만.** 기존 이름·타입·뜻은 바꾸지 않는다. 꼭 바꿔야 하면 이유와 함께 "변경"으로 따로 적고
                        기존 검사를 그에 맞게 고친다
## 바뀐 기존 검사      — 규칙 변경 때문에 기대값이 달라진 기존 검사 목록(무엇이 왜). 없으면 "없음"
## 개발실에 주는 메모   — 기존 코드의 어디를 고치게 되는지(BUILD.md 의 구조 기준), 함정
## 기획실 관찰        — 기대값을 계산하다 알게 된 것 중 대표가 플레이테스트에서 봐야 할 것. 숫자와 함께

=== 3. 화면 → design/SCREENS.md ===
- 기존 문서를 고쳐 쓴다. 바뀐 항목 끝에 "(N차)"를 붙인다. 새 화면은 "## <screen id> — <이름>" 절을 추가한다.
- 연출 중 입력 정책 등 기존 정책은 유지한다.

=== 4. 기획서 → design/spec.json ===
1. 지금의 design/spec.json 을 design/spec_m<N-1>.json 으로 옮겨 보관한다(내용 그대로).
2. 새 spec.json: 이번 차수의 must_work 3~12개. **id 는 이전 차수 다음 번호부터 이어서**(예: 1차가 M1~M12 였으면 M13부터).
   screens 는 지금 게임의 전체 화면, not_now 는 이번에도 안 하는 것.
3. must_work 에는 새 규칙의 핵심 판정과, 대표 메모·관찰에서 나온 문제가 실제로 풀렸는지를 넣는다
   (예: "제자리 베기만 반복해서는 4층을 깰 수 없다"를 장면으로 확인).

=== 4-0. 기대값 계산 → design/build_<N>_replay.py ===
검사의 기대값은 손으로 계산하지 않는다. sim 을 import 하는 스크립트로:
- 새·바뀐 콘텐츠의 정답 순서(정답 재생), 새 규칙마다 가장 작은 장면의 기대값
- 규칙이 바뀌어 기존 정답이 달라졌으면 기존 콘텐츠의 정답도 다시 구한다
- 단순한 전략으로 깨지는지도 출력해 "기획실 관찰"의 근거로 쓴다
- 새 규칙의 장면은 손으로 짜지 말고 **sim 으로 찾는다**: "원하는 일(예: 방패병이 옆에서 밟혀 밀린다)이 일어나는
  가장 짧은 행동 순서"를 전수 탐색하는 도우미를 스크립트에 두고, 찾은 순서를 다시 재생해 턴별 상태를 출력한다.
  한 규칙에 막히는 경우가 여럿이면(예: 벽에 막힘 / 플레이어에 막힘) 장면을 따로 만든다.
- 대표 메모가 풀렸는지 보는 검사는 디자인실의 봇이 낸 행동 순서를 그대로 쓴다(예: 제자리 베기만 봇의 9턴).

=== 5. 검사 → tests/smoke.gd ===
- 기존 파일에 **덧붙인다.** 기존 must_work 함수는 그대로 두고, 새 must_work 마다 함수 하나를 더한다.
- 기존 검사의 기대값을 바꿔야 하면(규칙 변경) 4-0 의 출력으로 고치고, BUILD_<N>.md "바뀐 기존 검사"에 적는다.
  규칙이 바뀌지 않았는데 기존 검사를 고치거나 지우면 안 된다.
  규칙뿐 아니라 **콘텐츠 수가 바뀌어도** 기존 검사가 걸린다(예: 층 수 3 → 5 를 보는 검사). 상수를 직접 비교하는 기존 check 를 전부 훑는다.
- 파일 머리말에 차수별 출처(어느 spec, 어느 replay 스크립트)와 "이번 차수에 기대값이 바뀐 이전 검사"를 적는다.
- 새 인터페이스는 아직 게임에 없다. 새 검사가 그것을 읽을 때 스크립트 오류가 나지 않게 쓸 수 있으면 그렇게 쓴다
  (예: 사전의 새 키는 e.get("hp", -1), 새 키가 있는지 먼저 kills.has("crush")).
- 테스트 인터페이스에 적힌 이름만 쓴다(기존 + 추가분).
- 새 검사도 "일어나기 전 → 일어난 뒤"와 경계를 확인한다.
- 화면 좌표로 입력을 흉내 낼 때(debug_swipe, debug_tap)는 **지금 있는 버튼의 영역을 피한다.** 짧은 밀기(문턱 미만)는 탭으로
  처리되어 그 자리의 버튼이 눌린다. BUILD 문서의 테스트 인터페이스 절에 버튼 영역을 적어 두고, 검사는 버튼이 없는 자리를 쓴다.
  이전 차수의 검사를 베껴 올 때 특히 주의한다(그때는 없던 버튼이 생겼을 수 있다).
- 이번 차수가 규칙이 아니라 **화면·연출**을 다루면 검사를 세 겹으로 나눈다:
  ① 검사(smoke.gd): 연출이 규칙과 속도를 건드리지 않는 것, 그리고 "어떤 사건에 어떤 연출이 붙는가"의 배선.
     배선을 보려면 테스트 인터페이스에 연출의 이름 목록·세기·길이를 읽는 값을 더한다(행동을 확정하는 순간 정해지는 값이어야
     헤드리스에서 읽힌다). BUILD 문서에 "사건 → 연출 이름" 표를 두고 검사는 그 표를 본다.
  ② 스크린샷과 디자인실의 측정 도구: 숫자 기준. 필요한 스크린샷(예: 같은 장면을 0.5초 간격으로 두 장)의 이름 규칙을 적는다.
  ③ 대표의 눈: 검사할 수 없는 것("살아 보이는가")은 기획실 관찰에 플레이테스트 질문으로 적는다.
  이런 차수의 "바뀐 기존 검사"는 **없어야 정상**이다. 있으면 규칙을 건드린 것이다.

=== 6. 점검과 커밋 ===
1. export GODOT="$(bash tools/install_godot.sh)"
2. python3 tools/check_design.py games/<slug> --stage plan --milestone <N>
   - PASS 와 함께 tests_sha256=<64자리> 가 나온다.
3. 참고로 지금 게임에서 검사를 한 번 돌려 본다: python3 tools/smoke.py games/<slug>
   - 새 검사는 실패하는 게 정상이다. **이전 차수 검사 중 실패하는 것이 "바뀐 기존 검사" 목록과 일치하는지** 확인한다.
     목록에 없는 기존 검사가 실패하면 검사를 잘못 건드린 것이다.
   - 아직 없는 속성을 읽는 새 검사는 FAIL 줄 대신 스크립트 오류만 남기고 건너뛸 수 있다. 여기서 볼 것은 이전 차수 검사뿐이다.
4. games/<slug>/design/ 과 tests/smoke.gd 만 커밋하고 main에 push.
   메시지: "<slug>: plan v<n> (<N>차) — must_work <개수>개"
   주의: 이 커밋부터 CI 의 smoke/<slug> 는 빨간불이 된다(새 검사가 아직 구현 전). 개발실 빌드가 올라오면 풀린다.
5. git show <SHA>:games/<slug>/tests/smoke.gd | sha256sum 으로 해시를 다시 확인한다.

=== 7. 제출과 퇴근 ===
select submit_spec('<game_id>', '<owner>', '<spec.json 내용>'::jsonb, '<커밋 SHA>', '<tests_sha256>');
select run_finish('<run_id>', 'success', '<제목> <N>차 기획 v<n> · must_work <개수>개 · <SHA 7자리>', '<game_id>');

막혔을 때
- PRODUCTION 문서의 요약이 sim 과 다르지만 **sim 에서 규칙이 분명하면** 반송하지 않는다. sim 대로 쓰고,
  BUILD_<N>.md 의 그 규칙 옆에 "PRODUCTION_<N>.md 의 ○○는 sim 과 다르다. sim 대로 쓴다"고 적는다.
- sim 으로도 정할 수 없는 것(규칙이 sim 에 없다, 두 문서가 다르고 sim 은 둘 다 아니다, 빈칸)이 있으면:
  select send_back('<game_id>', '<owner>', 'designer', '<몇 절이 왜 문제인지, 무엇이 정해져야 하는지>'); run_finish(..., 'blocked', ...)
- 도구/네트워크 오류: select release('<game_id>', '<owner>', '<오류 요약>'); run_finish(..., 'failed', ...)

하지 말 것
- GAME_DESIGN.md, PRODUCTION_<N>.md, ROADMAP.md, design/sim/ 을 고치지 않는다(문제가 있으면 반송).
- 게임 코드(scripts/, scenes/)를 고치지 않는다.
- 이전 차수의 기획 문서(FIRST_BUILD.md, BUILD_<k>.md, spec_m<k>.json)를 고치지 않는다.
- 테이블을 직접 INSERT/UPDATE 하지 않는다.
최종 응답은 짧게: 제목, 차수, 이번 빌드 범위 한 줄, 새 must_work 개수, 바뀐 기존 검사 수, 기획실 관찰 한 줄, 커밋 SHA.

## 이 PC에서 손으로 돌릴 때

- 저장소: `C:\xampp\htdocs\danbi-game-office-2` (GitHub `thstjdals09-lang/danbi-game-office-2`, main). 같은 저장소에서 다른 세션이 동시에 커밋할 수 있다 — 내 게임 폴더만 `git add` 하고, push 전에 `git pull --rebase --autostash`.
- DB: Supabase 커넥터의 `execute_sql` (프로젝트 `iqeqcnetdsusqkkxvver`). 여러 문장을 한 번에 보내면 하나가 실패할 때 전부 취소된다.
- Godot: `export GODOT="C:/Users/a/tools/godot/Godot_v4.7.2-stable_win64_console.exe"`
- 이 명령은 사람이 부를 때만 실행한다. 한 번 부르면 일을 하나 가져와 끝까지 하고 퇴근(run_finish)한다.
