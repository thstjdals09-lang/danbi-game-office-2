---
name: dgo2-builder
description: "단비의 게임회사2 빌드실: 기획 패키지를 Godot 게임으로 만들고 검사를 통과시킨다. 사용자가 '빌드실 실행', '빌드실 돌려'처럼 이 부서를 직접 부를 때만 쓴다."
disable-model-invocation: true
---

# 빌드실

원본: `prompts/builder.md` (빌드실 · 예약 작업 프롬프트). 이 파일은 `python tools/build_plugins.py` 가 만든다 — 직접 고치지 말 것.

> 기획 패키지를 Godot 4.7 게임으로 만든다. 규칙은 기획실의 검사(tests/smoke.gd)가 판정하고, 화면은 SCREENS.md와 스크린샷으로 스스로 확인한다. 한 번에 한 게임.
> 권장 모델: Opus.

아래 실행 문구를 그대로 따른다.

## 실행 문구

단비의 게임회사2의 빌드실을 실행하세요.

첫 빌드의 기준(대표가 정한 것): **내용은 적어도 된다. 대신 요소·구조·화면은 그림만 갈아 끼우면 바로 상용 게임이 될 수준이어야 한다.**
- 줄이는 것: 콘텐츠의 양(레벨·적·카드의 수), 규칙의 가짓수, 검사 항목 수.
- 줄이지 않는 것: 화면 구성, 화면 사이의 흐름, 요소의 크기와 자리, 버튼과 상태 표시, 움직임과 반응, 그림이 들어갈 자리.
화면이 시험판처럼 보이면(작은 도형, 글자 상자 버튼, 설명 글로 채운 빈자리, 뚝뚝 끊기는 전환) 검사를 다 통과해도 실패한 빌드입니다.

목표는 두 가지이고 둘 다 해야 합니다.
1. 규칙: 기획실이 쓴 tests/smoke.gd 를 한 글자도 바꾸지 않고 통과시킨다.
2. 화면과 손맛: design/SCREENS.md 의 요소·동작·피드백을 빠짐없이 만든다. 검사는 화면을 보지 못하므로,
   검사만 통과하고 화면이 비어 있는 빌드는 실패한 빌드다.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기/쓰기)
- 기준 문서: docs/OPERATING_MODEL.md 의 "게임 저장소 규칙"
- 참고 구현: games/first-lantern/ (그리기, 입력, 폰트, debug 훅의 모양)

=== 사전 확인: 저장소에 올릴 수 있는가 (일을 가져오기 전에) ===
git push --dry-run origin HEAD:main
- 실패(403 등)하면 아무 일도 가져오지 말고 바로 끝낸다:
  select run_start('builder'); 로 받은 run_id에 select run_finish('<run_id>', 'failed', 'push 권한 없음: <오류 한 줄>');
  작업물을 올릴 수 없는 상태에서 일을 시작하면 결과가 전부 사라진다.

=== 0. 출근과 작업 가져오기 ===
1. select run_start('builder'); 로 run_id를 받는다. owner = 'builder:<run_id>'.
2. select * from claim('builder', '<owner>', 120);   -- 빌드는 길다. 임대 120분
   - 행이 없으면 run_finish('<run_id>', 'noop', '빌드할 게임 없음') 후 종료.
   - attempt가 1이면 새 빌드, 2 이상이면 수리 빌드다(맨 아래 "수리 빌드").

=== 1. 읽기 (이 순서로, 끝까지) ===
1. design/FIRST_BUILD.md — **이번 빌드의 기준.** 범위, 규칙 처리 순서, 수치표, 콘텐츠 데이터, 상태 흐름, 테스트 인터페이스, 빌드실 메모, 기획실 관찰.
2. design/sim/*.py — 규칙의 **기준 구현.** FIRST_BUILD.md 가 가리키는 클래스/함수를 한 줄씩 읽는다.
3. tests/smoke.gd — 무엇이 어떤 값으로 검사되는지. 테스트 인터페이스가 실제로 어떻게 불리는지.
4. design/SCREENS.md — 화면별 요소, 동작, 피드백.
   design/mock/main.png (있으면 title.png, result.png 도)를 **열어 본다.** 빌드의 화면이 닿아야 할 모습이다(도형 시안).
5. design/spec.json 의 not_now — 만들지 않을 것.
6. design/GAME_DESIGN.md 는 FIRST_BUILD.md 가 절 번호로 가리키는 부분만(피드백, 비주얼 방향 등). 나머지는 이번 빌드 범위가 아니다.

=== 2. 구조 (이렇게 나눈다) ===
- scripts/rules.gd — 규칙만. RefCounted, 노드·그리기·시간·난수 시계 없음.
  - sim 코드의 함수와 1:1로 대응시키고, 함수마다 "sim.py <함수명> 대응" 주석을 단다.
  - 한 단계(턴/틱)를 진행하는 함수 하나가 규칙 전체를 끝까지 계산하고, **그 단계에 일어난 일의 목록(events)** 을 돌려준다
    (예: 이동, 명중, 처치, 막음, 피격, 등장, 층 클리어, 패배). 화면은 이 목록을 재생한다.
  - 동점 처리·처리 순서는 sim 과 글자 그대로 같게. "비슷하게"는 정답 재생 검사에서 반드시 어긋난다.
- scripts/content.gd — 콘텐츠 데이터를 FIRST_BUILD.md 의 형식 그대로 한 곳에.
- scripts/main.gd — 상태(TITLE/PLAY/RESULT 등), 입력, 그리기, 연출 재생.
  - 테스트 인터페이스의 속성은 rules 의 값을 그대로 내보낸다(이름·타입은 FIRST_BUILD.md 그대로).
  - 입력은 한 곳(누름/뗌 처리 함수)으로 모은다. 실제 터치와 debug_tap/debug_swipe/debug_press 가 같은 함수를 부른다.
  - 규칙 상태는 행동 확정 즉시 갱신되고, 연출은 그 뒤를 따라간다. 연출이 끝나길 기다려야 값이 바뀌는 구조는 금지.
- project.godot 은 화면 방향/크기 외에는 템플릿 그대로. 글자는 res://assets/fonts/NotoSansKR-Medium.ttf
  (ThemeDB.fallback_font 는 웹에서 한글이 깨진다). 입력은 InputEventScreenTouch / InputEventScreenDrag.

=== 3. 만드는 순서 ===
① 규칙 먼저
- rules.gd + content.gd + main.gd 의 테스트 인터페이스(화면은 아직 비어 있어도 된다)를 만들고 바로 검사한다:
  export GODOT="$(bash tools/install_godot.sh)"; python3 tools/smoke.py games/<slug>
- 정답 재생 검사가 어긋나면 눈으로 찾지 말고 **턴별로 비교**한다:
  design/first_build_replay.py(또는 sim)를 불러 같은 행동 순서의 턴별 상태를 출력하는 임시 스크립트를 쓰고,
  게임 쪽도 같은 형식으로 출력해 처음 달라지는 턴을 찾는다. 임시 스크립트는 커밋하지 않는다.
- 규칙 검사가 전부 통과한 뒤에 화면으로 넘어간다.

② 화면
- SCREENS.md 의 화면마다 "요소" 목록을 하나씩 전부 그린다. 도형·숫자·무늬로 구분되게(색에만 의존하지 않기).
- 화면 기준 크기와 배치 원칙(무엇이 위, 무엇이 엄지 영역)을 지킨다. 글자는 잘리거나 겹치지 않게.
- **주 화면은 SCREENS.md 맨 위의 구도(시선 순서, 주인공의 크기, 영역 비율)를 지킨다.** 주인공과 핵심 대상을 문서의 크기보다 작게 그리지 않는다.
  그리기 어렵다고 구도를 바꾸지 않는다(따라가는 화면을 작은 전체 판으로, 그림 단추를 글자 상자로).
- 문서에 없는 설명 글·기호 범례·숫자를 화면에 더하지 않는다. 빈자리가 남으면 비워 두지 말고 SCREENS.md 가 정한 배경을 그린다.
- **그림 자리**: SCREENS.md 의 그림 자리 표에 있는 요소는 전부 한 함수(예: draw_slot(id, rect, state))를 거쳐 그린다.
  res://assets/art/<id>.png (상태가 있으면 <id>_<state>.png)가 있으면 그 그림을 표의 크기에 맞춰 그리고, 없으면 임시 모양을 같은 자리·같은 크기로 그린다.
  이렇게 해 두면 그림 파일을 넣는 것만으로 화면이 바뀐다. 코드를 고쳐야 그림이 들어가는 구조는 금지.
  games/<slug>/ASSETS.md 에 표를 옮겨 적는다: id, 파일 이름, 크기, 상태, 지금 임시 모양인지 그림인지.
- **상용 수준의 화면 짜임**(그림이 없어도 지켜야 하는 것):
  · 여백과 정렬이 한 가지 간격 체계를 따른다(예: 8px 배수). 글자 크기는 3~4단계만 쓴다.
  · 누를 수 있는 것은 전부 눌림·꺼짐 상태가 있고, 누르면 0.1초 안에 반응이 보인다.
  · 화면 전환은 뚝 끊기지 않는다(0.2~0.4초의 넘어감). 결과·타이틀도 주 화면과 같은 공을 들인다.
  · 아무것도 누르지 않아도 화면에 움직임이 있다(SCREENS.md 가 정한 것).
  · 기기마다 다른 위아래 여백(안전 영역)에 중요한 것이 걸리지 않게 위 48px, 아래 32px 안쪽에 둔다.

③ 입력과 미리보기
- SCREENS.md "동작"대로. 문턱값(픽셀, 시간)은 문서의 숫자 그대로 상수로 둔다.
- 불가능한 행동의 반응, 연출 중 입력 무시도 문서대로.

④ 피드백과 연출
- SCREENS.md 피드백 표의 사건마다 표시를 만든다. events 를 순서대로 재생한다.
- 문서의 시간 수치(예: 히트스톱 0.08초, 한 턴 연출 0.9초 이내)를 지킨다.

⑤ 스크린샷으로 스스로 확인
- tests/shots.gd 를 쓴다(games/_template/tests/shots.gd 참고). debug 함수로 장면을 만들고 찍는다:
  SCREENS.md 의 화면마다 한 장 이상 + 주 화면의 핵심 순간 3장 이상 + **그림 자리 확인 한 장**
  (assets/art/ 에 아무 그림이나 하나를 임시로 넣어 그 자리의 모양이 그림으로 바뀌는 것을 찍고, 임시 그림은 지운다).
- python3 tools/screenshot.py games/<slug> → games/<slug>/shots/*.png 을 **직접 열어 본다.**
  **주 화면 스크린샷을 design/mock/main.png 와 나란히 놓고 본다.** 구도, 크기, 요소의 자리가 시안과 같아야 한다.
  시안보다 시험판처럼 보이면(말이 작다, 글자 버튼, 설명 글) 고치고 다시 찍는다.
  확인: SCREENS.md 의 요소가 다 있는가, 글자가 잘리거나 겹치는가, 한글이 네모로 깨지는가, 흑백으로 봐도 구분되는가,
  보드가 화면 위쪽에 있고 버튼이 엄지 영역에 있는가. 문제가 있으면 고치고 다시 찍는다.
- 기본 콘텐츠를 플레이해서는 안 나오는 장면(드문 규칙, 불가능한 행동의 반응, 미리보기)은 debug_load 같은 장면 함수로
  **작은 장면을 만들어** 찍는다. "정답 길에 그런 자리가 없어서 못 찍었다"는 이유가 되지 않는다.
- **찍은 파일을 전부 열어 파일 이름과 실제 화면이 같은지 대조한다.** 이름은 찍으려던 것이고 화면은 찍힌 것이다
  (벽인 줄 알고 민 쪽이 길이어서 "거절" 대신 "피격"이 찍히는 식). 여러 장을 한 번에 보려면 python3 tools/shots_sheet.py games/<slug>.
  그리기 코드를 고친 뒤에는 다시 찍고 다시 연다. BUILD.md 에는 실제로 연 만큼만 "열어 봤다"고 적는다.
- 찍을 수 없는 환경이면(화면도 xvfb 도 없음) 건너뛰고 BUILD.md 에 "스크린샷 못 찍음: <이유>"라고 적는다.

⑥ 덧붙이는 검사 tests/extra.gd (첫 빌드에서는 생략한다. 프로덕션 차수부터)
- smoke.gd 와 같은 형식("SMOKE PASS" 출력, quit(0|1)). tools/smoke.py 가 함께 실행한다.
- 실제 입력 경로(debug_swipe/debug_press/debug_tap)로 무작위 행동을 수백 번 넣어, 스크립트 오류 없이 상태가 항상 유효한지
  (체력 범위, 상태 전이, 결과 화면에서 다시 시작) 확인한다. 난수 시드는 고정한다.

⑦ 마지막 확인
- python3 tools/smoke.py games/<slug> 가 PASS (smoke.gd + extra.gd + 메인 씬 5초 실행 오류 0).

=== 4. 빌드 기록 BUILD.md ===
games/<slug>/BUILD.md (없으면 만들고, 있으면 맨 위에 이번 회차를 추가). 이 파일이 있어야 CI가 이 게임을 검사·배포한다.
- 빌드 회차, 기획 버전(spec_version), smoke 결과(통과한 check 수 / 전체)
- 구조: 파일별 역할 한 줄씩
- **SCREENS 대조표**: SCREENS.md 의 요소·동작·피드백·전환을 한 줄씩 옮기고 각각 ○(구현) / △(일부, 무엇이 빠졌는지) / ×(안 함, 이유).
  화면이 이 빌드의 본체이므로 첫 빌드에서도 쓴다. 주 화면의 주인공 크기(px)와 영역 비율이 문서와 같은지도 적는다.
- 스크린샷 목록(파일명과 무엇을 찍었는지) 또는 못 찍은 이유
- 기획과 다르게 만든 것(없어야 한다. 있으면 이유) / 알려진 한계
부풀리지 않는다. △와 ×를 숨기면 검수실이 찾아내고 불합격 처리한다.

=== 5. 커밋과 제출 ===
1. games/<slug>/ 아래만 커밋하고 main에 push(작업 브랜치라면 git push origin HEAD:main).
   메시지: "<slug>: build <attempt> — <한 줄 요약>"
2. 해시: git show <SHA>:games/<slug>/tests/smoke.gd | sha256sum
3. select submit_build('<game_id>', '<owner>', '<커밋 SHA>', <smoke 결과 true|false>,
                       '<무엇을 만들었는지, △×가 있으면 무엇인지, FAIL이면 어느 check가 왜>', '<tests sha256>');
   - TESTS_CHANGED 오류면 tests/smoke.gd 를 기획실 버전(git log 로 확인)으로 되돌려 다시 커밋한다.
   - smoke 가 FAIL인 채로 시간이 다 되면 false로 제출한다(빌드 대기로 돌아가고 다음 실행이 이어서 고친다).
4. select run_finish('<run_id>', 'success', '<제목> 빌드 <attempt>회차 · <SHA 7자리> · smoke <PASS|FAIL>', '<game_id>');

=== 반송 (고치지 말고 돌려보낸다) ===
다음 경우에만, 근거를 붙여서:
- 검사의 기대값이 FIRST_BUILD.md 규칙이나 sim 출력과 다르다 → 같은 장면을 sim 으로 돌린 출력을 근거로 붙인다.
- 검사가 테스트 인터페이스에 없는 것을 쓰거나, 인터페이스로는 확인할 수 없는 것을 요구한다.
- FIRST_BUILD.md 와 SCREENS.md 가 서로 모순된다.
  select send_back('<game_id>', '<owner>', 'planner', '<어느 must_work/절이 왜 틀렸는지, 근거>');
  (디자인 규칙 자체가 성립하지 않으면 'designer'). run_finish(..., 'blocked', ...)
"구현이 어렵다", "검사가 까다롭다"는 반송 사유가 아니다.

=== 수리 빌드 (attempt 2 이상) ===
- fix_notes(검수실 불합격 사유 또는 대표의 수정 요청)와 기존 BUILD.md 를 먼저 읽는다.
- 지적된 항목을 하나씩 고치고, BUILD.md 이번 회차에 "지적 → 조치"를 항목별로 적는다.
- 지적되지 않은 부분은 건드리지 않는다. 구조를 다시 짜지 않는다.

막혔을 때
- 시간 부족, GitHub/도구 오류로 커밋하지 못했으면:
  select release('<game_id>', '<owner>', '<오류 요약>'); run_finish(..., 'failed', ...)
  (임대가 만료되면 다음 실행이 이어받는다)

하지 말 것
- tests/smoke.gd, design/ 아래 문서와 스크립트, 다른 게임 폴더, tools/, .github/, supabase/ 를 고치지 않는다.
- not_now 에 있는 것을 만들지 않는다. 문서에 없는 규칙·수치를 지어내지 않는다.
- 테이블을 직접 INSERT/UPDATE 하지 않는다.
최종 응답은 짧게: 제목, 무엇을 만들었는지 한 줄, smoke 결과, SCREENS 대조표의 △× 개수, 커밋 SHA.

## 이 PC에서 손으로 돌릴 때

- 저장소: `C:\xampp\htdocs\danbi-game-office-2` (GitHub `thstjdals09-lang/danbi-game-office-2`, main). 같은 저장소에서 다른 세션이 동시에 커밋할 수 있다 — 내 게임 폴더만 `git add` 하고, push 전에 `git pull --rebase --autostash`.
- DB: Supabase 커넥터의 `execute_sql` (프로젝트 `iqeqcnetdsusqkkxvver`). 여러 문장을 한 번에 보내면 하나가 실패할 때 전부 취소된다.
- Godot: `export GODOT="C:/Users/a/tools/godot/Godot_v4.7.2-stable_win64_console.exe"`
- 이 명령은 사람이 부를 때만 실행한다. 한 번 부르면 일을 하나 가져와 끝까지 하고 퇴근(run_finish)한다.
