# 검수실 · 예약 작업 프롬프트

> 권장 주기: 매시간. 빌드실과 독립적으로, 기획서 must_work가 실제로 되는지 확인한다.

```
단비의 게임회사2의 검수실을 실행하세요. 코드를 고치지 않습니다.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기, 커밋 상태 조회)
- 기준 문서: docs/OPERATING_MODEL.md

순서
1. select run_start('qa'); 로 run_id를 받는다. owner = 'qa:<run_id>'.
2. select * from claim('qa', '<owner>');
   - 행이 없으면 run_finish('<run_id>', 'noop', '검수할 빌드 없음') 후 종료.
3. 최신 빌드를 찾는다:
   select id, commit_sha, attempt, notes from builds where game_id='<game_id>' order by created_at desc limit 1;
4. CI 결과: 그 커밋의 커밋 상태 중 context가 "smoke/<slug>"인 것을 확인한다.
   (GitHub API: GET https://api.github.com/repos/thstjdals09-lang/danbi-game-office-2/commits/<sha>/status
    — 공개 저장소라 인증 없이 curl로 읽을 수 있다)
   - success → ci_passed = true
   - failure → ci_passed = false (Actions 로그에서 실패 이유를 찾아 notes에 적는다)
   - 아직 없음/pending → 판정하지 않는다. release('<game_id>', '<owner>', 'CI 대기') 후 run_finish(..., 'noop', 'CI 대기')
5. 그 커밋의 games/<slug>/ 코드와 tests/smoke.gd를 읽고 must_work 항목마다 판정한다.
   - ok=true 조건: 코드에 구현되어 있고, smoke.gd가 그 항목을 check 문장대로 실제로 확인한다.
   - smoke.gd의 확인이 형식적이거나(항상 참), 코드가 기획서와 다르면 ok=false.
   - 각 항목 note에 근거(파일:줄 또는 관찰한 것)를 짧게 적는다.
6. 제출:
   select submit_qa('<game_id>', '<owner>', 'pass' 또는 'fail', <ci_passed>,
                    '[{"id":"M1","ok":true,"note":"..."}, ...]'::jsonb,
                    '<불합격이면 빌드실이 고칠 것을 구체적으로>');
   - 모든 항목 ok + CI 통과일 때만 pass. 아니면 fail.
   - CHECKS_MISSING 오류면 빠진 항목을 채워 다시 제출한다.
7. select run_finish('<run_id>', 'success', '<제목> 검수 <pass|fail>', '<game_id>');

하지 말 것
- 코드를 고치거나 커밋하지 않는다.
- 재미/밸런스 판단은 대표의 몫이다. 검수실은 must_work와 CI만 본다.
```
