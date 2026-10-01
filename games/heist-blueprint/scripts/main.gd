extends Node2D
## 설계도 위의 도둑들 — 건물 단면도 위에 도둑들의 동선과 기다릴 때를 그려 넣고, 작전 개시를 눌러 계획이 동시에 굴러가는 것을 지켜보는 털이 계획 게임
## Builder가 SPEC.md의 must_work 항목을 기준으로 채운다.

enum State { TITLE, PLAY, RESULT }

const W := 960.0
const H := 540.0

var state: State = State.TITLE
var score := 0
var font: Font


func _ready() -> void:
	font = load("res://assets/fonts/NotoSansKR-Medium.ttf")


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_tap(event.position)


func _tap(_pos: Vector2) -> void:
	match state:
		State.TITLE, State.RESULT:
			state = State.PLAY
			score = 0
		State.PLAY:
			pass


func _draw() -> void:
	draw_string(font, Vector2(0, H * 0.4), "설계도 위의 도둑들", HORIZONTAL_ALIGNMENT_CENTER, W, 40, Color("edf4ff"))


# 테스트용 훅: tests/smoke.gd가 입력을 흉내 낼 때 쓴다
func debug_tap(pos: Vector2) -> void:
	_tap(pos)
