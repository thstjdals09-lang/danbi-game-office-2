extends RefCounted
## 캠페인 고정 층 10개. FIRST_BUILD.md(1~3층) + BUILD_2.md(4·5층) + BUILD_3.md(6~10층) "콘텐츠"의 형식과 값 그대로.
## "enemies"는 이 순서대로 id 0, 1, ... / "spawns"는 [예고 턴, 종류, 칸]. 종류: W 졸개, A 궁수, S 방패병, B 폭탄병

const DEMO_FLOORS := 5    # 1~5층 = 체험 구간, 그 뒤 = 본편
const FLOOR_NAMES: Array[String] = ["첫걸음", "궁수의 복도", "두 개의 사선", "등 뒤", "협공",
	"째깍", "불꽃과 방패", "화약고", "십자 포화", "메아리의 방"]

const FLOORS: Array = [
	{
		"walls": [Vector2i(1, 1), Vector2i(5, 1), Vector2i(1, 5), Vector2i(5, 5)],
		"start": Vector2i(3, 6),
		"enemies": [["W", Vector2i(3, 0)], ["W", Vector2i(0, 2)]],
		"spawns": [[6, "W", Vector2i(6, 0)]],
	},
	{
		"walls": [Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4)],
		"start": Vector2i(3, 6),
		"enemies": [["A", Vector2i(3, 0)], ["W", Vector2i(0, 0)], ["W", Vector2i(6, 0)]],
		"spawns": [[8, "W", Vector2i(0, 6)]],
	},
	{
		"walls": [Vector2i(1, 2), Vector2i(5, 2), Vector2i(3, 3)],
		"start": Vector2i(3, 6),
		"enemies": [["A", Vector2i(0, 0)], ["W", Vector2i(3, 0)], ["A", Vector2i(6, 1)]],
		"spawns": [[5, "W", Vector2i(0, 3)], [9, "W", Vector2i(6, 4)]],
	},
	{
		"walls": [Vector2i(2, 3), Vector2i(4, 3), Vector2i(0, 5)],
		"start": Vector2i(3, 6),
		"enemies": [["S", Vector2i(3, 1)], ["W", Vector2i(6, 2)]],
		"spawns": [[6, "W", Vector2i(0, 0)]],
	},
	{
		"walls": [Vector2i(1, 3), Vector2i(5, 3), Vector2i(3, 2)],
		"start": Vector2i(3, 6),
		"enemies": [["S", Vector2i(3, 0)], ["A", Vector2i(0, 1)], ["W", Vector2i(6, 0)]],
		"spawns": [[5, "S", Vector2i(6, 3)], [9, "W", Vector2i(0, 6)]],
	},
	{
		"walls": [Vector2i(1, 3), Vector2i(5, 3)],
		"start": Vector2i(3, 6),
		"enemies": [["B", Vector2i(3, 1)], ["W", Vector2i(0, 0)]],
		"spawns": [[6, "W", Vector2i(6, 0)]],
	},
	{
		"walls": [Vector2i(0, 2), Vector2i(4, 4), Vector2i(5, 1), Vector2i(5, 2)],
		"start": Vector2i(3, 6),
		"enemies": [["W", Vector2i(6, 1)], ["S", Vector2i(0, 0)], ["B", Vector2i(2, 2)]],
		"spawns": [[5, "S", Vector2i(3, 0)]],
	},
	{
		"walls": [Vector2i(2, 1), Vector2i(3, 2), Vector2i(5, 1), Vector2i(6, 2)],
		"start": Vector2i(3, 6),
		"enemies": [["B", Vector2i(5, 3)], ["W", Vector2i(3, 0)], ["A", Vector2i(5, 0)]],
		"spawns": [[5, "W", Vector2i(4, 0)], [9, "A", Vector2i(0, 0)]],
	},
	{
		"walls": [Vector2i(0, 4), Vector2i(1, 4), Vector2i(3, 0), Vector2i(5, 2), Vector2i(6, 6)],
		"start": Vector2i(3, 6),
		"enemies": [["A", Vector2i(4, 2)], ["S", Vector2i(1, 1)], ["B", Vector2i(5, 0)], ["A", Vector2i(5, 3)]],
		"spawns": [[5, "S", Vector2i(6, 5)], [9, "B", Vector2i(0, 0)]],
	},
	{
		"walls": [Vector2i(1, 0), Vector2i(1, 3), Vector2i(1, 5), Vector2i(2, 0), Vector2i(2, 4)],
		"start": Vector2i(3, 6),
		"enemies": [["S", Vector2i(5, 1)], ["B", Vector2i(1, 1)], ["A", Vector2i(0, 3)], ["W", Vector2i(6, 3)], ["S", Vector2i(5, 0)]],
		"spawns": [[5, "B", Vector2i(6, 1)], [9, "A", Vector2i(0, 0)]],
	},
]
