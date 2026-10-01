# 메아리 발자국 — 아트 방향 3안

## 핵심 화면
- `shots/09-echo-blocks-arrow.png` (복사본 `art/key.png`)
- 고른 이유: 궁수의 화살을 메아리가 막는 순간. 플레이어, 메아리, 적 두 종류(궁수·졸개), 발자국 1·2·3, 줄어든 체력이 한 화면에 있고, 이 게임의 판타지인 "과거의 내가 지금의 나를 지킨다"(디자인 2절)가 그대로 보인다.
- 한계: 연출 순간(막음 파문)이라 적 의도 표시(화살표·빗금)는 보이지 않는다.

## 방향

| | 이름 | 분위기 | 플레이어 | 메아리 | 궁수 | 졸개 | 발자국 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A | 먹선 대나무 숲 | 밤의 대나무 숲 위 돌 격자, 먹색 바탕에 청록·주황 두 강조색. 붓 질감 | 먹선 검객 | 청록 잔상(먹 번짐) | 종이 인형 궁수 | 부적 종이 병정 | 청록 먹 도장 |
| B | 태엽 장난감 무대 | 따뜻한 등불 아래 나무 장난감 상자. 양철·황동·나무 재질 | 흰 법랑 양철 병정 | 유리로 된 투명 복제 | 황동 태엽 석궁 | 구리 태엽 로봇 | 황동 동전 |
| C | 네온 전술 보드 | 어두운 남색 위 발광 선으로 그린 평면 홀로그램. 날카롭고 차가움 | 흰 다이아 코어 | 시안 와이어프레임 + 육각 방패 | 주황 저격 드론 + 조준선 | 주황 돌격 드론 | 시안 조준점 마커 |

- A는 디자인 14절 "그림이 붙을 때의 방향"(먹선 검객, 푸른 잔상, 종이 인형 적, 먹색 + 청록 + 주황)을 그대로 따랐다.
- B와 C는 A와 축을 다르게 잡았다: 재질과 온도(B: 따뜻한 입체 장난감) / 그림체(C: 차가운 평면 벡터).

## 생성
- 도구: Higgsfield `gpt_image_2_5`, 9:16, quality medium, 참조 이미지 = 핵심 화면. 장당 0.5 크레딧, 총 1.5 크레딧. 다시 생성한 장 없음.
- 원본 PNG(752×1344)를 JPEG(품질 86)로 줄여 저장했다.

### 프롬프트 (공통 앞부분)
> Repaint this mobile tactics game screenshot as finished game art, keeping the exact same portrait layout: status bar at top (level, turn counter, five hearts with two filled), a 7x7 square grid board in the upper part, two large buttons at the bottom. Keep every game element in the same grid cell as the reference.

### A
> Style: East Asian ink wash painting (sumi-e) at night. The board is a grid of weathered stone tiles in a moonlit bamboo forest. The white circle (player) becomes a small ink-brushed swordsman seen from above. The translucent cyan circle with ripple (the echo) becomes a glowing teal ghostly afterimage of the same swordsman with ink bleeding edges, raising a spirit shield. The orange triangle at the top (archer) becomes a folded paper shikigami archer aiming downward. The orange square (grunt) becomes a square paper doll charm soldier. The small numbered circles 1, 2, 3 stay as teal ink footprint seals with clear numbers 1, 2, 3. Palette: ink black and charcoal, one teal accent for the echo, one orange accent for enemies and danger. Visible brush texture, rice paper grain. Clean readable mobile game UI, no extra text, no new characters, no extra UI panels.

### B
> Style: a warm handcrafted clockwork toy diorama, top-down view, soft warm lamp light, tin and brass materials, wooden toy-box board with a 7x7 grid of inlaid wooden squares. The white circle (player) becomes a small white enamel tin soldier swordsman seen from above. The translucent cyan circle with ripple (the echo) becomes a transparent pale-blue glass duplicate of the same tin soldier, glowing softly and blocking with a glass shield. The orange triangle at the top (archer) becomes a brass wind-up crossbow toy pointing downward. The orange square (grunt) becomes a boxy copper wind-up robot with a key on its back. The small numbered circles 1, 2, 3 become small brass coin tokens stamped with the numbers 1, 2, 3. Palette: warm browns, brass gold, cream, with pale blue for the echo and copper orange for enemies. Cozy tactile materials, slight depth of field. Clean readable mobile game UI, no extra text, no new characters, no extra UI panels.

### C
> Style: flat neon vector hologram tactics board, crisp geometric shapes with glowing outlines on a deep navy-black background, thin luminous grid lines, subtle scanline glow, minimal and sharp like a sci-fi command table. The white circle (player) becomes a bright white diamond-shaped core unit with a small blade glyph. The translucent cyan circle with ripple (the echo) becomes a cyan wireframe afterimage of the same unit with trailing motion lines and a hexagonal energy shield. The orange triangle at the top (archer) becomes an angular orange sniper drone with a thin targeting beam pointing downward. The orange square (grunt) becomes a blocky orange assault drone. The small numbered circles 1, 2, 3 become cyan holographic waypoint markers with clear numbers 1, 2, 3. Palette: navy black, white, electric cyan for the echo, hot orange for enemies. Clean readable mobile game UI, no extra text, no new characters, no extra UI panels.

## 스스로 본 한계
- 세 장 모두 요소의 위치와 구성은 핵심 화면과 같다. 다만 격자 칸 수가 정확히 7×7은 아니다(A는 가로 6칸, B·C는 가로 7칸 세로 7~8칸).
- A는 화면 안 한글이 일부 틀렸다("막음" → "막은", "오사" → "오차"). 방향을 보는 용도이며 실제 게임 화면이 아니다.
- B·C는 아래 띠의 처치 수 글자가 빠졌다.
- C에는 궁수의 조준선이 그려졌다(핵심 화면에는 화살만 있었다). 게임의 "조준 사선" 표시와 뜻이 같아 그대로 두었다.
