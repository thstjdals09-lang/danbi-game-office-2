# 검수실 · 예약 작업 프롬프트

> 빌드실과 독립적으로 검수한다. CI(기획실이 쓴 검사의 실행 결과), 검사 파일 무결성, 그리고 검사가 놓치는 부분(화면·규칙 수치·피드백)을 본다.
> 권장 모델: Sonnet.

```
단비의 게임회사2의 검수실을 실행하세요. 코드를 고치지 않습니다.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기, 커밋 상태 조회)
- 기준 문서: docs/OPERATING_MODEL.md

=== 0. 출근과 작업 가져오기 ===
1. select run_start('qa'); 로 run_id를 받는다. owner = 'qa:<run_id>'.
2. select * from claim('qa', '<owner>');
   - 행이 없으면 run_finish('<run_id>', 'noop', '검수할 빌드 없음') 후 종료.
3. 최신 빌드: select id, commit_sha, attempt, notes from builds where game_id='<game_id>' order by created_at desc limit 1;
   기획 정보: 받은 행의 spec, spec_commit, tests_sha256.
4. git fetch origin main 후 빌드 커밋 기준으로 읽는다: git show <sha>:games/<slug>/...

=== 1. 기계 확인 ===
- CI: curl -s https://api.github.com/repos/thstjdals09-lang/danbi-game-office-2/commits/<sha>/status
  에서 context가 "smoke/<slug>"인 상태.
  - success → ci_passed = true
  - failure → ci_passed = false (Actions 로그에서 실패 이유를 찾아 notes에 적는다)
  - 아직 없음/pending → 판정하지 않는다. release('<game_id>', '<owner>', 'CI 대기') 후 run_finish(..., 'noop', 'CI 대기')
  - CI 는 push 된 맨 끝 커밋에만 돈다. 빌드 커밋 뒤에 다른 커밋이 함께 올라가 빌드 커밋에 상태가 없으면,
    그 뒤 커밋 중 상태가 있는 가장 가까운 것을 본다. 단 git diff <빌드 sha> <그 sha> -- games/<slug> 가 비어 있어야 한다
    (게임 폴더가 그 사이에 바뀌지 않았어야 같은 빌드다). 어느 커밋의 상태를 봤는지 notes 에 적는다.
- 검사 파일 무결성: git show <sha>:games/<slug>/tests/smoke.gd | sha256sum 이 tests_sha256과 같은지.
  다르면 무조건 fail("빌드실이 검사 파일을 바꿈").

=== 2-가. 첫 빌드(milestone 1)의 확인 — 규칙은 가볍게, 화면은 엄격하게 ===
첫 빌드의 기준은 "내용은 적어도 되지만, 그림만 갈아 끼우면 상용 게임이 될 화면과 구조"다.
아래를 보고 판정한다(=== 2 === 의 나머지는 milestone 2 이상에만 적용).
- must_work 항목마다 ok = CI 에서 그 check 가 통과했는가. note 는 한 줄. 수치표와 상수의 대조는 하지 않는다.
- 스크린샷을 전부 연다: 화면이 깨지지 않았는가(글자 겹침·잘림, 한글 깨짐, 빈 화면), 파일 이름이 말하는 화면이 찍혀 있는가.
- **시험판처럼 보이면 fail**: 작은 도형 말, 글자만 있는 상자 버튼, 설명 글·범례로 채운 빈자리, 정렬이 어긋난 요소,
  제목만 놓인 타이틀·결과 화면. 어느 스크린샷의 무엇이 그런지 적는다.
- **그림 자리**: SCREENS.md 의 그림 자리 표의 id 가 코드에서 한 함수를 거쳐 그려지는가, ASSETS.md 가 있는가,
  그림을 넣은 스크린샷에서 그 자리가 실제로 그림으로 바뀌었는가. 코드를 고쳐야 그림이 들어가는 구조면 fail.
- BUILD.md 대조표의 ○ 중 5개를 골라 코드나 스크린샷에서 확인한다. ○인데 없으면 fail.
- design/mock/main.png 를 열어 주 화면 스크린샷과 나란히 본다(시안이 없는 예전 게임이면 SCREENS.md 로 본다).
- **주 화면이 SCREENS.md 의 구도대로인가**: 주인공과 핵심 대상의 크기, 영역 비율, 그림 단추. 문서에 없는 설명 글·범례가 화면을 채우고 있지 않은가.
  구도가 문서와 다르면 fail(대표가 보고 판단할 "완성되면 이런 모습"이 달라지기 때문이다).
- not_now 에 있는 것을 만들지 않았는가.

=== 2. 사람 눈 확인 (검사가 놓치는 것) — milestone 2 이상 ===
검사(smoke.gd)는 규칙만 본다. 검수실은 화면과 정직함을 본다.

must_work 항목마다 판정한다. ok=true 조건:
- 코드에 구현되어 있고, CI에서 해당 check가 통과했다.
- 기획 문서 규칙표의 수치가 코드 상수와 일치한다(다르면 ok=false, 파일:줄과 두 값을 적는다).
  기획 문서는 받은 행의 milestone 이 1이면 design/FIRST_BUILD.md, N(2 이상)이면 design/BUILD_<N>.md 다.
- 그 항목과 관련된 화면 요소가 SCREENS.md의 배치·동작·피드백대로다.
각 항목 note에 근거(파일:줄 또는 관찰한 것)를 짧게 적는다.

화면 확인(불합격 사유가 될 수 있다):
- BUILD.md 의 SCREENS 대조표를 읽는다. ×나 △가 SCREENS.md 의 핵심 요소(플레이에 필요한 정보, 입력 수단)면 fail.
- 대조표에서 ○라고 한 항목을 5개 이상 골라 코드에서 실제로 그리는지 확인한다. ○인데 없으면 fail("대조표가 사실과 다름").
- games/<slug>/shots/*.png 가 있으면 열어 본다(git show <sha>:games/<slug>/shots/<파일> > /tmp/x.png 후 이미지 읽기).
  SCREENS.md 요소가 보이는가, 글자가 잘리거나 겹치는가, 한글이 깨지는가, 배치 원칙(보드 위쪽, 버튼 엄지 영역 등)을 지켰는가.
  **파일마다 이름·BUILD.md 의 설명과 실제 화면이 같은지 본다**(1차 빌드도 마찬가지다). 이름과 다른 화면이 찍혀 그 항목을
  확인할 수 없거나, BUILD.md 가 "전부 열어 봤다"고 적었는데 그렇지 않은 것이 드러나면 fail. 많으면 python3 tools/shots_sheet.py games/<slug>.
- 스크린샷이 없으면 그 사실을 notes에 적고 코드로만 판정한다.
- milestone 이 2 이상이면(프로덕션 빌드): 판정할 must_work 는 이번 차수 spec 의 것이다. 추가로
  이전 차수 검사(design/spec_m<k>.json 의 id)가 smoke.gd 에 남아 있고 CI 에서 통과했는지,
  BUILD.md 의 "기존 항목 중 깨진 것"이 사실인지 확인한다:
    python3 tools/shots_diff.py games/<slug> --old <이번 차수 기획 커밋(spec_commit)> --new <빌드 sha>
  달라진 파일을 열어, 달라진 영역이 이번 차수에 바꾸기로 한 것인지, **파일 이름이 말하는 화면이 여전히 찍혀 있는지** 본다.
  "새로 생김"으로 나온 파일도 전부 열어 이름·BUILD.md 의 설명과 실제 화면이 같은지 본다.
  화면 전체가 바뀐 차수면 python3 tools/shots_sheet.py games/<slug> 로 모아서 전부 본다.
  BUILD.md 에 숫자 기준(측정 도구의 결과)이 적혀 있으면 같은 도구로 다시 재서 맞는지 확인한다. 재미·느낌은 판정하지 않는다(대표의 몫).
  기존 화면이 깨졌거나, 이름과 다른 화면이 찍혀 그 항목을 확인할 수 없거나, BUILD.md 의 설명이 사실과 다르면 fail.
- not_now 에 있는 것을 만들었거나 문서에 없는 규칙·수치를 넣었으면 fail.

=== 3. 제출 ===
select submit_qa('<game_id>', '<owner>', 'pass' 또는 'fail', <ci_passed>,
                 '[{"id":"M1","ok":true,"note":"..."}, ...]'::jsonb,
                 '<불합격이면 빌드실이 고칠 것을 구체적으로>', '<빌드 커밋의 smoke.gd sha256>');
- 모든 항목 ok + CI 통과 + 검사 파일 일치일 때만 pass. 아니면 fail.
- CHECKS_MISSING 오류면 빠진 항목을 채워 다시 제출한다.
select run_finish('<run_id>', 'success', '<제목> 검수 <pass|fail>', '<game_id>');

=== 반송 ===
빌드가 아니라 검사나 기획이 틀렸으면(예: 검사가 규칙표와 다른 값을 기대, must_work가 핵심 규칙을 빠뜨림):
  select send_back('<game_id>', '<owner>', 'planner', '<근거>'); run_finish(..., 'blocked', ...)

하지 말 것
- 코드를 고치거나 커밋하지 않는다.
- 재미/밸런스 판단은 대표의 몫이다.
- 테이블을 직접 INSERT/UPDATE 하지 않는다.
최종 응답은 짧게: 제목, 판정, 근거 한두 줄.
```
