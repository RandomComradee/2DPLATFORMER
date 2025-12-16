extends Node
class_name PlayerAnimationController

## Dedicated animation controller for 2D platformer
## Handles all animation state transitions without touching movement code

signal animation_state_changed(old_state: String, new_state: String)

# Reference to the main controller (set in _ready or via export)
@export var controller: CharacterBody2D
@export var sprite: AnimatedSprite2D

# Animation state enum
enum AnimState {
	IDLE,
	RUN_START,
	RUN,
	RUN_END,
	WALK,
	CROUCH_START,
	CROUCH_IDLE,
	CROUCH_WALK,
	CROUCH_END,
	JUMP_RISE,
	JUMP_TRANSITION,
	JUMP_FALL,
	JUMP_LANDING,
	JUMP_TO_RUN,
	WALL_SLIDE_CONTACT,
	WALL_SLIDE_LOOP,
	WALL_JUMP,
	ROLL,
	DASH,
	ATTACK,
	BLOCK,
	HIT
}

# Current and previous frame state tracking
var current_state: AnimState = AnimState.IDLE
var previous_state: AnimState = AnimState.IDLE

# State tracking for transitions
var _was_on_floor: bool = true
var _was_on_wall: bool = false
var _was_falling: bool = false
var _was_rising: bool = false
var _was_at_max_speed: bool = false
var _was_moving: bool = false
var _was_crouching: bool = false

# Velocity tracking for transitions
var _prev_velocity: Vector2 = Vector2.ZERO

# One-shot animation tracking
var _playing_one_shot: bool = false
var _one_shot_next_state: AnimState = AnimState.IDLE
var _queued_animation: String = ""

# Cached references from controller
var _max_speed: float = 200.0
var _wall_sliding: float = 1.0
var _anim_scale_lock: Vector2 = Vector2(1, 1)

# Threshold values
const VELOCITY_THRESHOLD: float = 10.0
const MAX_SPEED_THRESHOLD: float = 0.85  # 85% of max speed considered "at max"
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

	# Cache values from controller if available
	if controller and controller.has_method("get"):
		_max_speed = controller.get("maxSpeedLock") if controller.get("maxSpeedLock") else 200.0
		_wall_sliding = controller.get("wallSliding") if controller.get("wallSliding") else 1.0

func _process(delta):
	if !controller or !sprite:
		return

	_update_animation_state(delta)

func _update_animation_state(_delta):
	# Get current state from controller
	var velocity = controller.velocity
	var is_on_floor = controller.is_on_floor()
	var is_on_wall = controller.is_on_wall()

	# Get controller state variables
	var crouching = _get_controller_var("crouching", false)
	var rolling = _get_controller_var("rolling", false)
	var dashing = _get_controller_var("dashing", false)
	var attacking = _get_controller_var("attacking", false)
	var blocking = _get_controller_var("blocking", false)
	var hit_stunned = _get_controller_var("hit_stunned", false)
	var latched = _get_controller_var("latched", false)
	var wall_latching = _get_controller_var("wallLatching", false)

	# Input states for direction
	var right_hold = Input.is_action_pressed("right") if InputMap.has_action("right") else false
	var left_hold = Input.is_action_pressed("left") if InputMap.has_action("left") else false
	var moving_input = right_hold or left_hold

	# Calculate state booleans
	var is_moving = abs(velocity.x) > VELOCITY_THRESHOLD
	var is_at_max_speed = abs(velocity.x) >= _max_speed * MAX_SPEED_THRESHOLD
	var is_falling = velocity.y > FALL_THRESHOLD
	var is_rising = velocity.y < RISE_THRESHOLD
	var is_in_transition_zone = !is_falling and !is_rising and !is_on_floor

	# Handle sprite direction (without touching movement)
	_update_sprite_direction(right_hold, left_hold, latched, blocking)

	# If playing a one-shot animation, wait for it to finish
	if _playing_one_shot:
		_update_previous_state(is_on_floor, is_on_wall, is_falling, is_rising, is_at_max_speed, is_moving, crouching, velocity)
		return

	# Determine the target animation state (priority-based)
	var target_state = _determine_animation_state(
		is_on_floor, is_on_wall, is_moving, is_at_max_speed,
		is_falling, is_rising, is_in_transition_zone,
		crouching, rolling, dashing, attacking, blocking, hit_stunned,
		latched, wall_latching, velocity, moving_input
	)

	# Handle state transitions
	if target_state != current_state:
		_transition_to_state(target_state)

	# Update previous frame state
	_update_previous_state(is_on_floor, is_on_wall, is_falling, is_rising, is_at_max_speed, is_moving, crouching, velocity)

func _determine_animation_state(
	is_on_floor: bool, is_on_wall: bool, is_moving: bool, is_at_max_speed: bool,
	is_falling: bool, is_rising: bool, is_in_transition_zone: bool,
	crouching: bool, rolling: bool, dashing: bool, attacking: bool, blocking: bool, hit_stunned: bool,
	latched: bool, wall_latching: bool, velocity: Vector2, moving_input: bool
) -> AnimState:

	# HIGHEST PRIORITY: Hit stun
	if hit_stunned:
		return AnimState.HIT

	# Blocking
	if blocking:
		return AnimState.BLOCK

	# Attacking
	if attacking:
		return AnimState.ATTACK

	# Rolling
	if rolling:
		return AnimState.ROLL

	# Dashing
	if dashing:
		return AnimState.DASH

	# Wall interactions (not on floor)
	if is_on_wall and !is_on_floor:
		if wall_latching and latched:
			return AnimState.WALL_SLIDE_LOOP  # Static wall latch uses loop
		elif is_falling or velocity.y > 0:
			# Check if just contacted wall
			if !_was_on_wall:
				return AnimState.WALL_SLIDE_CONTACT
			else:
				return AnimState.WALL_SLIDE_LOOP
		elif is_rising:
			return AnimState.WALL_JUMP

	# Airborne states
	if !is_on_floor:
		if is_rising:
			return AnimState.JUMP_RISE
		elif is_in_transition_zone:
			return AnimState.JUMP_TRANSITION
		elif is_falling:
			return AnimState.JUMP_FALL

	# Landing detection (just hit floor)
	if is_on_floor and !_was_on_floor:
		if moving_input and is_moving:
			return AnimState.JUMP_TO_RUN
		else:
			return AnimState.JUMP_LANDING

	# Crouching states
	if crouching:
		if !_was_crouching:
			return AnimState.CROUCH_START
		elif is_moving:
			return AnimState.CROUCH_WALK
		else:
			return AnimState.CROUCH_IDLE

	# Crouch end (was crouching, now not)
	if _was_crouching and !crouching and is_on_floor:
		return AnimState.CROUCH_END

	# Ground movement states
	if is_on_floor:
		if is_moving:
			# Run start: just reached max speed
			if is_at_max_speed and !_was_at_max_speed:
				return AnimState.RUN_START
			# Full run
			elif is_at_max_speed:
				return AnimState.RUN
			# Walking (not at max speed)
			else:
				return AnimState.WALK
		else:
			# Run end: was moving fast, now stopped
			if _was_at_max_speed and !is_moving:
				return AnimState.RUN_END
			# Run end: turning around (velocity changed direction)
			elif _was_moving and _velocity_changed_direction(velocity):
				return AnimState.RUN_END
			# Idle
			else:
				return AnimState.IDLE

	return AnimState.IDLE

func _velocity_changed_direction(current_velocity: Vector2) -> bool:
	if abs(_prev_velocity.x) < VELOCITY_THRESHOLD:
		return false
	if abs(current_velocity.x) < VELOCITY_THRESHOLD:
		return false
	return sign(_prev_velocity.x) != sign(current_velocity.x)

func _transition_to_state(new_state: AnimState):
	var old_state = current_state
	previous_state = current_state
	current_state = new_state

	emit_signal("animation_state_changed", AnimState.keys()[old_state], AnimState.keys()[new_state])

	# Determine animation to play
	var anim_name = _get_animation_for_state(new_state)
	var is_one_shot = _is_one_shot_animation(new_state)
	var speed_scale = _get_speed_scale_for_state(new_state)

	_play_animation(anim_name, is_one_shot, speed_scale)

func _get_animation_for_state(state: AnimState) -> String:
	match state:
		AnimState.IDLE:
			return "idle"
		AnimState.WALK:
			return "walk"
		AnimState.RUN:
			return "run"
		AnimState.RUN_START:
			return "run_start"
		AnimState.RUN_END:
			return "run_end"
		AnimState.CROUCH_START:
			return "crouch_start"
		AnimState.CROUCH_IDLE:
			return "crouch_idle"
		AnimState.CROUCH_WALK:
			return "crouch_walk"
		AnimState.CROUCH_END:
			return "crouch_end"
		AnimState.JUMP_RISE:
			return "jump_rise_loop"
		AnimState.JUMP_TRANSITION:
			return "jump_transition"
		AnimState.JUMP_FALL:
			return "jump_fall_loop"
		AnimState.JUMP_LANDING:
			return "jump_landing"
		AnimState.JUMP_TO_RUN:
			return "jumptorun"
		AnimState.WALL_SLIDE_CONTACT:
			return "wall_slide_contact"
		AnimState.WALL_SLIDE_LOOP:
			return "wall_slide_loop"
		AnimState.WALL_JUMP:
			return "wall_jump_loop"
		AnimState.ROLL:
			return "roll"
		AnimState.DASH:
			return "dash_attack"
		AnimState.ATTACK:
			return "attack"  # Will be overridden by combo system
		AnimState.BLOCK:
			return "block_static"
		AnimState.HIT:
			return "hit"
	return "idle"

func _is_one_shot_animation(state: AnimState) -> bool:
	match state:
		AnimState.RUN_START, AnimState.RUN_END:
			return true
		AnimState.CROUCH_START, AnimState.CROUCH_END:
			return true
		AnimState.JUMP_TRANSITION:
			return true
		AnimState.JUMP_LANDING, AnimState.JUMP_TO_RUN:
			return true
		AnimState.WALL_SLIDE_CONTACT:
			return true
		AnimState.ROLL:
			return true
	return false

func _get_speed_scale_for_state(state: AnimState) -> float:
	var velocity = controller.velocity if controller else Vector2.ZERO

	match state:
		AnimState.WALK:
			return clamp(abs(velocity.x) / 100.0, 0.5, 1.5)
		AnimState.RUN:
			return clamp(abs(velocity.x) / 150.0, 0.8, 1.5)
		AnimState.CROUCH_WALK:
			return clamp(abs(velocity.x) / 80.0, 0.5, 1.2)
	return 1.0

func _play_animation(anim_name: String, is_one_shot: bool, speed_scale: float = 1.0):
	if !sprite:
		return

	# Check if animation exists
	if !sprite.sprite_frames.has_animation(anim_name):
		# Fallback animations
		anim_name = _get_fallback_animation(anim_name)
		if !sprite.sprite_frames.has_animation(anim_name):
			return

	if is_one_shot:
		_playing_one_shot = true
		_queued_animation = anim_name

	if sprite.animation != anim_name:
		sprite.play(anim_name)
	sprite.speed_scale = speed_scale

func _get_fallback_animation(anim_name: String) -> String:
	# Provide fallbacks for missing animations
	match anim_name:
		"run_start":
			return "run"
		"run_end":
			return "idle"
		"crouch_start", "crouch_end":
			return "crouch_idle"
		"jump_transition":
			return "jump_fall_loop"
		"jump_landing", "jumptorun":
			return "idle"
		"wall_slide_contact":
			return "wall_slide_loop"
		"walk":
			return "run"
	return "idle"

func _on_animation_finished():
	if !_playing_one_shot:
		return

	_playing_one_shot = false

	# Transition to appropriate next state after one-shot
	match current_state:
		AnimState.RUN_START:
			# After run_start, go to run
			current_state = AnimState.RUN
			_play_animation("run", false, _get_speed_scale_for_state(AnimState.RUN))
		AnimState.RUN_END:
			# After run_end, go to idle
			current_state = AnimState.IDLE
			_play_animation("idle", false)
		AnimState.CROUCH_START:
			# After crouch_start, go to crouch_idle
			current_state = AnimState.CROUCH_IDLE
			_play_animation("crouch_idle", false)
		AnimState.CROUCH_END:
			# After crouch_end, go to idle
			current_state = AnimState.IDLE
			_play_animation("idle", false)
		AnimState.JUMP_TRANSITION:
			# After transition, go to fall
			current_state = AnimState.JUMP_FALL
			_play_animation("jump_fall_loop", false)
		AnimState.JUMP_LANDING:
			# After landing, go to idle
			current_state = AnimState.IDLE
			_play_animation("idle", false)
		AnimState.JUMP_TO_RUN:
			# After jumptorun, go to run or walk
			if abs(controller.velocity.x) >= _max_speed * MAX_SPEED_THRESHOLD:
				current_state = AnimState.RUN
				_play_animation("run", false, _get_speed_scale_for_state(AnimState.RUN))
			else:
				current_state = AnimState.WALK
				_play_animation("walk", false, _get_speed_scale_for_state(AnimState.WALK))
		AnimState.WALL_SLIDE_CONTACT:
			# After wall contact, go to wall slide loop
			current_state = AnimState.WALL_SLIDE_LOOP
			_play_animation("wall_slide_loop", false)
		AnimState.ROLL:
			# After roll, check state
			if _get_controller_var("crouching", false):
				current_state = AnimState.CROUCH_IDLE
				_play_animation("crouch_idle", false)
			else:
				current_state = AnimState.IDLE
				_play_animation("idle", false)

func _update_previous_state(is_on_floor: bool, is_on_wall: bool, is_falling: bool, is_rising: bool, is_at_max_speed: bool, is_moving: bool, crouching: bool, velocity: Vector2):
	_was_on_floor = is_on_floor
	_was_on_wall = is_on_wall
	_was_falling = is_falling
	_was_rising = is_rising
	_was_at_max_speed = is_at_max_speed
	_was_moving = is_moving
	_was_crouching = crouching
	_prev_velocity = velocity

func _update_sprite_direction(right_hold: bool, left_hold: bool, latched: bool, blocking: bool):
	if !sprite:
		return

	if right_hold and !latched and !blocking:
		sprite.scale.x = _anim_scale_lock.x
	if left_hold and !latched and !blocking:
		sprite.scale.x = _anim_scale_lock.x * -1

func _get_controller_var(var_name: String, default_value):
	if controller and var_name in controller:
		return controller.get(var_name)
	return default_value

# Public API for external systems to override animations
func force_animation(anim_name: String, is_one_shot: bool = false):
	_play_animation(anim_name, is_one_shot)

func get_current_state() -> AnimState:
	return current_state

func get_current_state_name() -> String:
	return AnimState.keys()[current_state]

# Called by controller for attack animations (combo system)
func play_attack_animation(combo_count: int, is_heavy: bool, is_airborne: bool, is_crouching: bool, velocity_y: float):
	var anim_name = "attack"

	if is_heavy:
		match combo_count:
			0: anim_name = "heavyattack_1_start"
			1: anim_name = "heavyattack_1_charge_2"
			_: anim_name = "heavyattack_1_end"
	elif is_airborne:
		if velocity_y < 0:
			anim_name = "jump_up_attack"
		else:
			anim_name = "jump_down_attack"
	elif is_crouching:
		anim_name = "crouch_attack"
	else:
		match combo_count:
			0: anim_name = "attack"
			1: anim_name = "attack_2"
			2: anim_name = "attack_3"
			_: anim_name = "attack_4"

	force_animation(anim_name, true)

# Called by controller for block animations
func play_block_animation(is_starting: bool, is_ending: bool):
	if is_starting:
		force_animation("block_start", true)
	elif is_ending:
		force_animation("block_end", true)
	else:
		force_animation("block_static", false)

# Called by controller for hit animations
func play_hit_animation(is_airborne: bool):
	if is_airborne:
		force_animation("air_hit", true)
	else:
		force_animation("hit", true)
