# 처음 설정

## 1. Supabase 프로젝트

1. [supabase.com/dashboard](https://supabase.com/dashboard)에서 **New project**를 만든다. 이름 예: `danbi-game-office-2`, 지역 `Northeast Asia (Seoul)`.
2. **SQL Editor**에서 `supabase/migrations/0001_init.sql` 내용을 통째로 붙여 넣고 실행한다.
3. 대표 메일을 등록한다 (SQL Editor):
   ```sql
   insert into ceo_emails(email) values ('대표메일@example.com');
   ```
4. **Authentication → URL Configuration**
   - Site URL: `https://thstjdals09-lang.github.io/danbi-game-office-2/`
   - Redirect URLs에 같은 주소와 로컬 확인용 `http://127.0.0.1:5173/`를 추가
5. **Project Settings → API**에서 `Project URL`과 `anon public` 키를 복사해 `config.js`에 넣고 push한다.
   - `service_role` 키는 config.js나 저장소에 넣지 않는다.

## 2. GitHub Pages

저장소 **Settings → Pages → Source**를 **GitHub Actions**로 둔다. 이후 `main`에 push할 때마다 CI가 게임을 검사하고 배포한다.

## 3. 부서 예약 작업

`prompts/`의 네 프롬프트에서 `iqeqcnetdsusqkkxvver`를 실제 프로젝트 ref로 바꾸고 예약 작업으로 등록한다.

| 부서 | 파일 | 권장 주기 | 필요한 연결 |
| --- | --- | --- | --- |
| 아이디어 연구소 | `prompts/idea-lab.md` | 하루 1~2회 | Supabase |
| 기획실 | `prompts/planner.md` | 매시간 | Supabase |
| 빌드실 | `prompts/builder.md` | 매시간 | Supabase, GitHub 쓰기 |
| 검수실 | `prompts/qa.md` | 매시간 | Supabase, GitHub 읽기 |

부서들은 DB 함수(`run_start`, `claim`, `submit_*`, `run_finish`)로만 상태를 바꾼다. 함수는 Supabase 연결(SQL 실행)로 `select 함수(...)` 형태로 호출한다.
