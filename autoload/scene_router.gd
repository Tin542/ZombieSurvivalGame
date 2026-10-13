extends CanvasLayer
## Top-level scene transitions with a fade. Knows scene paths, not scene contents.

const MAIN_MENU := "res://scenes/main_menu/main_menu.tscn"
const RUN := "res://scenes/run/run.tscn"
const FADE_TIME := 0.2

var _fade: ColorRect
var _busy := false
## Items (id -> units) the next run should take from the stash, or null when
## the run was started without a loadout choice (PLAY with nothing to bring).
var _run_loadout: Variant = null


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


func go_to_main_menu() -> void:
	_change_scene(MAIN_MENU)


## Starts a run that brings `loadout` (a Dictionary of item id -> units, may be
## empty) from the stash; null = no loadout choice was made. The run takes the
## items itself (SaveService.take_loadout) when it starts, so a transition that
## never happens can't lose them.
func start_run(loadout: Variant = null) -> void:
	if _busy:
		return
	_run_loadout = loadout.duplicate() if loadout is Dictionary else null
	_change_scene(RUN)


## The loadout passed to start_run(), handed over once; null afterwards.
func take_run_loadout() -> Variant:
	var loadout: Variant = _run_loadout
	_run_loadout = null
	return loadout


func _change_scene(path: String) -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP

	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_TIME)
	await tween.finished

	get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneRouter: cannot load %s (%s)" % [path, error_string(err)])

	tween = create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_TIME)
	await tween.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
