extends RefCounted
## 고정 층 5개. design/FIRST_BUILD.md "콘텐츠"(1~3층) + design/BUILD_2.md "콘텐츠"(4·5층)의 형식과 값 그대로.
## "enemies"는 이 순서대로 id 0, 1, ... / "spawns"는 [예고 턴, 종류, 칸]. 종류: W 졸개, A 궁수, S 방패병

const FLOOR_NAMES: Array[String] = ["첫걸음", "궁수의 복도", "두 개의 사선", "등 뒤", "협공"]

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
]
