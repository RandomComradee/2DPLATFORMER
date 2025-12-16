extends Node
class_name KnightAnimationController

## Handles all knight animation logic and transitions
## Attach this to your CharacterBody2D player node

@export var anim_sprite: AnimatedSprite2D
@export var player_body: CharacterBody2D

# Animation state tracking
var was_on_floor: bool = false
var was_on_wall: bool = false
var was_moving: bool = false
var was_at_max_speed: bool = false
var is_crouching: bool = false
var is_wall_sliding: bool = false

# Speed thresholds
@export var walk_speed_threshold: float = 50.0
@export var run_speed_threshold: float = 150.0

func _ready():
	if anim_sprite == null:
		push_error("AnimatedSprite2D not assigned to KnightAnimationController!")
	if player_body == null:
		push_error("CharacterBody2D not assigned to KnightAnimationController!")

func _process(_delta):
	if anim_sprite == null or player_body == null:
		return

	update_animations()

func update_animations():
	var velocity = player_body.velocity
	var is_on_floor = player_body.is_on_floor()
	var is_on_wall = player_body.is_on_wall()
	var h_speed = abs(velocity.x)
	var v_speed = velocity.y

	# WALL INTERACTIONS (High priority)
	if is_on_wall and !is_on_floor:
		handle_wall_animations(v_speed)

	# JUMPING AND FALLING
	elif !is_on_floor:
		handle_air_animations(v_speed, h_speed)

	# GROUND MOVEMENT
	elif is_on_floor:
		handle_ground_animations(h_speed, velocity.x)

	# Update state tracking
	was_on_floor = is_on_floor
	was_on_wall = is_on_wall
	was_moving = h_speed > 5.0
	was_at_max_speed = h_speed >= run_speed_threshold

func handle_wall_animations(v_speed: float):
	# Just contacted wall
	if !was_on_wall:
		play_animation("wall_slide_contact")
		is_wall_sliding = true
	# Sliding down wall
	elif v_speed > 0 and is_wall_sliding:
		# Only switch to loop after contact finishes
		if !anim_sprite.is_playing() or anim_sprite.animation != "wall_slide_contact":
			play_animation("wall_slide_loop")
	# Static on wall (not sliding)
	elif v_speed == 0:
		play_animation("wall_slide_static")
		is_wall_sliding = false

func handle_air_animations(v_speed: float, h_speed: float):
	# Just left ground - check if jumping or falling
	if was_on_floor:
		if v_speed < 0:
			play_animation("jump_rise_loop")
		else:
			play_animation("jump_fall_loop")

	# Rising (jumping up)
	elif v_speed < -50:
		play_animation("jump_rise_loop")

	# At peak of jump (transition point)
	elif v_speed >= -50 and v_speed <= 50:
		if anim_sprite.animation == "jump_rise_loop":
			play_animation("jump_transition")

	# Falling down
	elif v_speed > 50:
		# Play transition first if at peak
		if anim_sprite.animation != "jump_fall_loop" and anim_sprite.animation != "jump_transition":
			if anim_sprite.animation == "jump_rise_loop":
				play_animation("jump_transition")
		# After transition or already falling
		elif anim_sprite.animation == "jump_transition" and !anim_sprite.is_playing():
			play_animation("jump_fall_loop")
		elif anim_sprite.animation != "jump_fall_loop":
			play_animation("jump_fall_loop")

	# Reset wall slide state when in air
	is_wall_sliding = false

func handle_ground_animations(h_speed: float, vel_x: float):
	# Just landed
	if !was_on_floor:
		handle_landing(h_speed)
		return

	# CROUCHING (handled externally, but we manage the animations)
	if is_crouching:
		handle_crouch_animations(h_speed)
		return

	# MOVEMENT
	if h_speed > 5.0:
		handle_movement_animations(h_speed, vel_x)
	else:
		handle_idle_or_stopping(h_speed)

func handle_landing(h_speed: float):
	# Landing while moving - transition to run
	if h_speed > walk_speed_threshold:
		play_animation("jumptorun")
	# Landing while standing still
	else:
		play_animation("jump_landing")

func handle_movement_animations(h_speed: float, vel_x: float):
	var current_anim = anim_sprite.animation

	# Check if changing direction (velocity sign changed)
	var direction_changed = (was_moving and
		((vel_x > 0 and player_body.velocity.x < 0) or
		 (vel_x < 0 and player_body.velocity.x > 0)))

	# Stopping or turning around from max speed
	if was_at_max_speed and (h_speed < run_speed_threshold or direction_changed):
		if current_anim != "run_end":
			play_animation("run_end")
		return

	# Starting to run (reaching max speed)
	if h_speed >= run_speed_threshold:
		if !was_at_max_speed and current_anim != "run_start" and current_anim != "run":
			play_animation("run_start")
		# Transition from run_start to run
		elif current_anim == "run_start" and !anim_sprite.is_playing():
			play_animation("run")
		# Already running
		elif current_anim != "run_start" and current_anim != "run":
			play_animation("run")

		# Speed scale for run animation
		anim_sprite.speed_scale = clamp(h_speed / run_speed_threshold, 0.8, 1.5)

	# Walking
	elif h_speed > walk_speed_threshold:
		# Transition from landing
		if current_anim == "jumptorun" and !anim_sprite.is_playing():
			play_animation("walk")
		elif current_anim != "walk":
			play_animation("walk")

		anim_sprite.speed_scale = clamp(h_speed / walk_speed_threshold, 0.6, 1.2)

	# Slow movement
	else:
		play_animation("walk")
		anim_sprite.speed_scale = 0.5

func handle_idle_or_stopping(h_speed: float):
	var current_anim = anim_sprite.animation

	# Coming to a stop from running
	if was_at_max_speed and current_anim != "run_end":
		play_animation("run_end")
		return

	# Transition to idle after run_end finishes
	if current_anim == "run_end" and !anim_sprite.is_playing():
		play_animation("idle")
		return

	# Transition to idle after landing finishes
	if current_anim == "jump_landing" and !anim_sprite.is_playing():
		play_animation("idle")
		return

	# Default idle
	if current_anim != "idle" and current_anim != "run_end" and current_anim != "jump_landing":
		play_animation("idle")

	anim_sprite.speed_scale = 1.0

func handle_crouch_animations(h_speed: float):
	var current_anim = anim_sprite.animation

	# Just started crouching
	if current_anim != "crouch_start" and current_anim != "crouch_idle" and current_anim != "crouch_walk":
		play_animation("crouch_start")

	# Transition from crouch_start to idle/walk
	elif current_anim == "crouch_start" and !anim_sprite.is_playing():
		if h_speed > 5.0:
			play_animation("crouch_walk")
		else:
			play_animation("crouch_idle")

	# Already crouching - check movement
	elif current_anim == "crouch_idle" or current_anim == "crouch_walk":
		if h_speed > 5.0:
			if current_anim != "crouch_walk":
				play_animation("crouch_walk")
			anim_sprite.speed_scale = clamp(h_speed / 50.0, 0.5, 1.2)
		else:
			if current_anim != "crouch_idle":
				play_animation("crouch_idle")
			anim_sprite.speed_scale = 1.0

func set_crouching(crouching: bool):
	var was_crouching = is_crouching
	is_crouching = crouching

	# Stopped crouching - play end animation
	if was_crouching and !is_crouching:
		play_animation("crouch_end")

func play_animation(anim_name: String):
	if anim_sprite.sprite_frames.has_animation(anim_name):
		if anim_sprite.animation != anim_name:
			anim_sprite.play(anim_name)
	else:
		push_warning("Animation not found: " + anim_name)

# Public function to flip sprite direction
func set_direction(facing_right: bool):
	if anim_sprite:
		anim_sprite.flip_h = !facing_right
