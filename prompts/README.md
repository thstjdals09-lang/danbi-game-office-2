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

- 주기를 엇갈리게 둔다(예: 기획실 :55, 빌드실 :20, 검수실 :40). 빌드 후 CI가 끝난 뒤에 검수실이 오게 하기 위해서다.
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

예약을 켜기 전에 확인할 것
1. 클라우드 루틴이 저장소에 push할 수 있는가 (`git push --dry-run origin HEAD:main`). 지금은 403.
2. 클라우드 환경에서 Godot 설치(`tools/install_godot.sh`)와 `tools/smoke.py`가 도는가.
3. 클라우드 환경에서 스크린샷(`tools/screenshot.py`, xvfb 필요)이 되는가. 안 되면 빌드실은 건너뛰고 기록만 남긴다.

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
| 아이디어 연구소 | `idea-lab.md` | CREATOR(8 lens, 내부 후보 16~20개) → STRUCTURE → CRITIC → PRODUCER 단계를 건너뛰지 마세요. 코드를 바꾸거나 commit/push 하지 마세요. |
| 디자인실 | `designer.md` | 초안 → 비평(최소 2바퀴) → 규칙 시뮬레이션 → ROADMAP → check_design 점검 → 커밋 → submit_design 순서를 건너뛰지 마세요. games/<slug>/ 안만 바꾸고 main에 push하세요. |
| 기획실 | `planner.md` | 디자인 문서를 다시 쓰지 말고 첫 빌드 조각을 고르세요. 검사 기대값은 sim 코드로 계산하세요. games/<slug>/ 안만 바꾸고 main에 push하세요. |
| 빌드실 | `builder.md` | 기준은 design/FIRST_BUILD.md 와 SCREENS.md 입니다. tests/smoke.gd 와 design/ 은 바꾸지 마세요(해시로 대조됩니다). 틀렸다고 판단되면 send_back 으로 반송하세요. |
| 검수실 | `qa.md` | CI 결과, tests/smoke.gd 해시, 수치, BUILD.md 대조표, 스크린샷을 모두 확인하세요. 코드를 고치거나 commit/push 하지 마세요. |
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
| (확인용) push 권한 확인 | `trig_0187yZGdpskodk8v868ZWwCG` | 수동 실행 전용 |

ChatGPT 예약 작업 등 다른 곳에 등록할 때도 같은 실행 문구를 쓰면 된다. 필요한 것은 Supabase SQL 실행과 저장소 읽기/쓰기 두 가지다.
