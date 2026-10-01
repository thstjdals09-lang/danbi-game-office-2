# 단비의 게임회사2 · 운영 규칙

이 문서가 회사의 기준이다. 부서 프롬프트(`prompts/`)와 DB 함수(`supabase/migrations/`)는 이 문서를 따른다.

## 원칙

**기획은 깊게, 첫 빌드 범위는 좁게, 일치 여부는 실행으로 판정한다.**

| 1회사 | 2회사 |
| --- | --- |
| 게임 설계 → 와이어프레임 → 구현 계약(블루프린트) → 빌드 → Gate. 단계마다 앞 문서를 다시 써서 옮김 | 디자인실이 깊은 설계를 쓰고, 기획실은 다시 쓰지 않고 **첫 빌드 조각을 고름** |
| 게임당 요구사항 93~156개를 한 번에 빌드·검수 | 깊은 설계는 ROADMAP으로 나눠 쌓고, 첫 빌드는 `must_work` **3~12개** |
| Gate가 문서끼리 비교해 일치 여부를 판정 | **기획실이 검사(`tests/smoke.gd`)를 먼저 쓰고**, CI가 실제로 돌려 판정. 빌드실은 검사를 못 바꿈(해시 대조) |
| 규칙 검증은 빌드 후 | 디자인실이 **Python 규칙 시뮬레이션**으로 Godot 전에 검증 |
| 플레이하려면 따로 Web export | 통과하면 자동 Web export, 대시보드에서 **바로 플레이** |
| 상태 규칙이 프롬프트와 DB에 흩어져 있음 | 상태 변경은 **DB 함수로만**. 규칙 위반은 DB가 거절 |

## 부서

| 부서 | 가져가는 단계 | 만드는 것 | 프롬프트 |
| --- | --- | --- | --- |
| 아이디어 연구소 | — | 아이디어(점수·승격 이유·검증 질문) | `prompts/idea-lab.md` |
| 디자인실 | `idea` | `design/GAME_DESIGN.md`(16절), `design/sim/`, `design/ROADMAP.md` | `prompts/designer.md` |
| 기획실 | `designed` | `design/FIRST_BUILD.md`, `design/SCREENS.md`, `design/spec.json`, `tests/smoke.gd` | `prompts/planner.md` |
| 빌드실 | `ready` | 게임 코드(`scripts/rules.gd` 규칙 · `main.gd` 화면), `BUILD.md`(SCREENS 대조표), `shots/*.png`, `tests/extra.gd` | `prompts/builder.md` |
| 검수실 | `qa` | 판정(CI·검사 파일 무결성·수치·대조표의 정직함·스크린샷) | `prompts/qa.md` |
| 아트실 | `playtest`·`kept` 중 아트가 없는 게임 (흐름을 막지 않는 옆 작업) | `art/A·B·C` 아트 방향 3안, `art/key.png`, `art/ART.md` | `prompts/artist.md` |
| 프로덕션 디자인실 | `kept` (합격작) | `design/PRODUCTION_<N>.md`, 고친 `GAME_DESIGN.md`·`sim/`·`ROADMAP.md`, 대표 결정 요청 | `prompts/prod-designer.md` |
| 프로덕션 기획실 | `designed` (2차 이상) | `design/BUILD_<N>.md`, 고친 `SCREENS.md`, 새 `spec.json`(이전 것은 `spec_m<k>.json`), `tests/smoke.gd`에 검사 추가 | `prompts/prod-planner.md` |
| 프로덕션 개발실 | `ready` (2차 이상) | 기존 코드 위에 N차 빌드, `BUILD.md`에 N차 기록 | `prompts/prod-developer.md` |
| 대표 | `playtest`, `held`, 결정 요청 | 플레이 판정, 판단, 부서가 추린 선택지 중 결정, 아트 방향 선택 | 대시보드 |

단계(`stage`)는 "어디에 있나", 차수(`milestone`)는 "몇 번째 빌드인가"다. 같은 단계라도 1차는 프로토타입 부서(디자인실·기획실·빌드실)가,
2차 이상은 프로덕션 부서가 가져간다. 검수실과 아트실은 차수와 상관없이 같다.

## 흐름

```
idea ─디자인실─▶ designing ─▶ designed ─기획실─▶ planning ─▶ ready ─빌드실─▶ building ─▶ qa ─검수실─▶ playtest ─대표─▶ kept
  ▲                              ▲                            ▲                          │                 │
  │                              │                            └──── 불합격 · 수정 요청 ───┴─────────────────┘
  └────── send_back('designer') ─┴──── send_back('planner') ──── (빌드실·검수실)
          (기획실·빌드실·검수실)          빌드 3회 실패 / 반송 3번째 → held(대표 판단)
```

| 단계 | 뜻 | 누가 다음으로 옮기나 |
| --- | --- | --- |
| `idea` | 디자인 대기 | 디자인실 `claim('designer')` — 대표 승인 없이 가져감 |
| `designing` | 디자인 중 | 디자인실 `submit_design` |
| `designed` | 기획 대기 | 기획실 `claim('planner')` |
| `planning` | 기획 중 | 기획실 `submit_spec` |
| `ready` | 빌드 대기 | 빌드실 `claim('builder')` |
| `building` | 빌드 중 | 빌드실 `submit_build` |
| `qa` | 검수 대기 | 검수실 `submit_qa` |
| `playtest` | 대표 플레이 대기 | 대표: keep / fix / drop |
| `kept` | 합격 · 다음 차수 대기 | 프로덕션 디자인실 `claim('prod_designer')` — 차수가 1 오른다. 대표가 `ceo_finish`로 끝낼 수도 있다 |
| `done` | 완료 (더 키우지 않음) | — |
| `held` | 대표 판단 필요 (`fix_notes`에 사유) | 대표: go / drop |
| `dropped` | 버림 | — |

- 공장은 대표 승인 없이 돈다. 대표의 결정은 게이트가 아니라 우선순위다.
  - ★(대시보드의 별)을 단 아이디어를 디자인실이 먼저 가져간다. 버리기는 가져가지 않는다.
  - 대표가 반드시 해야 하는 일은 플레이테스트 판정과 `held` 건 판단뿐이다.
- 대기열 순서: ★ → 중단된 작업(임대 만료) → 들어온 순.
- 대기 상한(`wip_limits`)은 **빌드 1개**만. 다른 단계에 필요해지면 `wip_limits`에 행만 추가한다.

## 합격 뒤: 프로덕션 루프

합격은 끝이 아니라 "로드맵의 다음 조각으로 넘어간다"는 뜻이다. 대표가 "여기까지"를 누를 때까지 같은 고리를 돈다.

```
kept ─프로덕션 디자인실─▶ designing(차수+1) ─▶ designed ─프로덕션 기획실─▶ planning ─▶ ready
     ─프로덕션 개발실─▶ building ─▶ qa ─검수실─▶ playtest ─대표─▶ kept(또 한 차수) | done(여기까지)
```

- 프로덕션 디자인실은 **대표의 합격 메모(`keep_notes`) → 지난 빌드에서 드러난 사실 → 로드맵** 순으로 근거를 삼아 이번 차수를 정한다.
- 기존 검사는 회귀 검사로 남는다. 차수마다 `must_work` id를 이어서 붙이고(1차 M1~M12 → 2차 M13~), 이전 기획서는 `design/spec_m<k>.json`으로 보관한다.
  `tools/check_design.py --milestone <N>`이 이전 차수 검사가 사라지지 않았는지 확인한다.
- 프로덕션 기획이 올라온 뒤 개발실 빌드가 올라오기 전까지는 새 검사가 실패하므로 CI의 `smoke/<slug>`가 빨갛고 Web 빌드가 내려간다. 정상이다.
- 실제 스토어 공개는 이 흐름에 없다(지금은 하지 않는다). 출시한다고 가정하고 쌓되, 비용이 드는 일은 출시할 만한 게임이 생겼을 때 정한다.

### 대표 결정 요청 (`decisions`)

수익 모델, 목표 플랫폼과 분량, 게임 이름, 톤처럼 **대표만 정할 수 있는 것**은 부서가 정하지 않는다.
선택지 2~4개(뜻·장점·단점)와 추천·이유를 `ask_decision`으로 올리고, 대표는 결재함에서 고르기만 한다(`ceo_decide`).

- 결정을 기다리느라 공장이 멈추지 않는다. 결정 전에는 추천안을 가정하고 진행하되, 가정했다는 것을 문서에 적는다.
- 같은 게임·같은 주제는 하나만 있다. 결정 전이면 새 내용으로 바뀌고, 결정된 뒤에는 부서가 바꿀 수 없다.
- 대표가 추천과 다르게 고르면, 다음 차수의 프로덕션 디자인실이 그 결정을 읽고 설계에 반영한다.

## 작업 규칙 (모든 부서 공통)

1. 시작하자마자 `select run_start('<role>')`로 출근부를 남기고, 끝날 때 반드시 `run_finish`로 닫는다.
   - `success`: 진행시킴 · `noop`: 할 일 없음 · `blocked`: 반송/대표 판단으로 넘김 · `failed`: 운영 장애
2. 일은 `claim`으로 가져온다. 돌려받은 `lease_owner`(= `<role>:<run_id>`)로만 제출한다. 임대는 기본 50분.
3. **운영 장애**(GitHub/Supabase/도구 오류, 시간 부족)는 게임 탓이 아니다 → `release`로 임대만 풀고 `failed`.
4. **앞 부서 산출물의 문제**(규칙 모순, 검사가 규칙과 다름)는 고치지 말고 `send_back`으로 반송한다.
   반송 사유는 다음 부서가 그대로 읽고 고칠 수 있게 구체적으로(문서 절 번호, must_work id, 근거).
5. **아이디어 자체가 성립하지 않으면** `escalate`로 대표에게 넘긴다.
6. 자기 단계의 파일만 고친다. 디자인실은 `design/`(GAME_DESIGN·ROADMAP·sim), 기획실은 `design/`(FIRST_BUILD·SCREENS·spec.json)와 `tests/`, 빌드실은 게임 코드와 `BUILD.md`.
7. 테이블을 직접 UPDATE/INSERT하지 않는다. 함수가 거절하면 그 메시지대로 고친다.
8. 결과를 부풀리지 않는다. 확인하지 않은 것을 확인했다고 적지 않는다.

## 아트 방향 (`games.art`)

- 아트실은 `claim_art`로 게임을 가져가 빌드 스크린샷(`shots/`) 중 **핵심 화면 하나**를 고르고, 같은 화면을 서로 다른 방향 3가지로 그려 `submit_art`로 제출한다.
- 세 장은 같은 구도·같은 요소를 그리되 재질·그림체·명암 같은 **축이 달라야** 한다. A는 디자인 14절의 방향을 따른다.
- 이미지는 `games/<slug>/art/`에 두고(게임 export에서 제외), 생성 프롬프트와 한계를 `art/ART.md`에 적는다.
- 대표는 대시보드 게임 상세에서 `ceo_pick_art`로 방향을 고른다. 라이브러리 카드의 썸네일은 고른 방향(없으면 A)이다.

## 디자인 문서 (`design/GAME_DESIGN.md`)

16개 절, 번호와 제목 고정(`tools/check_design.py --stage design`이 확인):

1 한 줄 정의 · 2 플레이어 판타지 · 3 핵심 판단과 조작 · 4 코어 루프 · 5 세션 구조 · 6 규칙 · 7 상태 모델 ·
8 콘텐츠 모델 · 9 난이도 곡선 · 10 성장과 메타 · 11 경제 · 12 피드백과 손맛 · 13 화면 흐름 · 14 비주얼 방향 ·
15 깊이 검증 · 16 리스크와 미해결 질문

- 15절에는 비평 라운드(발견한 약점 → 바꾼 설계)와 시뮬레이션 결론을 적는다.
- 규칙 시뮬레이션: `design/sim/*.py`(표준 라이브러리, 시드 고정, 5분 안에 끝남) + `design/sim/RESULTS.md`.
  점검 도구가 시뮬레이션을 다시 돌려 exit 0을 확인한다. 손맛이 핵심이라 시뮬레이션이 의미 없으면 `sim_status='skipped'`와 이유.

## 기획 패키지

- `design/FIRST_BUILD.md`: 범위 · 규칙 확정(수치표, 처리 순서) · 콘텐츠 · 상태 흐름 · **테스트 인터페이스** · 빌드실 메모 · 기획실 관찰
- `design/first_build_replay.py`: 디자인실의 sim 코드로 콘텐츠의 정답 순서와 규칙 장면의 기대값을 계산하는 스크립트. 검사의 기대값은 손으로 계산하지 않는다
- `design/SCREENS.md`: spec의 화면마다 `## <screen id> — <이름>` 절. 텍스트 와이어프레임, 요소, 동작, 피드백
- `design/spec.json`: DB `games.spec`과 같은 내용 (아래 형식)
- `tests/smoke.gd`: must_work마다 `check("M<n>", ...)`. 테스트 인터페이스의 이름만 사용. 규칙을 실제로 확인
- `tools/check_design.py --stage plan`이 위를 점검하고 `tests_sha256`을 출력. `submit_spec`에 커밋 SHA와 함께 제출

```json
{
  "one_liner": "꺼지기 전에 등불을 눌러 밝힌다",
  "orientation": "portrait",
  "controls": "화면 탭 한 가지",
  "screens": [
    {"id": "title", "what": "제목, 시작 안내, 최고 기록"},
    {"id": "play", "what": "등불들, 점수, 남은 시간, 목숨"},
    {"id": "result", "what": "점수, 최고 기록, 다시 하기"}
  ],
  "win_lose": "45초 버티면 끝. 3번 놓치면 끝",
  "must_work": [
    {"id": "M1", "text": "타이틀 화면에서 시작한다", "check": "실행 직후 state == TITLE"},
    {"id": "M2", "text": "탭하면 플레이가 시작된다", "check": "타이틀에서 탭 → state == PLAY"},
    {"id": "M3", "text": "등불을 누르면 점수가 1 오른다", "check": "등불 위치 탭 → score +1"}
  ],
  "not_now": ["사운드", "랭킹", "튜토리얼"]
}
```

DB가 거절하는 경우 (`validate_spec`): `one_liner`·`controls`·`win_lose` 비어 있음, `orientation`이 portrait/landscape 아님,
`screens` 1~6개 아님, `must_work` 3~12개 아님, id가 `M숫자`가 아니거나 중복, `text`·`check` 비어 있음.

## 게임 저장소 규칙

- 게임 하나 = `games/<slug>/` 하나 (Godot 4.7, GL Compatibility). `python tools/new_game.py`로 만든다.
- 화면 기준 크기: 세로 540×960, 가로 960×540.
- 글자는 `res://assets/fonts/NotoSansKR-Medium.ttf`(한글 전체 + 영문, OFL). Godot 기본 폰트는 웹에서 한글이 깨진다.
- 외부 에셋 없이 도형과 폰트로 시작한다. 에셋을 넣으면 `assets/`에 두고 출처를 `BUILD.md`에 적는다.

## CI

`main`에 push하면 `.github/workflows/ci.yml`이 돈다.

1. `npm test`: DB 함수 시나리오 테스트
2. 게임마다 `python tools/smoke.py games/<slug>`: import → 메인 씬 5초 실행(스크립트 오류 0) → `tests/smoke.gd` → (있으면) `tests/extra.gd`
   - `design/`이 있는데 `BUILD.md`가 없는 게임(빌드 전)은 건너뛴다.
3. 통과한 게임은 Web export → `play/<slug>/`
4. 커밋 상태 `smoke/<slug>`를 `success` 또는 `failure`로 남김
5. 대시보드와 `play/`를 GitHub Pages로 배포

검수실은 빌드 커밋의 `smoke/<slug>` 상태와 `tests/smoke.gd` 해시를 보고 판정한다.
