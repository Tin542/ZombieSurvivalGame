class_name AimButton
extends Button
## Button that doubles as an aim stick: press and drag to aim, release to
## fire. A quick tap (never dragged out) reports `tapped` instead; dragging
## out and back to the centre before letting go cancels.
##
## Aim is reported as a vector up to length 1 (`max_drag` pixels of drag = 1),
## in screen directions, which match world directions (the camera never
## rotates). Tracks one finger by touch index, so it works while another
## finger holds the movement joystick; real mouse input is handled for
## desktop, emulated mouse events from touches are ignored.

signal aim_started
signal aim_changed(aim: Vector2)
signal aim_released(aim: Vector2)
signal aim_cancelled
signal tapped

const NO_POINTER := -2
const MOUSE_POINTER := -1

## Drag distance (pixels) that counts as full range.
@export var max_drag: float = 48.0
## Aims shorter than this (fraction of full range) are a tap, or a cancel
## after having dragged out.
@export var dead_zone: float = 0.2

var aiming: bool:
	get:
		return _pointer != NO_POINTER

var _pointer := NO_POINTER
var _origin := Vector2.ZERO
var _aim := Vector2.ZERO
var _dragged_out := false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not aiming:
			begin_aim(event.position, event.index)
		elif not event.pressed and event.index == _pointer:
			release_aim()
		accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _pointer:
			drag_to(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			if event.pressed and not aiming:
				begin_aim(event.position, MOUSE_POINTER)
			elif not event.pressed and _pointer == MOUSE_POINTER:
				release_aim()
		accept_event()
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and _pointer == MOUSE_POINTER:
			drag_to(event.position)
		accept_event()


## Starts aiming from `local_position` (in this control's coordinates).
func begin_aim(local_position: Vector2, pointer: int = MOUSE_POINTER) -> void:
	if disabled or aiming:
		return
	_pointer = pointer
	_origin = local_position
	_aim = Vector2.ZERO
	_dragged_out = false
	aim_started.emit()


func drag_to(local_position: Vector2) -> void:
	if not aiming:
		return
	_aim = ((local_position - _origin) / maxf(max_drag, 1.0)).limit_length(1.0)
	if _aim.length() >= dead_zone:
		_dragged_out = true
	aim_changed.emit(_aim)


func release_aim() -> void:
	if not aiming:
		return
	_pointer = NO_POINTER
	if _aim.length() >= dead_zone:
		aim_released.emit(_aim)
	elif _dragged_out:
		aim_cancelled.emit()
	else:
		tapped.emit()


## Drops the aim without firing (e.g. the run paused or the player died).
func cancel_aim() -> void:
	if not aiming:
		return
	_pointer = NO_POINTER
	aim_cancelled.emit()


func _notification(what: int) -> void:
	# Losing visibility or the tree mid-drag would leave aiming stuck on.
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel_aim()
