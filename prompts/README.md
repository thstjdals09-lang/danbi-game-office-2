# 부서 프롬프트와 작업 등록 방법

부서의 일하는 방법은 이 폴더의 파일이 기준이다. 예약 작업(Claude 루틴 등)에는 **짧은 실행 문구**만 등록하고, 실행 문구가 이 파일을 읽어 그대로 따르게 한다. 그래서 프롬프트를 고칠 때는 이 폴더의 파일만 고치면 되고, 등록된 작업은 건드리지 않아도 된다.

## 부서 목록

| 부서 | 프롬프트 | 모델 | 권장 주기 (한국 시간) | 필요한 연결 | 파일을 고치는가 |
| --- | --- | --- | --- | --- | --- |
| 아이디어 연구소 | [idea-lab.md](idea-lab.md) | Opus | 하루 4회 (9·13·17·21시) | Supabase | 아니오 |
| 디자인실 | [designer.md](designer.md) | Opus | 2시간마다 | Supabase, 저장소 쓰기 | `games/<slug>/design/` |
| 기획실 | [planner.md](planner.md) | Opus | 매시간 | Supabase, 저장소 쓰기 | `games/<slug>/design/`, `tests/smoke.gd` |
| 빌드실 | [builder.md](builder.md) | Opus | 매시간 | Supabase, 저장소 쓰기 | `games/<slug>/` (검사·설계 문서 제외) |
| 검수실 | [qa.md](qa.md) | Sonnet | 매시간 | Supabase, 저장소 읽기 | 아니오 |
| 아트실 | [artist.md](artist.md) | Sonnet | 2시간마다 | Supabase, Higgsfield(이미지 생성), 저장소 쓰기 | `games/<slug>/art/` |
| 프로덕션 디자인실 | [prod-designer.md](prod-designer.md) | Opus | 2시간마다 | Supabase, 저장소 쓰기 | `games/<slug>/design/` |
| 프로덕션 기획실 | [prod-planner.md](prod-planner.md) | Opus | 매시간 | Supabase, 저장소 쓰기 | `games/<slug>/design/`, `tests/smoke.gd` |
| 프로덕션 개발실 | [prod-developer.md](prod-developer.md) | Opus | 매시간 | Supabase, 저장소 쓰기 | `games/<slug>/` (검사·설계 문서 제외) |

- 주기를 엇갈리게 둔다(예: 기획실 :55, 빌드실 :20, 검수실 :40). 빌드 후 CI가 끝난 뒤에 검수실이 오게 하기 위해서다.
- 프로토타입 부서(디자인실·기획실·빌드실)는 1차 빌드만, 프로덕션 부서는 합격한 게임의 2차 이상만 가져간다. 검수실과 아트실은 공통이다.
- 부서는 전부 DB 함수로만 상태를 바꾼다(`run_start`, `claim`, `submit_*`, `send_back`, `release`, `escalate`, `run_finish`).

## 검증 상태 (2026-10-01)

"메아리 발자국"(`games/echo-step-tactics`)을 이 프롬프트들로 아이디어 → 디자인 → 기획 → 빌드 → 검수 → 플레이 대기까지 한 번 끝까지 진행했다.

| 부서 | 어떻게 돌려 봤나 | 결과 |
| --- | --- | --- |
| 아이디어 연구소 | Claude 클라우드 루틴 | 정상 (입고 2개) |
| 디자인실 | Claude 클라우드 루틴 | 설계는 정상. 저장소에 올리는 권한(Claude GitHub App)이 없어 올리지 못함 → 권한 해결 필요 |
| 기획실 | 로컬 세션이 프롬프트대로 수행 | 정상. 얻은 교훈을 프롬프트에 반영함 |
| 빌드실 | 로컬 세션이 프롬프트대로 수행 | 정상 (검사 78개 통과, 반송 1회 발생·처리) |
| 검수실 | 로컬 세션이 프롬프트대로 수행 | 정상. 단 빌드한 세션이 검수해 독립 검수는 아니었음 |
| 아트실 | 로컬 세션이 프롬프트대로 수행 | 정상. Higgsfield `gpt_image_2_5` 3장, 총 1.5 크레딧. 다시 생성한 장 없음 |

### 새 디자인 두 개 수동 실행 (2026-10-01)

디자인실이 올린 두 게임을 이 프롬프트대로 기획실 → 빌드실 → 검수실 순서로 손으로 돌렸다(예약 없이). 둘 다 플레이테스트까지 갔다.

| 게임 | 기획 | 빌드 | 검수 | 걸린 반송·불합격 |
| --- | --- | --- | --- | --- |
| 불길 속으로 `backdraft-crew` | v2, 검사 12항목 166 check | 2회차 | 2회차 pass | 빌드실 → 기획실 반송 1회(검사의 시작 상태 기대값이 콘텐츠와 달랐다), 검수 불합격 1회(스크린샷 2장이 이름과 다른 화면) |
| 같은 하루 `loop-village` | v1, 검사 12항목 196 check | 1회차 | pass | 없음 |

이 실행에서 프롬프트에 더한 것
- planner.md: 시작 상태의 기대값도 replay 출력에서 옮긴다 / 성공했을 때 화면에 무엇이 보이는지 확인한다
- builder.md: 안 나오는 장면은 작은 장면을 만들어 찍는다 / 찍은 파일을 전부 열어 이름과 대조하고, 연 만큼만 적는다
- qa.md: 스크린샷 이름 대조를 1차 빌드에도 적용한다

남은 약점: 검수를 빌드한 세션이 했다(독립 검수가 아니다). DB 는 Supabase 커넥터로 불렀다(비밀번호 없이 된다).

### 프롬프트 재정비 (2026-10-02) — 아직 실제로 돌려 보지 않음

대표 지적 세 가지에 따라 고쳤다. 이 판으로 게임을 처음부터 만들어 본 적은 아직 없다.

| 지적 | 고친 곳 |
| --- | --- |
| 게임마다 "위에서 본 판 위의 작은 말"만 나온다 | idea-lab: visual 점수가 주 화면의 매력과 구도를 보고, 이미 만든 게임과 구도가 같으면 낮게. designer: 구도 후보 셋 이상 비교("그리기·검사하기 쉽다"는 이유 금지), 움직임·손맛 게임은 시뮬레이션 생략이 기본. planner: 시뮬레이션 없는 게임은 입력 기록 재생으로 검사 |
| "완성되면 이런 모습"이 빈약하다. 와이어프레임 설계가 부족했다 | designer 13절에 **주 화면 설계**(시선 순서, 주인공, 구도 비교, 크기 12% 이상, 글 대신 모양과 움직임, 그림 단추, 빈자리, 완성판 장면 묘사). planner·builder 는 그 구도를 바꾸지 못한다. qa 는 구도가 문서와 다르면 불합격. artist 는 그대로다 — 스크린샷을 기반으로 그린다(대표 결정). 스크린샷이 좋아지도록 앞 단계를 고친 것이다 |
| 플레이테스트까지 오는 일이 점점 무거워진다 | 첫 빌드만 가볍게: 검사 4~6항목(경계 검사 없음), 스크린샷 6장 안팎, extra.gd 생략, 대조표 대신 "안 만든 것·다르게 만든 것"만, 검수는 CI·깨짐·구도·not_now 만. 프로덕션 차수(2차 이상)는 그대로 꼼꼼하게 |

**첫 빌드의 기준 (대표, 2026-10-02)**: 내용은 적어도 된다. 요소·구조·화면은 그림만 갈아 끼우면 바로 상용 게임이 될 수준이어야 한다.
그래서 "첫 빌드 가볍게"는 **규칙·콘텐츠 쪽만** 가볍게다(검사 4~6항목, 경계 검사·무작위 입력 검사 없음). 화면 쪽은 오히려 엄격해졌다:
디자인실의 요소 표 → 기획실의 그림 자리 표(id, 크기, 상태) → 빌드실이 그 id 로 그림 파일을 찾아 그리는 구조(`assets/art/<id>.png`, `ASSETS.md`),
상용 수준의 화면 짜임(간격 체계, 눌림 상태, 전환, 대기 중 움직임, 안전 영역) → 검수실은 시험판처럼 보이면 불합격.
위 표의 "스크린샷 6장 안팎, 대조표 대신…"은 이 기준으로 바뀌어 더는 맞지 않는다(스크린샷과 대조표는 첫 빌드에서도 한다).

### 합격 뒤(프로덕션 루프) 검증

메아리 발자국을 복제한 시험용 게임(`games/echo-step-lab`)을 합격 처리하고 2차를 끝까지 돌려 봤다. 전부 로컬 세션이 프롬프트대로 수행했다(클라우드 루틴으로는 아직 돌려 보지 않았다).

| 부서 | 결과 |
| --- | --- |
| 프로덕션 디자인실 | 대표 메모("제자리에서 베기만 해도 깨진다")를 시뮬레이션으로 재현하고 규칙 하나(칼 하나)를 바꿈. 결정 요청 2건 등록 |
| 프로덕션 기획실 | 검사 M13~M18 추가. 1차 검사 중 기대값이 바뀐 것은 M1·M9·M10뿐 |
| 프로덕션 개발실 | 1회차: 검사 133개 통과(1차 회귀 86 + 2차 47). 2회차: 검수 지적 수리 |
| 검수실 | 1회차 불합격(스크린샷 한 장이 이름과 다른 화면을 찍음, 빌드 기록이 사실과 다름) → 2회차 합격. 빌드한 세션이 검수해 독립 검수는 아님 |

**3차도 같은 프롬프트로 끝까지 돌렸다**(폭탄병, 캠페인 10층, 되감기). 대표 메모 없이 지난 빌드의 사실과 확정된 결정 두 건으로 범위를 정했고, 규칙을 바꾸지 않고 콘텐츠 기준(본편 층은 1수 앞 봇이 다친다)으로 풀었다. 검사 198개(이전 차수 회귀 133 + 3차 65). 검수는 또 1회차 불합격(이름과 다른 스크린샷) → 2회차 합격. 1차부터 있던 결함(층을 깬 뒤 다음 층 안내가 입력으로 넘길 때만 띄)을 이번에 찾아 고쳤다.

**4차는 실제 대표 메모로 돌렸다**("아트가 없는 걸 고려해도 너무 심심하게 보인다. 해결은 단순하지 않다"). 디자인실이 로드맵의 4차(저장·층 선택)를 미루고 "보는 맛"으로 차수를 바꿨다: 스크린샷을 재는 도구(`design/visual_audit.py`)로 "대기 중 움직임 0%, 두 색이 화면의 85~96%"를 재현하고 목표를 정함. 규칙 변경 0. 기획실은 연출 배선을 읽는 인터페이스(`last_fx` 등)로 검사 M26~M32를 씀. 개발실 → 기획실 **반송 1회**(검사가 짧은 밀기를 되감기 버튼 위에서 함). 검사 238개(회귀 198 + 4차 40), 검수 1회차 합격.

얻은 교훈은 프롬프트에 반영했다: 대표가 말한 플레이를 흉내 내는 봇부터 만들기, 규칙은 한 번에 하나, 검사 장면은 sim으로 찾기, 기존 스크린샷을 `tools/shots_diff.py`로 전부 비교하기, CI 상태가 빌드 커밋이 아닌 뒤 커밋에 붙는 경우.

예약을 켜기 전에 확인할 것
1. 클라우드 루틴이 저장소에 push할 수 있는가 (`git push --dry-run origin HEAD:main`). 지금은 403.
2. 클라우드 환경에서 Godot 설치(`tools/install_godot.sh`)와 `tools/smoke.py`가 도는가.
3. 클라우드 환경에서 스크린샷(`tools/screenshot.py`, xvfb 필요)이 되는가. 안 되면 빌드실은 건너뛰고 기록만 남긴다.

## 플러그인 (부서마다 하나)

부서 프롬프트 9개를 Claude Code 플러그인으로도 묶어 두었다. 예약(루틴) 없이 사람이 한 줄로 부를 때 쓴다.

| 명령 | 부서 |
| --- | --- |
| `/dgo2-idea-lab` | 아이디어 연구소 |
| `/dgo2-designer` | 디자인실 |
| `/dgo2-planner` | 기획실 |
| `/dgo2-builder` | 빌드실 |
| `/dgo2-qa` | 검수실 |
| `/dgo2-artist` | 아트실 |
| `/dgo2-prod-designer` | 프로덕션 디자인실 |
| `/dgo2-prod-planner` | 프로덕션 기획실 |
| `/dgo2-prod-developer` | 프로덕션 개발실 |

- 원본은 여전히 `prompts/<부서>.md` 다. 프롬프트를 고친 뒤 `python tools/build_plugins.py` 를 돌리면 `plugins/dgo2-<부서>/SKILL.md` 와 `.claude-plugin/marketplace.json` 이 다시 만들어진다. 플러그인 쪽을 직접 고치지 않는다.
- 설치: `claude plugin marketplace add <이 저장소 경로 또는 GitHub 주소>` 뒤 `claude plugin install dgo2-<부서>@danbi-game-office-2`. 고친 뒤에는 `claude plugin marketplace update danbi-game-office-2` 와 `claude plugin update dgo2-<부서>@danbi-game-office-2`.
- 사람이 부를 때만 실행된다(`disable-model-invocation: true`). 대화 중에 Claude 가 알아서 부서를 돌리지 않는다.
- 한 번 부르면 일을 하나 가져와 끝까지 하고 퇴근한다. 플러그인으로 실제 한 바퀴를 돌려 본 적은 아직 없다(설치와 형식 검사까지만 확인).

## 등록할 실행 문구

공통 설정
- 저장소: `https://github.com/thstjdals09-lang/danbi-game-office-2`
- 연결: Supabase 커넥터 (project_id `iqeqcnetdsusqkkxvver`). 아트실만 Higgsfield 커넥터 추가
- 이미지 생성 비용: 게임 하나당 3장, 약 1.5 Higgsfield 크레딧(다시 생성하면 장당 0.5씩 추가)
- 도구: Bash, Read, Glob, Grep (+ 파일을 고치는 부서는 Write, Edit)

아래에서 `<부서>`, `<파일>`, `<한 줄 요약>`만 바꿔서 쓴다.

```
당신은 단비의 게임회사2의 <부서>입니다.

저장소 prompts/<파일> 을 읽고, 그 안의 코드 블록 지시를 처음부터 끝까지 그대로 수행하세요.
<한 줄 요약>
기준 문서는 docs/OPERATING_MODEL.md 입니다.

DB 접속: Supabase 커넥터의 execute_sql 도구를 project_id "iqeqcnetdsusqkkxvver" 로 사용합니다.
프롬프트의 SQL을 이 도구로 실행하세요. 테이블을 직접 INSERT/UPDATE 하지 마세요.

할 일이 없으면 run_finish(..., 'noop', ...) 후 바로 끝내세요.
도구나 권한 오류가 나면 오류 내용을 그대로 보고하세요.
```

| 부서 | `<파일>` | `<한 줄 요약>` |
| --- | --- | --- |
| 아이디어 연구소 | `idea-lab.md` | CREATOR(8 lens, 내부 후보 16~20개) → STRUCTURE(게임과 첫 조각을 따로) → 관문 → CRITIC → PRODUCER 단계를 건너뛰지 마세요. 후보는 첫 빌드가 아니라 완성판 기준으로 평가하세요. 코드를 바꾸거나 commit/push 하지 마세요. |
| 디자인실 | `designer.md` | 초안 → 비평(최소 2바퀴) → 규칙 시뮬레이션 → ROADMAP → check_design 점검 → 커밋 → submit_design 순서를 건너뛰지 마세요. games/<slug>/ 안만 바꾸고 main에 push하세요. |
| 기획실 | `planner.md` | 디자인 문서를 다시 쓰지 말고 첫 빌드 조각을 고르세요. 검사 기대값은 sim 코드로 계산하세요. games/<slug>/ 안만 바꾸고 main에 push하세요. |
| 빌드실 | `builder.md` | 기준은 design/FIRST_BUILD.md 와 SCREENS.md 입니다. tests/smoke.gd 와 design/ 은 바꾸지 마세요(해시로 대조됩니다). 틀렸다고 판단되면 send_back 으로 반송하세요. |
| 검수실 | `qa.md` | CI 결과, tests/smoke.gd 해시, 수치, BUILD.md 대조표, 스크린샷을 모두 확인하세요. 코드를 고치거나 commit/push 하지 마세요. |
| 프로덕션 디자인실 | `prod-designer.md` | 대표 메모와 지난 빌드의 사실을 근거로 이번 차수를 정하세요. 바뀌는 규칙은 sim으로 전·후 숫자를 확인하세요. 대표만 정할 수 있는 것은 ask_decision으로 올리고 기다리지 마세요. games/<slug>/design/ 안만 바꾸고 main에 push하세요. |
| 프로덕션 기획실 | `prod-planner.md` | 기존 검사는 지우지 말고 새 검사를 덧붙이세요(id는 이어서). 기대값은 sim 코드로 계산하세요. games/<slug>/design/ 과 tests/smoke.gd 만 바꾸고 main에 push하세요. |
| 프로덕션 개발실 | `prod-developer.md` | 기준은 design/BUILD_<N>.md 와 SCREENS.md 입니다. 기존 구조 위에 쌓고, tests/smoke.gd 와 design/ 은 바꾸지 마세요. 틀렸다고 판단되면 send_back 으로 반송하세요. |
| 아트실 | `artist.md` | 핵심 화면 하나를 고르고 같은 화면을 축이 다른 방향 3가지로 그리세요. 이미지는 Higgsfield 커넥터로 생성합니다. games/<slug>/art/ 안만 바꾸고 main에 push하세요. |

## 지금 등록되어 있는 Claude 루틴 (전부 예약 꺼짐)

https://claude.ai/code/routines 에서 켜고 끄거나 "지금 실행"을 누를 수 있다.

| 부서 | 루틴 ID | 등록된 주기 (UTC cron) |
| --- | --- | --- |
| 아이디어 연구소 | `trig_0157raWf8getzKJkbBoykfr7` | `0 0,4,8,12 * * *` |
| 디자인실 | `trig_01SJQvNkUGMZTArmiB713kjG` | `10 */2 * * *` |
| 기획실 | `trig_01KgCNANJn2gKqSkwaoKQArQ` | `55 * * * *` |
| 빌드실 | `trig_01HB4nkgg16z34p55tSBdkjN` | `20 * * * *` |
| 검수실 | `trig_019oUgGemyM5UgDWEurez6Sw` | `40 * * * *` |
| 아트실 | `trig_01HRhmRQLHMhQQX1uEF6CQyd` | `30 */2 * * *` |
| 프로덕션 디자인실 | `trig_01AaudpyX7UfqDjYxDHw95Pv` | `15 */2 * * *` |
| 프로덕션 기획실 | `trig_01NAHX74Y3BLT4JA4APNRnSs` | `50 * * * *` |
| 프로덕션 개발실 | `trig_016Ecbasga8qssmbxLpFK15E` | `25 * * * *` |
| (확인용) push 권한 확인 | `trig_0187yZGdpskodk8v868ZWwCG` | 수동 실행 전용 |

ChatGPT 예약 작업 등 다른 곳에 등록할 때도 같은 실행 문구를 쓰면 된다. 필요한 것은 Supabase SQL 실행과 저장소 읽기/쓰기 두 가지다.
