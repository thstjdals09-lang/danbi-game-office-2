# 아이디어 연구소 · 예약 작업 프롬프트 v2

> 1회사 Idea Lab Hourly Gate v0.2 구조(넓은 탐색 → 구조화 → 독립 비평 → 제작 가치 승격)를 회사2 제작 조건에 맞춘 것.
> 대표 취향은 반영하지 않는다. 오직 제작 가치로 고른다.
> 권장 주기: 하루 1~4회. 실행당 최대 4개 입고, 0개도 정상.

```
단비의 게임회사2의 아이디어 연구소 v2를 실행하세요.

목표는 원시 아이디어를 많이 쌓는 것이 아니라, 내부에서 충분히 넓게 탐색한 뒤
제작 가치가 높은 후보만 대표 분류 대기(stage='idea')에 입고하는 것입니다.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- 기준 문서: docs/OPERATING_MODEL.md

=== 0. 출근과 사전 조사 ===
1. select run_start('idea_lab'); 로 run_id를 받는다.
2. 기존 후보를 확인한다 (중복·유사 구조 판단용):
   select slug, title, pitch, core_verb, genre from games order by created_at desc limit 300;
   대표의 분류(go/hold/drop)는 다음 단계의 작업 우선순위일 뿐이다. 아이디어 생성이나 평가에 반영하지 않는다.

=== 회사2 제작 조건 (모든 단계의 기준) ===
- 모바일 세로 또는 가로, Godot 4.7 2D.
- 첫 playable은 빌드실의 AI 빌드 한 번(약 1시간)으로 핵심 재미를 검증할 수 있어야 한다.
- 첫 빌드는 도형, 색, 기본 폰트만으로도 핵심이 전달되어야 한다(그림·사운드는 합격 후).
- 핵심 규칙은 헤드리스 자동 검사(tests/smoke.gd)로 "된다/안 된다"를 확인할 수 있는 형태여야 한다.
- 기획실이 must_work 3~10개로 요약할 수 있을 만큼 핵심이 선명해야 한다.
  이것은 첫 빌드 범위의 제한이지 장르의 제한이 아니다. 경영, 전략, 덱빌딩, 추리 등도
  첫 빌드에서 검증할 핵심 고리 하나를 잘라낼 수 있으면 좋은 후보다.

=== A. CREATOR — 평가표를 보기 전에 탐색 공간부터 넓힌다 ===
Critic 점수를 의식해 안전한 후보만 만들지 마세요. 서로 다른 발상 출발점에서 후보를 만들어
게임 아이디어 공간을 넓게 샘플링하세요.

한 실행에서 내부 후보를 최소 16개, 가능하면 20개 내외 탐색합니다.
원시 후보와 탈락 후보는 DB에 저장하지 않고 출력하지도 않습니다.

다음 8개 ideation lens를 각각 써서 2개 이상씩 후보를 만드세요.
1) Mechanic-first — 조작, 규칙, 물리, 타이밍, 정보 제한, 입력 방식 등 행동 자체에서 시작
2) System-first — 경제, 생산, 자동화, 생태, 네트워크, 교통, 자원 흐름, 관계망, 조직 운영에서 시작
3) Fantasy-first — 플레이어가 어떤 존재/직업/역할이 되는가에서 시작
4) Conflict-first — 압박, 딜레마, 불완전한 정보, 시간 경쟁, 상충 목표, 위험-보상에서 시작
5) World-rule-first — 시간, 중력, 기억, 복제, 시야, 언어, 날씨, 물질 변화 등 세계의 특이한 법칙에서 시작
6) Character / Social-first — 관계, 협상, 오해, 신뢰, 역할 분담, 군중 행동, 캐릭터 반응에서 시작
7) Progression-first — 수집, 빌드, 조합, 성장, 변이, 덱/팀/도구 구성, 장기 메타에서 시작
8) Toy-first — 만지고 움직이고 배치하고 관찰하는 것 자체가 재미있는 상호작용에서 시작

여력이 있으면 exploration/discovery, management/tycoon, strategy/tactics, rhythm/performance,
survival/pressure, stealth/pursuit, deduction/investigation, deck/drafting/buildcraft,
asynchronous/social, narrative-systemic hybrid에서도 탐색하세요.

중요
- 각 lens에서 반드시 하나씩 승격할 필요는 없습니다.
- 최종 후보가 전부 같은 장르나 테마여도 정말 그것들이 가장 좋다면 허용합니다.
  diversity는 탐색의 폭을 넓히는 장치이지 승격 quota가 아닙니다.
- 특정 소재나 미학(괴물, 유령, 마법, 현실 직업, SF, 일상, 귀여운 동물 등)을 의도적으로 밀어내거나 밀어주지 마세요.
- 테마는 아이디어의 일부일 뿐이며 Hook/Visual 점수의 지름길이 아닙니다. 같은 테마라도 core gameplay가
  충분히 다르면 독립 후보이고, 다른 테마라도 core gameplay가 사실상 같으면 유사 후보입니다.
- "한 화면에서 한 번 조작하는 퍼즐"이 아닌 게임도 적극적으로 탐색하세요.

=== B. STRUCTURE PASS — 후보를 실제 게임으로 만든다 ===
가능성 있는 후보만 추려 다음을 정의하세요.
- player fantasy
- primary verb 또는 primary decision
- 반복되는 core loop
- success / failure 또는 meaningful outcome
- session structure (한 판 길이, 판과 판 사이)
- 왜 두 번째 판을 하고 싶은지
- 모바일에서 실제 입력 방식
- 첫 playable에서 무엇을 검증해야 하는지

분위기/세계관만 있는 아이디어, 한 번 보고 끝나는 기믹, 메뉴에서 선택지만 누르는 구조는
실제 반복 gameplay로 발전하지 못하면 탈락시키세요.

=== C. CRITIC — Creator와 독립적으로 공격적으로 평가 ===
Critic은 Creator의 의도를 변호하지 말고 냉정한 별도 관점에서 평가합니다.
각 후보를 0~100 정수로 평가합니다.
- hook: 한 문장만 듣고 해 보고 싶은가
- core_loop: 반복할수록 판단/손맛이 깊어지는가
- mobile_fit: 손가락 입력과 짧은 세션에 맞는가
- prototype: 회사2 제작 조건(AI 빌드 1회, 도형만, 자동 검사)으로 핵심을 검증할 수 있는가
- asset: 합격 후 그림/사운드 제작 규모가 현실적인가 (높을수록 현실적)
- visual: 도형만으로도, 그리고 나중에 그림이 붙었을 때 화면이 읽히고 매력적인가
- growth: 첫 빌드 뒤 콘텐츠·시스템으로 키울 여지가 있는가

다음 편향을 경계하세요.
- 직접 조작이라는 이유만으로 높은 점수 주기
- 특정 테마나 미학이라는 이유만으로 Hook/Visual을 자동 고평가 또는 저평가하기
- 작은 게임이라는 이유만으로 Prototype/Asset에 과도하게 높은 점수 주기
- 모든 후보를 88~95점대에 몰아넣기 — 약점이 분명하면 60~70점대를 적극적으로 쓰세요.

기존 games와 비교할 때 제목/테마가 아니라 상위 gameplay 구조가 사실상 같은지 확인하세요.
(예: 소재가 달라도 "관찰 → 드래그/회전 → 정답 위치에 맞춤 → 판정" 구조가 같으면 유사 후보)
유사하다는 이유만으로 자동 탈락시키지 말고, 새 후보가 훨씬 더 좋은 훅/규칙/확장성을 갖는지 비교하세요.

=== D. PRODUCER — 실제 제작 비용을 쓸 후보만 승격 ===
최종 승격은 실행당 최대 4개, 0개도 허용합니다. 각 승격 후보는 다음을 모두 만족해야 합니다.
- 한 문장으로 무슨 게임인지 설명 가능
- 반복 가능한 핵심 플레이/판단이 있음
- 단순 선택지 메뉴만 누르는 구조가 아님
- 모바일에서 실제 조작이 성립함
- 첫 Godot playable(AI 빌드 1회, 도형만)로 핵심 재미를 검증 가능
- 그림/사운드 제작 규모가 비현실적이지 않음
- 기존 후보의 단순 테마 스킨 교체가 아님
- 최소 하나의 강한 이유 때문에 제작 비용을 써 볼 가치가 있음
억지로 서로 다른 장르나 테마로 맞추지 마세요. Producer는 오직 제작 가치로 고릅니다.

=== E. 입고 ===
승격 후보마다 실행합니다:
select add_idea(
  '<slug>',          -- 영어 소문자-하이픈, 48자 이하 (예: afterimage-arena)
  '<게임명>',        -- 80자 이하
  '<한 줄 컨셉>',    -- 무슨 게임인지 한 문장, 300자 이하
  '<core action>',   -- primary verb 또는 primary decision (예: "궤적 그리기", "카드 드래프트"), 60자 이하
  '<player fantasy + 왜 두 번째 판을 하고 싶은지>',   -- 300자 이하
  '<genre>',         -- 예: action-tactics, management, deduction
  '{"hook":0,"core_loop":0,"mobile_fit":0,"prototype":0,"asset":0,"visual":0,"growth":0}'::jsonb,
  array['<제작 비용을 써 볼 이유>', '...']::text[],   -- 2~4개, 짧게
  '<다음 기획 단계에서 가장 먼저 검증할 핵심 의문 하나>'
);
- slug 중복 오류면 slug만 바꿔 다시 실행합니다.
- 입고 후 재조회로 실제 저장을 확인합니다. 실패한 후보를 입고 완료로 간주하지 마세요.
  select title, genre, idea_scores, next_test from games where slug in (...);

=== F. 퇴근 ===
- 입고가 있으면: select run_finish('<run_id>', 'success', '입고 N개: <게임명들>');
- 승격 없음: select run_finish('<run_id>', 'noop', '이번 회차 입고 없음');
- 도구/DB 오류로 입고하지 못했으면: select run_finish('<run_id>', 'failed', '<오류 요약>');

최종 응답은 매우 짧게 하세요.
- 성공: 줄마다 `Idea Lab 입고: <게임명> — <한 줄 컨셉>` (저장 확인된 것만)
- 승격 없음: `이번 회차 Idea Lab 입고 없음.`
원시 후보 목록, 탈락 후보, 내부 점수 비교표, 사고 과정은 출력하지 마세요.

하지 말 것
- games 테이블을 직접 INSERT/UPDATE 하지 않는다 (add_idea만 쓴다).
- 대표 분류(go/hold/drop)를 대신 하지 않는다.
- 코드를 고치거나 commit/push 하지 않는다.
```
