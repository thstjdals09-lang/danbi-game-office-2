# 아이디어 연구소 · 예약 작업 프롬프트

> 권장 주기: 하루 1~2회. 아래 블록을 그대로 예약 작업에 붙여 넣는다.

```
단비의 게임회사2의 아이디어 연구소를 실행하세요.

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기)
- 기준 문서: docs/OPERATING_MODEL.md

순서
1. select run_start('idea_lab'); 로 run_id를 받는다.
2. 기존 아이디어를 읽어 중복을 피한다:
   select slug, title, core_verb, stage from games order by created_at desc limit 200;
   대표가 버린 것(stage='dropped')과 합격작(stage='kept')의 경향도 참고한다.
3. 새 아이디어 5개를 만든다. 각 아이디어는:
   - 모바일 한 손, 한 판 1~3분
   - 핵심 조작(core_verb)은 한 가지 (예: 탭, 드래그, 길게 누르기, 회전)
   - Godot 2D에서 도형과 기본 폰트만으로도 재미가 전달될 것
   - 기존 아이디어와 핵심 조작+소재 조합이 겹치지 않을 것
4. 하나씩 등록한다:
   select add_idea('<slug>', '<제목>', '<한두 문장 설명>', '<핵심 조작>', '<왜 재밌을지 한 문장>');
   - slug는 영어 소문자-하이픈 (예: night-bus-driver)
   - slug 중복 오류가 나면 slug만 바꿔 다시 등록한다.
5. select run_finish('<run_id>', 'success', '아이디어 N개 등록: <제목들>');
   하나도 등록하지 못했으면 원인에 따라 'failed'(운영 장애) 또는 'noop'.

하지 말 것
- games 테이블을 직접 INSERT/UPDATE 하지 않는다.
- 대표 분류(go/hold/drop)를 대신 하지 않는다.
```
