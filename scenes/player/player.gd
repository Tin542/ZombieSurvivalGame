class_name Player
extends CharacterBody2D
## Top-down player body. Movement reads the move_* actions, which both the
## HUD's touch joystick and the keyboard drive. Behaviour lives in child
## components (Health, AutoAim, WeaponHolder); this script only links them
## and handles visuals.

@export var move_speed: float = 80.0
## Radius zombies use for contact range.
@export var body_radius: float = 5.0

@onready var health: HealthComponent = $Health
@onready var aim: AutoAim = $AutoAim
@onready var weapons: WeaponHolder = $WeaponHolder
@onready var camera: Camera2D = $Camera
@onready var _sprite: Sprite2D = $Sprite
@onready var _gun: Sprite2D = $Gun


func _ready() -> void:
	weapons.aim = aim
	health.died.connect(_on_died)


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = direction * move_speed
	move_and_slide()
	_update_facing(direction)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"switch_weapon"):
		weapons.cycle_weapon()
		get_viewport().set_input_as_handled()


func set_camera_limits(rect: Rect2) -> void:
	camera.limit_left = floori(rect.position.x)
	camera.limit_top = floori(rect.position.y)
	camera.limit_right = ceili(rect.end.x)
	camera.limit_bottom = ceili(rect.end.y)


## Faces the aim target while shooting, otherwise the movement direction.
func _update_facing(move_direction: Vector2) -> void:
	var look := move_direction
	if aim.has_target:
		look = aim.target_position - global_position
	if absf(look.x) > 0.01:
		_sprite.flip_h = look.x < 0.0
	if look != Vector2.ZERO:
		_gun.rotation = look.angle()
		_gun.flip_v = look.x < 0.0


func _on_died() -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)
	aim.set_physics_process(false)
	weapons.set_physics_process(false)
	velocity = Vector2.ZERO
	_sprite.modulate = Color(1.0, 1.0, 1.0, 0.4)
	_gun.visible = false
