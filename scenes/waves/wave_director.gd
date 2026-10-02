class_name WaveDirector
extends Node
## Runs the wave loop:  BREAK (countdown) -> COMBAT -> wave cleared -> BREAK ...
##
## COMBAT asks ZombieSpawner for the wave's batch and ends once every zombie of
## it has spawned and died. BREAK is the window between waves; the supply phase
## (Phase 10) drops crates during it. Knows nothing about UI: it only emits
## signals, and the run forwards them to the HUD.

enum Phase { IDLE, BREAK, COMBAT, STOPPED }

signal wave_started(wave: int, zombie_count: int)
signal wave_cleared(wave: int)
signal break_started(next_wave: int, duration: float)
## Zombies of the current wave not yet killed (alive + still to spawn).
signal remaining_changed(remaining: int)

## Countdown before wave 1.
@export var first_wave_delay: float = 3.0

## Last wave started (0 before the first).
var wave := 0
var phase := Phase.IDLE

var _spawner: ZombieSpawner
var _zombies: ZombieManager
var _table: WaveTable
var _break_left := 0.0
var _remaining := -1


func setup(spawner: ZombieSpawner, zombies: ZombieManager, table: WaveTable) -> void:
	_spawner = spawner
	_zombies = zombies
	_table = table


## Begins the countdown to wave 1.
func start() -> void:
	wave = 0
	_begin_break(first_wave_delay)


## Ends the current break early (e.g. the player tapped "start now").
func skip_break() -> void:
	if phase == Phase.BREAK:
		_break_left = 0.0


## Halts the loop for good (player died). Pending spawns are cancelled.
func stop() -> void:
	phase = Phase.STOPPED
	_spawner.stop()


func break_time_left() -> float:
	return _break_left if phase == Phase.BREAK else 0.0


func _physics_process(delta: float) -> void:
	match phase:
		Phase.BREAK:
			_break_left -= delta
			if _break_left <= 0.0:
				_start_wave(wave + 1)
		Phase.COMBAT:
			# Polled rather than driven by kill signals so anything that removes
			# zombies (debug clear, future instakill effects) still ends the wave.
			var remaining := _spawner.pending_count() + _zombies.alive_count()
			if remaining != _remaining:
				_remaining = remaining
				remaining_changed.emit(remaining)
			if remaining == 0 and not _spawner.is_batch_active():
				_clear_wave()


func _start_wave(next: int) -> void:
	wave = next
	phase = Phase.COMBAT
	_break_left = 0.0
	var count := _table.zombie_count(wave)
	_spawner.start_batch(count, _table.spawn_interval(wave), wave)
	_remaining = count
	wave_started.emit(wave, count)
	remaining_changed.emit(count)


func _clear_wave() -> void:
	wave_cleared.emit(wave)
	_begin_break(_table.supply_duration)


func _begin_break(duration: float) -> void:
	phase = Phase.BREAK
	_break_left = maxf(duration, 0.0)
	break_started.emit(wave + 1, _break_left)
