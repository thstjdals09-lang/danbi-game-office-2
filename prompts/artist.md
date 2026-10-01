# 아트실 · 예약 작업 프롬프트

> 검수를 통과한 게임의 핵심 화면 하나를 고르고, 그 화면을 서로 다른 아트 방향 3가지(A·B·C)로 그려 진열장에 올린다.
> 제작 흐름을 막지 않는 옆 작업이다. 권장 모델: Sonnet 이상(이미지를 보고 판단해야 한다).

```
단비의 게임회사2의 아트실을 실행하세요.

목표: 대표가 "이 게임이 그림을 입으면 어떤 모습일까"를 한눈에 비교하고 방향을 고를 수 있게 한다.
세 장은 **같은 화면, 같은 구도, 같은 게임 요소**를 그리되 분위기·색·재질이 분명히 달라야 한다.
게임이 달라 보이면 실패다(없는 UI, 없는 캐릭터, 다른 규칙처럼 보이는 그림).

연결 자원
- Supabase 프로젝트 iqeqcnetdsusqkkxvver (SQL 실행: Supabase 커넥터의 execute_sql 등)
- 이미지 생성: Higgsfield 커넥터 (media_import_url, generate_image_batch, jobs_wait)
- GitHub thstjdals09-lang/danbi-game-office-2, main (읽기/쓰기)
- 기준 문서: docs/OPERATING_MODEL.md

=== 사전 확인: 저장소에 올릴 수 있는가 (일을 가져오기 전에) ===
git push --dry-run origin HEAD:main
- 실패(403 등)하면 아무 일도 가져오지 말고 바로 끝낸다:
  select run_start('artist'); 로 받은 run_id에 select run_finish('<run_id>', 'failed', 'push 권한 없음: <오류 한 줄>');

=== 0. 출근과 작업 가져오기 ===
1. select run_start('artist'); 로 run_id를 받는다. owner = 'artist:<run_id>'.
2. select * from claim_art('<owner>', 60);
   - 행이 없으면 run_finish('<run_id>', 'noop', '아트 작업할 게임 없음') 후 종료.

=== 1. 읽고 보기 ===
1. games/<slug>/design/GAME_DESIGN.md 의 2절(플레이어 판타지), 12절(피드백), 14절(비주얼 방향)을 읽는다.
   14절에 디자인실이 적은 "그림이 붙을 때의 방향"이 있으면 A안은 그 방향을 충실히 따른다.
2. games/<slug>/design/SCREENS.md 에서 화면별 요소를 확인한다.
3. games/<slug>/shots/*.png 를 **전부 열어 본다.** games/<slug>/BUILD.md 의 스크린샷 목록에서 각 장이 무엇인지 확인한다.

=== 2. 핵심 화면 고르기 ===
스크린샷 중 한 장을 고른다. 기준:
- 이 게임의 핵심 판단이 한 화면에 보인다(플레이어, 적/대상, 판단에 쓰는 정보가 함께 있다).
- 타이틀·결과 화면이 아니라 플레이 중 화면이다.
- 요소가 너무 적지도(빈 보드) 너무 많지도(연출이 겹친 순간) 않다.
고른 파일과 이유를 한두 문장으로 적어 둔다.

=== 3. 아트 방향 3가지 정하기 ===
- A: 디자인 14절의 방향(없으면 판타지에 가장 정직한 방향).
- B, C: A와 **축이 다른** 방향. 예: 재질(종이/금속/천), 시대·장소, 명암(어두운/밝은), 그림체(먹선/픽셀/점토/평면 벡터).
  색만 바꾼 변형은 안 된다.
- 각 방향: 이름(짧게), 설명(분위기·색·재질·그림체를 한두 문장), 화면 요소가 각각 무엇으로 그려지는지
  (예: 플레이어 = 먹선 검객, 메아리 = 푸른 잔상, 졸개 = 종이 인형, 벽 = 대나무 울타리).
- 세 방향 모두 지켜야 하는 것: 핵심 화면의 격자·배치·요소 수, 모바일 세로(또는 가로) 화면, 도형으로 구분되던 정보가
  그림에서도 구분됨(적 종류, 위험 표시, 순서 숫자).

=== 4. 이미지 생성 ===
1. 핵심 화면을 참조 이미지로 올린다:
   media_import_url(url = "https://raw.githubusercontent.com/thstjdals09-lang/danbi-game-office-2/main/games/<slug>/<key_screen>")
2. generate_image_batch 로 3장을 한 번에 요청한다(index 0=A, 1=B, 2=C).
   - model: "gpt_image_2_5", aspect_ratio: 게임 방향에 맞게(세로 "9:16" 또는 가까운 값, 가로 "16:9")
   - medias: [{"role": "image", "value": "<media_id>"}] — 모델이 요구하는 role 은 models_explore(action="get") 로 확인
   - prompt(영어로): 참조 이미지와 같은 구도·같은 요소 배치의 모바일 게임 스크린샷을 <방향> 스타일로 다시 그린다.
     요소별로 무엇으로 그릴지, 색·재질·조명, "keep the same grid layout and element positions", "game UI screenshot",
     화면 안 글자는 넣지 않거나 최소로("no extra text").
   - use_unlim 은 넣지 않는다. 크레딧이 모자라면 생성하지 말고 run_finish(..., 'failed', '이미지 크레딧 부족') 후 release_art.
3. jobs_wait 로 끝날 때까지 기다린다. 결과 URL을 내려받는다:
   curl -L -o games/<slug>/art/A.png "<url>"  (B, C 도)
4. 세 장을 **직접 열어 본다.** 다음이면 그 장만 다시 생성한다(장당 최대 2번까지):
   - 참조와 구도가 다르다, 핵심 요소가 빠졌다, 다른 게임처럼 보인다, 세 장이 서로 비슷하다.
5. 핵심 화면도 복사해 둔다: cp games/<slug>/<key_screen> games/<slug>/art/key.png

=== 5. 기록과 커밋 ===
1. games/<slug>/art/ART.md:
   - 핵심 화면: 파일명과 고른 이유
   - 방향 A/B/C: 이름, 설명, 요소별 표현, 생성에 쓴 프롬프트 원문, 다시 생성했다면 이유
   - 스스로 본 한계(예: 숫자가 뭉개짐, 격자 칸 수가 다름)
2. games/<slug>/art/.gdignore 빈 파일을 둔다(Godot가 게임 리소스로 가져오지 않게).
3. games/<slug>/art/ 아래만 커밋하고 main에 push(작업 브랜치라면 git push origin HEAD:main).
   메시지: "<slug>: art — <A 이름> / <B 이름> / <C 이름>"

=== 6. 제출과 퇴근 ===
select submit_art('<game_id>', '<owner>', '{
  "key_screen": "shots/<파일>.png",
  "key_reason": "<왜 이 화면인지>",
  "directions": [
    {"id": "A", "name": "<이름>", "description": "<설명>", "image": "art/A.png"},
    {"id": "B", "name": "<이름>", "description": "<설명>", "image": "art/B.png"},
    {"id": "C", "name": "<이름>", "description": "<설명>", "image": "art/C.png"}
  ]
}'::jsonb, '<커밋 SHA>');
- ART_INVALID 면 메시지대로 고쳐 다시 제출한다.
select run_finish('<run_id>', 'success', '<제목> 아트 방향 3안: <A> / <B> / <C>', '<game_id>');

막혔을 때
- 스크린샷이 하나도 없으면: select release_art('<game_id>', '<owner>', '스크린샷 없음'); run_finish(..., 'blocked', '<제목>: 스크린샷이 없어 핵심 화면을 고를 수 없음')
- 이미지 도구/네트워크 오류: select release_art('<game_id>', '<owner>', '<오류 요약>'); run_finish(..., 'failed', ...)

하지 말 것
- games/<slug>/art/ 밖의 파일을 고치지 않는다(게임 코드, 설계 문서, 스크린샷).
- 테이블을 직접 INSERT/UPDATE 하지 않는다.
- 대표 대신 방향을 고르지 않는다(ceo_pick_art 는 대표의 일).
최종 응답은 짧게: 제목, 핵심 화면, 방향 세 이름, 커밋 SHA.
```
