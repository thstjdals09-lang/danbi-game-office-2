# 프로덕션 개발실 · 예약 작업 프롬프트

> 이미 돌아가는 게임 위에 N차 빌드를 쌓는다. 기존 검사(회귀)와 새 검사를 모두 통과시키고, 바뀐 화면을 스크린샷으로 확인한다.
> 권장 모델: Opus.

```
단비의 게임회사2의 프로덕션 개발실을 실행하세요.

돌아가는 게임을 망가뜨리지 않고 넓히는 일입니다.
1. 규칙: tests/smoke.gd(기획실 작성)를 한 글자도 바꾸지 않고 전부 통과시킨다. 이전 차수의 검사도 그 안에 있다.
2. 화면과 손맛: design/SCREENS.md 에서 "(N차)"로 표시된 항목과 새 화면을 빠짐없이 만든다.
3. 구조: 지금의 구조(scripts/rules.gd 규칙 · main.gd 화면 · content.gd 데이터) 위에 쌓는다. 처음부터 다시 짜지 않는다.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기/쓰기)
- 기준 문서: docs/OPERATING_MODEL.md 의 "게임 저장소 규칙"

=== 사전 확인: 저장소에 올릴 수 있는가 (일을 가져오기 전에) ===
git push --dry-run origin HEAD:main
- 실패(403 등)하면 아무 일도 가져오지 말고 바로 끝낸다:
  select run_start('prod_developer'); 로 받은 run_id에 select run_finish('<run_id>', 'failed', 'push 권한 없음: <오류 한 줄>');

=== 0. 출근과 작업 가져오기 ===
1. select run_start('prod_developer'); 로 run_id를 받는다. owner = 'prod_developer:<run_id>'.
2. select * from claim('prod_developer', '<owner>', 120);
   - 행이 없으면 run_finish('<run_id>', 'noop', '개발할 게임 없음') 후 종료.
   - 행의 milestone = N. attempt 가 2 이상이면 이 차수의 수리 빌드다(맨 아래).

=== 1. 읽기 (이 순서로) ===
1. design/BUILD_<N>.md — **이번 빌드의 기준.** 범위, 바뀌는 규칙, 새 규칙, 콘텐츠, 테스트 인터페이스 추가분, 바뀐 기존 검사, 개발실 메모
2. design/sim/*.py — 규칙의 기준 구현(바뀐·새 규칙 부분을 한 줄씩)
3. tests/smoke.gd — 새 검사와, 기대값이 바뀐 기존 검사
4. design/SCREENS.md — "(N차)" 표시와 새 화면
5. games/<slug>/BUILD.md — 지금 구조와 알려진 한계. scripts/ 를 읽어 구조를 확인한다
6. design/spec.json 의 not_now

=== 2. 시작하기 전에 지금 상태를 잰다 ===
export GODOT="$(bash tools/install_godot.sh)"; python3 tools/smoke.py games/<slug>
- 실패하는 check 를 적어 둔다. 새 must_work 의 검사와 BUILD_<N>.md "바뀐 기존 검사"만 실패해야 정상이다.
- 그 밖의 기존 검사가 실패하면 고치기 전에 원인을 본다. 기획실이 기존 검사를 잘못 건드린 것이면 반송한다.

=== 3. 만드는 순서 ===
① 규칙: rules.gd 를 sim 과 대조해 바뀐 규칙·새 규칙을 넣는다. 함수마다 "sim.py <함수명> 대응" 주석을 유지한다.
   content.gd 에 새 콘텐츠를 BUILD_<N>.md 의 형식 그대로. 테스트 인터페이스 추가분을 main.gd 에.
   → smoke 를 돌려 규칙 검사가 전부 통과할 때까지. 어긋나면 design/build_<N>_replay.py 출력과 턴(단계)별로 비교한다.
② 화면·입력·피드백: SCREENS.md 의 "(N차)" 항목과 새 화면. events 에 새 사건을 더해 재생한다.
   기존 화면 요소의 배치·모양은 SCREENS.md 가 바꾸라고 한 것만 바꾼다.
③ 스크린샷: tests/shots.gd 에 새·바뀐 화면과 핵심 순간을 더한다. python3 tools/screenshot.py games/<slug>
   → shots/*.png 을 직접 열어 SCREENS.md 와 대조하고, 기존 화면이 깨지지 않았는지도 본다.
   찍을 수 없는 환경이면 건너뛰고 BUILD.md 에 적는다.
④ 덧붙이는 검사: tests/extra.gd 의 무작위 입력 검사가 새 화면·새 상태까지 지나가도록 넓힌다. 불변식에 새 규칙의 것을 더한다.
⑤ 마지막 확인: python3 tools/smoke.py games/<slug> 가 PASS.

=== 4. 빌드 기록 BUILD.md ===
맨 위에 "## <N>차 빌드 <attempt>회차 (기획 v<spec_version>)" 절을 추가한다(이전 기록은 그대로 둔다).
- smoke 결과(통과한 check 수 / 전체, 그중 이전 차수 회귀 검사 수)
- 바꾼 파일과 무엇을 바꿨는지(구조 변경이 있으면 이유)
- **SCREENS 대조표**: 이번 차수에 바뀐·추가된 항목만 ○/△/×. 그리고 "기존 항목 중 깨진 것: 없음 / 있음(무엇)"
- 이전 차수 대조표의 △× 중 이번에 해결한 것
- 스크린샷 목록(새로 찍은 것), 추가 검사가 찾은 것, 기획과 다르게 만든 것, 알려진 한계

=== 5. 커밋과 제출 ===
1. games/<slug>/ 아래만 커밋하고 main에 push(작업 브랜치라면 git push origin HEAD:main).
   메시지: "<slug>: build <N>차 <attempt> — <한 줄 요약>"
2. 해시: git show <SHA>:games/<slug>/tests/smoke.gd | sha256sum
3. select submit_build('<game_id>', '<owner>', '<커밋 SHA>', <smoke 결과 true|false>,
                       '<무엇을 넣고 바꿨는지, △×, FAIL이면 어느 check가 왜>', '<tests sha256>');
4. select run_finish('<run_id>', 'success', '<제목> <N>차 빌드 <attempt>회차 · <SHA 7자리> · smoke <PASS|FAIL>', '<game_id>');

=== 반송 (고치지 말고 돌려보낸다) ===
- 새 검사의 기대값이 BUILD_<N>.md 규칙이나 sim 출력과 다르다(같은 장면의 sim 출력을 근거로).
- "바뀐 기존 검사" 목록에 없는 기존 검사가, 코드를 바꾸기 전부터 실패한다.
- 테스트 인터페이스 추가분이 기존 것과 충돌한다. BUILD_<N>.md 와 SCREENS.md 가 모순된다.
  select send_back('<game_id>', '<owner>', 'planner', '<어느 must_work/절이 왜 틀렸는지, 근거>');
  (설계 규칙 자체가 성립하지 않으면 'designer'). run_finish(..., 'blocked', ...)

=== 수리 빌드 (attempt 2 이상) ===
fix_notes 와 BUILD.md 를 먼저 읽고, 지적된 항목만 고친다. BUILD.md 이번 회차에 "지적 → 조치"를 항목별로 적는다.

막혔을 때
- 시간 부족, GitHub/도구 오류: select release('<game_id>', '<owner>', '<오류 요약>'); run_finish(..., 'failed', ...)

하지 말 것
- tests/smoke.gd, design/ 아래 파일, 다른 게임 폴더, tools/, .github/, supabase/ 를 고치지 않는다.
- 이번 차수 범위 밖의 것을 만들지 않는다(BUILD_<N>.md "다음으로 미룸", not_now).
- 기존 테스트 인터페이스의 이름·타입·뜻을 바꾸지 않는다.
- 테이블을 직접 INSERT/UPDATE 하지 않는다.
최종 응답은 짧게: 제목, 차수, 넣은 것 한 줄, smoke 결과(회귀 포함), 대조표 △× 개수, 커밋 SHA.
```
