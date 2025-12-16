extends Node
class_name AnimationStateMachine

## Clean animation state machine for 2D platformer
## Handles all movement animation transitions properly

signal state_changed(from_state: String, to_state: String)

@export var sprite: AnimatedSprite2D
@export var body: CharacterBody2D

# Animation states
enum State {
	IDLE,
	WALK,
	RUN_START,
	RUN,
	RUN_END,
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
	ROLL,
	DASH
}

# State to animation name mapping
const STATE_ANIMS := {
	State.IDLE: "idle",
	State.WALK: "walk",
	State.RUN_START: "run_start",
	State.RUN: "run",
	State.RUN_END: "run_end",
	State.CROUCH_START: "crouch_start",
	State.CROUCH_IDLE: "crouch_idle",
	State.CROUCH_WALK: "crouch_walk",
	State.CROUCH_END: "crouch_end",
	State.JUMP_RISE: "jump_rise_loop",
	State.JUMP_TRANSITION: "jump_transition",
	State.JUMP_FALL: "jump_fall_loop",
	State.JUMP_LANDING: "jump_landing",
	State.JUMP_TO_RUN: "jumptorun",
	State.WALL_SLIDE_CONTACT: "wall_slide_contact",
	State.WALL_SLIDE_LOOP: "wall_slide_loop",
	State.ROLL: "roll",
	State.DASH: "dash_attack"
}

# One-shot states (play once then transition)
const ONE_SHOT_STATES := [
	State.RUN_START,
	State.RUN_END,
	State.CROUCH_START,
	State.CROUCH_END,
	State.JUMP_TRANSITION,
	State.JUMP_LANDING,
	State.JUMP_TO_RUN,
	State.WALL_SLIDE_CONTACT,
	State.ROLL
]

# What state to go to after one-shot finishes
const ONE_SHOT_NEXT := {
	State.RUN_START: State.RUN,
	State.RUN_END: State.IDLE,
	State.CROUCH_START: State.CROUCH_IDLE,
	State.CROUCH_END: State.IDLE,
	State.JUMP_TRANSITION: State.JUMP_FALL,
	State.JUMP_LANDING: State.IDLE,
	State.JUMP_TO_RUN: State.RUN,
	State.WALL_SLIDE_CONTACT: State.WALL_SLIDE_LOOP,
	State.ROLL: State.IDLE
}

var current_state: State = State.IDLE
var locked: bool = false  # When true, don't change state until animation finishes

# Previous frame tracking
var prev_on_floor: bool = true
var prev_on_wall: bool = false
var prev_crouching: bool = false
var prev_velocity_x: float = 0.0
var prev_at_max_speed: bool = false
var prev_moving: bool = false

# Config
var max_speed: float = 200.0
var wall_slide_enabled: bool = false
var sprite_scale: Vector2 = Vector2(1, 1)

func _ready() -> void:
	if sprite:
		sprite.animation_finished.connect(_on_animation_finished)
		sprite_scale = abs(sprite.scale)

func setup(p_sprite: AnimatedSprite2D, p_body: CharacterBody2D, p_max_speed: float, p_wall_sliding: float) -> void:
	sprite = p_sprite
	body = p_body
	max_speed = p_max_speed
	wall_slide_enabled = p_wall_sliding != 1.0
	if sprite:
		sprite.animation_finished.connect(_on_animation_finished)
		sprite_scale = abs(sprite.scale)

func _process(_delta: float) -> void:
	if !sprite or !body:
		return

	update_state()

func update_state() -> void:
	var vel := body.velocity
	var on_floor := body.is_on_floor()
	var on_wall := body.is_on_wall()

	# Get external states (these should be set by movement controller)
	var crouching: bool = body.get("crouching") if "crouching" in body else false
	var rolling: bool = body.get("rolling") if "rolling" in body else false
	var dashing: bool = body.get("dashing") if "dashing" in body else false

	# Input for direction
	var right_input := Input.is_action_pressed("right")
	var left_input := Input.is_action_pressed("left")
	var has_move_input := right_input or left_input

	# Update sprite facing
	if right_input:
		sprite.scale.x = sprite_scale.x
	elif left_input:
		sprite.scale.x = -sprite_scale.x

	# State calculations
	var vel_x_abs: float = absf(vel.x)
	var moving: bool = vel_x_abs > 10.0
	var at_max_speed: bool = vel_x_abs >= max_speed * 0.8
	var rising: bool = vel.y < -50.0
	var falling: bool = vel.y > 50.0
	var at_apex: bool = !rising and !falling and !on_floor

	# Detect transitions
	var just_landed: bool = on_floor and !prev_on_floor
	var just_left_ground: bool = !on_floor and prev_on_floor
	var just_touched_wall: bool = on_wall and !prev_on_wall and !on_floor
	var just_started_crouch: bool = crouching and !prev_crouching
	var just_stopped_crouch: bool = !crouching and prev_crouching
	var just_reached_max: bool = at_max_speed and !prev_at_max_speed and prev_moving
	var just_stopped: bool = !moving and prev_moving
	var prev_vel_abs: float = absf(prev_velocity_x)
	var direction_changed: bool = prev_moving and moving and sign(vel.x) != sign(prev_velocity_x) and prev_vel_abs > 10.0

	# Determine target state
	var target: State = current_state

	# If locked (playing one-shot), don't change unless interrupted by high-priority
	if locked:
		if rolling or dashing:
			locked = false
		else:
			_save_prev_state(on_floor, on_wall, crouching, vel.x, at_max_speed, moving)
			return

	# Priority-based state selection

	# ROLLING (high priority)
	if rolling:
		target = State.ROLL

	# DASHING (high priority)
	elif dashing:
		target = State.DASH

	# WALL SLIDING
	elif on_wall and !on_floor and wall_slide_enabled:
		if just_touched_wall:
			target = State.WALL_SLIDE_CONTACT
		elif current_state == State.WALL_SLIDE_CONTACT:
			# Stay in contact until animation finishes
			pass
		else:
			target = State.WALL_SLIDE_LOOP

	# JUST LANDED
	elif just_landed:
		if has_move_input and moving:
			target = State.JUMP_TO_RUN
		else:
			target = State.JUMP_LANDING

	# AIRBORNE
	elif !on_floor:
		if rising:
			target = State.JUMP_RISE
		elif at_apex:
			target = State.JUMP_TRANSITION
		else:
			target = State.JUMP_FALL

	# CROUCH TRANSITIONS
	elif just_started_crouch:
		target = State.CROUCH_START
	elif just_stopped_crouch and on_floor:
		target = State.CROUCH_END

	# CROUCHING
	elif crouching:
		if moving:
			target = State.CROUCH_WALK
		else:
			target = State.CROUCH_IDLE

	# GROUND MOVEMENT
	elif on_floor:
		# Turn around from run
		if direction_changed and prev_at_max_speed:
			target = State.RUN_END
		# Just reached max speed
		elif just_reached_max:
			target = State.RUN_START
		# Stopped from running fast
		elif just_stopped and prev_at_max_speed:
			target = State.RUN_END
		# Running
		elif at_max_speed:
			target = State.RUN
		# Walking
		elif moving:
			target = State.WALK
		# Idle
		else:
			target = State.IDLE

	# Change state if needed
	if target != current_state:
		_change_state(target)

	# Update speed scale for looping anims
	_update_speed_scale(vel.x)

	# Save state for next frame
	_save_prev_state(on_floor, on_wall, crouching, vel.x, at_max_speed, moving)

func _change_state(new_state: State) -> void:
	var old_state := current_state
	current_state = new_state

	var anim_name: String = STATE_ANIMS.get(new_state, "idle")

	# Check if animation exists
	if !sprite.sprite_frames.has_animation(anim_name):
		anim_name = _get_fallback(anim_name)

	# Lock if one-shot
	if new_state in ONE_SHOT_STATES:
		locked = true

	# Play animation
	sprite.play(anim_name)
	sprite.speed_scale = 1.0

	emit_signal("state_changed", State.keys()[old_state], State.keys()[new_state])

func _on_animation_finished() -> void:
	if !locked:
		return

	locked = false

	# Transition to next state after one-shot
	if current_state in ONE_SHOT_NEXT:
		var next_state: State = ONE_SHOT_NEXT[current_state]
		_change_state(next_state)

func _update_speed_scale(vel_x: float) -> void:
	match current_state:
		State.WALK:
			sprite.speed_scale = clamp(abs(vel_x) / 100.0, 0.5, 1.5)
		State.RUN:
			sprite.speed_scale = clamp(abs(vel_x) / 150.0, 0.8, 1.5)
		State.CROUCH_WALK:
			sprite.speed_scale = clamp(abs(vel_x) / 80.0, 0.5, 1.2)
		_:
			sprite.speed_scale = 1.0

func _get_fallback(anim_name: String) -> String:
	match anim_name:
		"run_start", "run_end": return "run"
		"crouch_start", "crouch_end": return "crouch_idle"
		"jump_transition": return "jump_fall_loop"
		"jump_landing", "jumptorun": return "idle"
		"wall_slide_contact": return "wall_slide_loop"
		"walk": return "run"
	return "idle"

func _save_prev_state(on_floor: bool, on_wall: bool, crouching: bool, vel_x: float, at_max: bool, moving: bool) -> void:
	prev_on_floor = on_floor
	prev_on_wall = on_wall
	prev_crouching = crouching
	prev_velocity_x = vel_x
	prev_at_max_speed = at_max
	prev_moving = moving

# Force a specific state (for external systems)
func force_state(state: State) -> void:
	locked = false
	_change_state(state)

func get_state_name() -> String:
	return State.keys()[current_state]
