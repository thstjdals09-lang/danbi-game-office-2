# 단비의 게임회사2

AI 부서들이 예약 작업으로 게임을 만들고, 대표는 고르고 플레이하고 판정만 하는 게임 회사.
1회사([Queenrain9/danbi-game-office](https://github.com/Queenrain9/danbi-game-office))와 별개로 처음부터 다시 설계했다.

```
아이디어 연구소 → 대표 분류 → 기획실(한 장 기획서) → 빌드실(Godot) → CI 자동 검사·Web export → 검수실 → 대표 플레이테스트
```

- 대시보드: GitHub Pages (`index.html`) — 결재함, 바로 플레이 진열대, 생산 라인, 부서 출근부
- 데이터: Supabase (`supabase/migrations/`) — 상태 변경은 DB 함수로만
- 게임: `games/<slug>/` Godot 4.7 프로젝트 — CI가 검사하고 `play/<slug>/`로 배포
- 부서 프롬프트: `prompts/` — 예약 작업에 붙여 넣어 쓴다
- 운영 규칙: [docs/OPERATING_MODEL.md](docs/OPERATING_MODEL.md)
- 처음 설정: [docs/SETUP.md](docs/SETUP.md)

## 폴더

| 경로 | 내용 |
| --- | --- |
| `index.html`, `app.js`, `config.js` | 대표 대시보드. Supabase 설정 전에는 예시 데이터로 보인다 |
| `supabase/migrations/` | 테이블, 권한, 제작 흐름 함수 |
| `tests/db.test.mjs` | DB 흐름·권한 시나리오 테스트 (`npm test`) |
| `games/_template/` | 새 게임 템플릿 |
| `games/first-lantern/` | 파이프라인 시험 게임 |
| `tools/new_game.py` | 템플릿으로 새 게임 만들기 |
| `tools/smoke.py` | 게임 자동 검사 (CI와 같은 명령) |
| `prompts/` | 아이디어 연구소, 기획실, 빌드실, 검수실 |

## 로컬에서

```bash
npm install
npm test                                   # DB 흐름 테스트
python tools/smoke.py games/first-lantern  # Godot 필요 (GODOT 환경변수나 PATH)
npm run serve                              # http://127.0.0.1:5173 대시보드
```
