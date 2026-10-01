# 단비의 게임회사2 · 운영 규칙

이 문서가 회사의 기준이다. 예약 작업 프롬프트(`prompts/`)와 DB 함수(`supabase/migrations/`)는 이 문서를 따른다.

## 1회사에서 바꾼 것

| 1회사 | 2회사 |
| --- | --- |
| 7단계 (아이디어 → 게임 설계 → 와이어프레임 → 구현 계약 → 빌드 → Gate → 플레이테스트) | 4개 부서 + 대표. 게임 설계, 와이어프레임, 구현 계약을 **한 장 기획서**로 합침 |
| 게임당 요구사항 93~156개 | 기획서의 `must_work` **3~10개** |
| Gate가 요구사항마다 증거 UUID를 만들어 정적 검수 | CI가 **실제로 실행해서** 검사 (`tests/smoke.gd`), 검수실은 항목별 확인 |
| 플레이하려면 따로 Web export | 통과하면 자동으로 Web export, 대시보드에서 **바로 플레이** |
| 상태 규칙이 프롬프트와 DB에 흩어져 있음 | 상태 변경은 **DB 함수로만**. 규칙 위반은 DB가 거절 |

## 흐름

```
idea ──대표 분류──▶ planning ──기획실──▶ ready ──빌드실──▶ building ──▶ qa ──검수실──▶ playtest ──대표──▶ kept
  │                                       ▲                                │                     │
  └─ hold / drop                          └──────── 불합격 · 수정 요청 ─────┴─────────────────────┘
                                                    (빌드 3회 실패하면 held → 대표 판단)
```

| 단계 | 뜻 | 누가 다음으로 옮기나 |
| --- | --- | --- |
| `idea` | 대표 분류 대기 | 대표: go / hold / drop |
| `planning` | 기획서 작성 대기 | 기획실 `submit_spec` |
| `ready` | 빌드 대기 | 빌드실 `claim('builder')` |
| `building` | 빌드 중 | 빌드실 `submit_build` |
| `qa` | 검수 대기 | 검수실 `submit_qa` |
| `playtest` | 대표 플레이 대기 | 대표: keep / fix / drop |
| `kept` | 합격작 | — |
| `held` | 대표 판단 필요 (`fix_notes`에 사유) | 대표: go / drop |
| `dropped` | 버림 | — |

- 대기열 순서: 대표 별표(★) 먼저, 그다음 그 단계에서 오래 기다린 순서.
- 대기 상한(`wip_limits`)은 기본으로 **빌드 1개**만 건다. 아이디어는 많이 쌓아 두는 게 정상이다. 다른 단계에 상한이 필요해지면 `wip_limits`에 행만 추가한다.

## 작업 규칙 (모든 부서 공통)

1. 시작하자마자 `select run_start('<role>')`로 출근부를 남기고, 끝날 때 반드시 `run_finish`로 닫는다.
   - `success`: 무언가 진행시킴 · `noop`: 할 일이 없었음 · `blocked`: 게임 자체 문제로 대표에게 넘김 · `failed`: 운영 장애
2. 일은 `claim`으로 가져온다. 돌려받은 `lease_owner`(= `<role>:<run_id>`)로만 제출할 수 있다. 임대는 기본 50분.
3. **운영 장애**(GitHub/Supabase/도구 오류, 시간 부족)는 게임 탓이 아니다 → `release`로 임대만 풀고 `run_finish(..., 'failed', ...)`.
4. **게임 자체의 문제**(기획이 모순, 구현 불가)만 `escalate`로 대표에게 넘긴다.
5. 테이블을 직접 UPDATE/INSERT하지 않는다. 함수가 거절하면 그 메시지대로 고친다.
6. 결과를 부풀리지 않는다. 확인하지 않은 것을 확인했다고 적지 않는다.

## 한 장 기획서 (`games.spec`)

```json
{
  "one_liner": "꺼지기 전에 등불을 눌러 밝힌다",
  "orientation": "portrait",
  "controls": "화면 탭 한 가지",
  "core_loop": ["등불이 나타남", "꺼지기 전에 탭", "놓치면 목숨 -1"],
  "screens": [
    {"id": "title", "what": "제목, 시작 안내, 최고 기록"},
    {"id": "play", "what": "등불들, 점수, 남은 시간, 목숨"},
    {"id": "result", "what": "점수, 최고 기록, 다시 하기"}
  ],
  "win_lose": "45초 버티면 끝. 3번 놓치면 끝",
  "session_seconds": 45,
  "art_direction": "어두운 남색 밤, 따뜻한 노란 불빛. 도형만으로 그림",
  "must_work": [
    {"id": "M1", "text": "타이틀 화면에서 시작한다", "check": "실행 직후 state == TITLE"},
    {"id": "M2", "text": "탭하면 플레이가 시작된다", "check": "타이틀에서 탭 → state == PLAY"},
    {"id": "M3", "text": "등불을 누르면 점수가 1 오른다", "check": "등불 위치 탭 → score +1"}
  ],
  "not_now": ["사운드", "랭킹", "튜토리얼"]
}
```

DB가 거절하는 경우 (`validate_spec`):
- `one_liner`, `controls`, `win_lose`가 비어 있음
- `orientation`이 `portrait` / `landscape`가 아님
- `screens`가 1~4개가 아님
- `must_work`가 3~10개가 아님, id가 `M숫자` 형식이 아니거나 중복, `text`나 `check`가 비어 있음

`must_work`는 "이게 안 되면 게임이 아니다"인 것만 적는다. 다듬기, 연출, 밸런스는 `not_now`나 대표 플레이테스트에서 다룬다.

## 게임 저장소 규칙

- 게임 하나 = `games/<slug>/` 하나 (Godot 4.7, GL Compatibility).
- 새 게임은 `python tools/new_game.py <slug> --title ... --pitch ... --orientation ...`으로 만든다.
- 화면 기준 크기: 세로 540×960, 가로 960×540.
- `games/<slug>/SPEC.md`: DB의 기획서를 사람이 읽을 수 있게 옮긴 것. 빌드실이 쓴다.
- `games/<slug>/tests/smoke.gd`: `must_work`마다 `check("M<n>", ...)`를 하나 이상 둔다. 입력은 메인 씬의 `debug_*` 훅으로 흉내 낸다.
- 글자는 템플릿에 들어 있는 `res://assets/fonts/NotoSansKR-Medium.ttf`(한글 전체 + 영문, OFL)로 그린다. Godot 기본 폰트는 웹에서 한글이 네모로 깨진다.
- 외부 에셋 없이 도형과 기본 폰트로 시작해도 된다. 에셋을 넣으면 `games/<slug>/assets/`에 두고 출처를 `SPEC.md`에 적는다.

## CI

`main`에 push하면 `.github/workflows/ci.yml`이 돈다.

1. `npm test`: DB 함수 시나리오 테스트
2. 게임마다 `python tools/smoke.py games/<slug>`: import → 메인 씬 5초 실행(스크립트 오류 0) → `tests/smoke.gd`
3. 통과한 게임은 Web export → `play/<slug>/`
4. 커밋 상태 `smoke/<slug>`를 `success` 또는 `failure`로 남김
5. 대시보드와 `play/`를 GitHub Pages로 배포

검수실은 빌드 커밋의 `smoke/<slug>` 상태를 보고 `submit_qa`의 `p_ci_passed`를 채운다.
