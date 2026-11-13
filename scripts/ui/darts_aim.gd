extends Control
## The darts aim, drawn over the board: a line through the bull at some angle
## with a dot running up and down it, then (once you've stopped that dot) a
## second line through where it stopped, at another angle, the same length.
## Stop the second dot and that's where the dart goes.
##
## Everything here is in board radii (darts.gd); `to_screen` turns them into
## this control's pixels. darts_ui.gd drives it.

const LINE := 1.4 # half a line's length, in board radii: long enough to miss the board

var to_screen: Callable # Vector2 (board) -> Vector2 (pixels)
var stage := "" # "", "line1", "line2"
var a1 := 0.0 # the first line's angle
var a2 := 0.0 # the second's
var p1 := Vector2.ZERO # where the first dot stopped
var dot := Vector2.ZERO
var period := 1.8 # seconds for the dot to go end to end and back
var _t := 0.0
var _phase := 0.0
var ghost := false # an AI's aim, played out for you to watch
var _ghost_to := 0.0 # where the ghost's dot stops (along its line)
var _ghost_time := 0.0
var _ghost_done: Callable
var _lock_flash := 0.0

const RED := Color(0.86, 0.2, 0.18)
const DOT := Color(1.0, 0.86, 0.25)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## The dot's place along its line, -LINE..LINE, as a triangle wave.
static func tri(x: float) -> float:
	return 2.0 * absf(2.0 * fposmod(x, 1.0) - 1.0) - 1.0


func begin(angle: float, speed_period: float) -> void:
	stage = "line1"
	ghost = false
	a1 = angle
	period = speed_period
	_t = 0.0
	_phase = randf()
	visible = true
	queue_redraw()


## Stop the dot. Returns true once the dart is ready to go (the second stop).
func stop(angle2: float) -> bool:
	if stage == "line1":
		p1 = dot
		a2 = angle2
		stage = "line2"
		_t = 0.0
		_phase = randf()
		_lock_flash = 0.25
		return false
	if stage == "line2":
		stage = ""
		visible = false
		return true
	return false


func landing() -> Vector2:
	return dot


func hide_aim() -> void:
	stage = ""
	ghost = false
	visible = false


## Play an AI's aim: it lands at `land`. Two lines are found that get there,
## and each dot runs for a moment and stops in the right place.
func play_ghost(land: Vector2, speed_period: float, done: Callable) -> void:
	ghost = true
	_ghost_done = done
	period = speed_period
	a1 = randf() * PI
	a2 = a1 + deg_to_rad(randf_range(45.0, 135.0))
	var u1 := Vector2(cos(a1), sin(a1))
	var u2 := Vector2(cos(a2), sin(a2))
	# land = s1 * u1 + s2 * u2
	var det := u1.x * u2.y - u1.y * u2.x
	var s1 := (land.x * u2.y - land.y * u2.x) / det
	var s2 := (u1.x * land.y - u1.y * land.x) / det
	_ghost_to = s1
	p1 = u1 * s1
	set_meta("s2", s2)
	stage = "line1"
	_ghost_time = 0.0
	_t = 0.0
	_phase = _phase_for(s1)
	visible = true


## A phase so the wave reaches `s` after the ghost's time on a line.
func _phase_for(s: float) -> float:
	var v := clampf(s / LINE, -1.0, 1.0)
	var x0 := (1.0 - v) / 4.0 # tri(x0) == v
	return x0 - _ghost_span() / period


func _ghost_span() -> float:
	return clampf(period * 0.75, 0.6, 1.1)


func _process(delta: float) -> void:
	if stage == "":
		return
	_t += delta
	_lock_flash = maxf(0.0, _lock_flash - delta)
	var along := tri(_t / period + _phase) * LINE
	if ghost:
		_ghost_time += delta
		if _ghost_time >= _ghost_span():
			along = _ghost_to # the dot settles where it stopped
			if stage == "line1":
				stage = "line2"
				_lock_flash = 0.25
				var s2: float = get_meta("s2")
				_ghost_to = s2
				_ghost_time = 0.0
				_t = 0.0
				_phase = _phase_for(s2)
				along = tri(_phase) * LINE
			else:
				stage = ""
				visible = false
				if _ghost_done.is_valid():
					_ghost_done.call()
				return
	if stage == "line1":
		dot = Vector2(cos(a1), sin(a1)) * along
	else:
		dot = p1 + Vector2(cos(a2), sin(a2)) * along
	queue_redraw()


func _line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var a: Vector2 = to_screen.call(from)
	var b: Vector2 = to_screen.call(to)
	draw_line(a, b, Color(0, 0, 0, color.a * 0.7), width + 6.0)
	draw_line(a, b, color, width)


func _draw() -> void:
	if stage == "" or not to_screen.is_valid():
		return
	var u1 := Vector2(cos(a1), sin(a1))
	var reach := maxf(LINE, absf(_ghost_to) if ghost else LINE)
	if stage == "line1":
		_line(-u1 * reach, u1 * reach, RED, 7.0)
	else:
		_line(-u1 * LINE, u1 * LINE, Color(RED, 0.3), 4.0) # the first line, done with
		var u2 := Vector2(cos(a2), sin(a2))
		_line(p1 - u2 * reach, p1 + u2 * reach, RED, 7.0)
		var c: Vector2 = to_screen.call(p1)
		draw_circle(c, 9.0 + _lock_flash * 40.0, Color(1, 1, 1, 0.5 + _lock_flash * 2.0))
	var d: Vector2 = to_screen.call(dot)
	draw_circle(d, 17.0, Color(0, 0, 0, 0.7))
	draw_circle(d, 13.0, DOT)
	draw_circle(d, 6.0, Color(1, 1, 1))
