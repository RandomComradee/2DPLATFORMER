extends Node
class_name PlayerAnimationController

## Dedicated animation controller for movement animations only
## Handles state transitions for: wall slide, jump, run, crouch

@export var controller: CharacterBody2D
@export var sprite: AnimatedSprite2D

# Configuration (set by main controller)
var _max_speed: float = 200.0
var _wall_sliding: float = 1.0
var _anim_scale_lock: Vector2 = Vector2(1, 1)

# Previous frame state tracking
var _was_on_floor: bool = true
var _was_on_wall: bool = false
var _was_at_max_speed: bool = false
var _was_moving: bool = false
var _was_crouching: bool = false
var _prev_velocity: Vector2 = Vector2.ZERO

# One-shot animation tracking
var _playing_one_shot: bool = false
var _current_one_shot: String = ""

# Thresholds
const VELOCITY_THRESHOLD: float = 10.0
const MAX_SPEED_RATIO: float = 0.85
const FALL_THRESHOLD: float = 50.0
const RISE_THRESHOLD: float = -50.0

func _ready():
	if controller == null:
		controller = get_parent() as CharacterBody2D
	if sprite == null and controller:
		sprite = controller.get_node_or_null("AnimatedSprite2D")

	if sprite:
		sprite.animation_finished.connect(_on_animation_finished)
		_anim_scale_lock = abs(sprite.scale)

func _process(_delta):
	if !controller or !sprite:
		return

	_update_animations()

func _update_animations():
	var velocity = controller.velocity
	var is_on_floor = controller.is_on_floor()
	var is_on_wall = controller.is_on_wall()

	# Get state from controller (with safe defaults)
	var crouching: bool = _get_bool("crouching")
	var rolling: bool = _get_bool("rolling")
	var dashing: bool = _get_bool("dashing")
	var latched: bool = _get_bool("latched")
	var blocking: bool = _get_bool("blocking")
	var attacking: bool = _get_bool("attacking")
	var hit_stunned: bool = _get_bool("hit_stunned")

	# Input for direction
	var right_hold = Input.is_action_pressed("right") if InputMap.has_action("right") else false
	var left_hold = Input.is_action_pressed("left") if InputMap.has_action("left") else false
	var moving_input = right_hold or left_hold

	# Calculate states
	var is_moving = abs(velocity.x) > VELOCITY_THRESHOLD
	var is_at_max_speed = abs(velocity.x) >= _max_speed * MAX_SPEED_RATIO
	var is_falling = velocity.y > FALL_THRESHOLD
	var is_rising = velocity.y < RISE_THRESHOLD
	var is_in_transition = !is_falling and !is_rising and !is_on_floor

	# Update sprite direction
	if right_hold and !latched and !blocking:
		sprite.scale.x = _anim_scale_lock.x
	if left_hold and !latched and !blocking:
		sprite.scale.x = -_anim_scale_lock.x

	# If playing one-shot, let it finish (unless state drastically changed)
	if _playing_one_shot:
		# Allow interruption only for major state changes
		if hit_stunned or attacking or rolling or dashing:
			_playing_one_shot = false
		else:
			_update_prev_state(is_on_floor, is_on_wall, is_at_max_speed, is_moving, crouching, velocity)
			return

	# Skip if combat states are active (let existing system handle those)
	if hit_stunned or attacking or blocking or rolling or dashing:
		_update_prev_state(is_on_floor, is_on_wall, is_at_max_speed, is_moving, crouching, velocity)
		return

	# Determine animation
	var anim_name: String = "idle"
	var is_one_shot: bool = false
	var speed_scale: float = 1.0

	# WALL SLIDE (not on floor, on wall, sliding enabled)
	if is_on_wall and !is_on_floor and _wall_sliding != 1.0:
		if !_was_on_wall:
			# Just contacted wall
			anim_name = "wall_slide_contact"
			is_one_shot = true
		else:
			anim_name = "wall_slide_loop"

	# LANDING (just hit floor from air)
	elif is_on_floor and !_was_on_floor:
		if moving_input and is_moving:
			anim_name = "jumptorun"
			is_one_shot = true
		else:
			anim_name = "jump_landing"
			is_one_shot = true

	# AIRBORNE
	elif !is_on_floor:
		if is_rising:
			anim_name = "jump_rise_loop"
		elif is_in_transition:
			anim_name = "jump_transition"
			is_one_shot = true
		elif is_falling:
			anim_name = "jump_fall_loop"

	# CROUCHING
	elif crouching:
		if !_was_crouching:
			anim_name = "crouch_start"
			is_one_shot = true
		elif is_moving:
			anim_name = "crouch_walk"
			speed_scale = clamp(abs(velocity.x) / 80.0, 0.5, 1.2)
		else:
			anim_name = "crouch_idle"

	# CROUCH END
	elif _was_crouching and !crouching:
		anim_name = "crouch_end"
		is_one_shot = true

	# GROUND MOVEMENT
	elif is_on_floor:
		# Turning around (velocity changed direction while moving fast)
		if _was_at_max_speed and _velocity_flipped(velocity):
			anim_name = "run_end"
			is_one_shot = true
		# Just reached max speed
		elif is_at_max_speed and !_was_at_max_speed and _was_moving:
			anim_name = "run_start"
			is_one_shot = true
		# Stopped from running
		elif !is_moving and _was_moving and _was_at_max_speed:
			anim_name = "run_end"
			is_one_shot = true
		# Running at max speed
		elif is_at_max_speed:
			anim_name = "run"
			speed_scale = clamp(abs(velocity.x) / 150.0, 0.8, 1.5)
		# Walking (not at max)
		elif is_moving:
			anim_name = "walk"
			speed_scale = clamp(abs(velocity.x) / 100.0, 0.5, 1.5)
		# Idle
		else:
			anim_name = "idle"

	# Play animation
	_play_anim(anim_name, is_one_shot, speed_scale)

	# Update previous state
	_update_prev_state(is_on_floor, is_on_wall, is_at_max_speed, is_moving, crouching, velocity)

func _velocity_flipped(current: Vector2) -> bool:
	if abs(_prev_velocity.x) < VELOCITY_THRESHOLD or abs(current.x) < VELOCITY_THRESHOLD:
		return false
	return sign(_prev_velocity.x) != sign(current.x)

func _play_anim(anim_name: String, is_one_shot: bool, speed_scale: float = 1.0):
	if !sprite.sprite_frames.has_animation(anim_name):
		anim_name = _get_fallback(anim_name)
		if !sprite.sprite_frames.has_animation(anim_name):
			return

	if is_one_shot:
		_playing_one_shot = true
		_current_one_shot = anim_name

	if sprite.animation != anim_name:
		sprite.play(anim_name)
	sprite.speed_scale = speed_scale

func _get_fallback(anim_name: String) -> String:
	match anim_name:
		"run_start", "run_end": return "run"
		"crouch_start", "crouch_end": return "crouch_idle"
		"jump_transition": return "jump_fall_loop"
		"jump_landing", "jumptorun": return "idle"
		"wall_slide_contact": return "wall_slide_loop"
		"walk": return "run"
	return "idle"

func _on_animation_finished():
	if !_playing_one_shot:
		return

	_playing_one_shot = false

	# Transition to next animation after one-shot
	match _current_one_shot:
		"run_start":
			sprite.play("run")
		"run_end":
			sprite.play("idle")
		"crouch_start":
			sprite.play("crouch_idle")
		"crouch_end":
			sprite.play("idle")
		"jump_transition":
			sprite.play("jump_fall_loop")
		"jump_landing":
			sprite.play("idle")
		"jumptorun":
			sprite.play("run")
		"wall_slide_contact":
			sprite.play("wall_slide_loop")

func _update_prev_state(on_floor: bool, on_wall: bool, at_max: bool, moving: bool, crouching: bool, vel: Vector2):
	_was_on_floor = on_floor
	_was_on_wall = on_wall
	_was_at_max_speed = at_max
	_was_moving = moving
	_was_crouching = crouching
	_prev_velocity = vel

func _get_bool(var_name: String) -> bool:
	if controller and var_name in controller:
		var val = controller.get(var_name)
		if val is bool:
			return val
	return false
