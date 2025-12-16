extends CharacterBody2D

@export var README: String = "IMPORTANT: MAKE SURE TO ASSIGN 'left' 'right' 'jump' 'dash' 'up' 'down' 'roll' 'latch' 'twirl' 'run' 'attack' 'heavy_attack' 'block' in the project settings input map."

@export_category("Necesary Child Nodes")
@export var PlayerSprite: AnimatedSprite2D
@export var PlayerCollider: CollisionShape2D

@export_category("L/R Movement")
@export_range(50, 500) var maxSpeed: float = 200.0
@export_range(0, 4) var timeToReachMaxSpeed: float = 0.2
@export_range(0, 4) var timeToReachZeroSpeed: float = 0.2
@export var directionalSnap: bool = false
@export var runningModifier: bool = false

@export_category("Jumping and Gravity")
@export_range(0, 20) var jumpHeight: float = 2.0
@export_range(0, 4) var jumps: int = 1
@export_range(0, 100) var gravityScale: float = 20.0
@export_range(0, 1000) var terminalVelocity: float = 500.0
@export_range(0.5, 3) var descendingGravityFactor: float = 1.3
@export var shortHopAkaVariableJumpHeight: bool = true
@export_range(1, 10) var jumpVariable: float = 2
@export_range(0, 0.5) var coyoteTime: float = 0.2
@export_range(0, 0.5) var jumpBuffering: float = 0.2

@export_category("Wall Jumping")
@export var wallJump: bool = false
@export_range(0, 0.5) var inputPauseAfterWallJump: float = 0.1
@export_range(0, 90) var wallKickAngle: float = 60.0
@export_range(1, 20) var wallSliding: float = 1.0
@export var wallLatching: bool = false
@export var wallLatchingModifer: bool = false

@export_category("Dashing")
@export_enum("None", "Horizontal", "Vertical", "Four Way", "Eight Way") var dashType: int
@export_range(0, 10) var dashes: int = 1
@export var dashCancel: bool = true
@export_range(1.5, 4) var dashLength: float = 2.5

@export_category("Corner Cutting/Jump Correct")
@export var cornerCutting: bool = false
@export_range(1, 5) var correctionAmount: float = 1.5
@export var leftRaycast: RayCast2D
@export var middleRaycast: RayCast2D
@export var rightRaycast: RayCast2D

@export_category("Down Input")
@export var crouch: bool = false
@export var canRoll: bool
@export_range(1.25, 2) var rollLength: float = 2
@export var groundPound: bool
@export_range(0.05, 0.75) var groundPoundPause: float = 0.25
@export var upToCancel: bool = false

# Internal variables
var appliedGravity: float
var maxSpeedLock: float
var appliedTerminalVelocity: float
var acceleration: float
var deceleration: float
var instantAccel: bool = false
var instantStop: bool = false
var jumpMagnitude: float = 500.0
var jumpCount: int
var jumpWasPressed: bool = false
var coyoteActive: bool = false
var dashMagnitude: float
var gravityActive: bool = true
var dashing: bool = false
var dashCount: int
var rolling: bool = false
var twoWayDashHorizontal: bool = false
var twoWayDashVertical: bool = false
var eightWayDash: bool = false
var wasMovingR: bool = true
var wasPressingR: bool = true
var movementInputMonitoring: Vector2 = Vector2(true, true)
var gdelta: float = 1
var dset: bool = false
var colliderScaleLockY: float
var colliderPosLockY: float
var latched: bool = false
var wasLatched: bool = false
var crouching: bool = false
var groundPounding: bool = false
var anim: AnimatedSprite2D
var col: CollisionShape2D
var animScaleLock: Vector2

# Animation state tracking
var _was_on_floor: bool = true
var _was_on_wall: bool = false
var _was_at_max_speed: bool = false
var _was_moving: bool = false
var _was_crouching: bool = false
var _prev_velocity_x: float = 0.0
var _playing_one_shot: bool = false
var _current_one_shot: String = ""

# Input variables
var upHold: bool = false
var downHold: bool = false
var leftHold: bool = false
var leftTap: bool = false
var leftRelease: bool = false
var rightHold: bool = false
var rightTap: bool = false
var rightRelease: bool = false
var jumpTap: bool = false
var jumpRelease: bool = false
var runHold: bool = false
var latchHold: bool = false
var dashTap: bool = false
var rollTap: bool = false
var downTap: bool = false
var twirlTap: bool = false

func _ready():
	anim = PlayerSprite
	col = PlayerCollider
	_updateData()
	if anim:
		anim.animation_finished.connect(_on_anim_finished)

func _updateData():
	acceleration = maxSpeed / timeToReachMaxSpeed
	deceleration = -maxSpeed / timeToReachZeroSpeed
	jumpMagnitude = (10.0 * jumpHeight) * gravityScale
	jumpCount = jumps
	dashMagnitude = maxSpeed * dashLength
	dashCount = dashes
	maxSpeedLock = maxSpeed
	animScaleLock = abs(anim.scale)
	colliderScaleLockY = col.scale.y
	colliderPosLockY = col.position.y

	if timeToReachMaxSpeed == 0:
		instantAccel = true
		timeToReachMaxSpeed = 1
	else:
		instantAccel = false

	if timeToReachZeroSpeed == 0:
		instantStop = true
		timeToReachZeroSpeed = 1
	else:
		instantStop = false

	if jumps > 1:
		jumpBuffering = 0
		coyoteTime = 0

	if directionalSnap:
		instantAccel = true
		instantStop = true

	twoWayDashHorizontal = dashType == 1 or dashType == 3
	twoWayDashVertical = dashType == 2 or dashType == 3
	eightWayDash = dashType == 4

func _process(_delta):
	_handle_animations()

func _handle_animations():
	if !anim:
		return

	# Update latched state
	if is_on_wall() and !is_on_floor() and wallLatching and ((wallLatchingModifer and latchHold) or !wallLatchingModifer):
		latched = true
	else:
		latched = false

	# Sprite direction
	if rightHold and !latched:
		anim.scale.x = animScaleLock.x
	if leftHold and !latched:
		anim.scale.x = -animScaleLock.x

	# State calculations
	var is_moving = abs(velocity.x) > 10.0
	var is_at_max_speed = abs(velocity.x) >= maxSpeedLock * 0.85
	var is_falling = velocity.y > 50.0
	var is_rising = velocity.y < -50.0
	var is_transition = !is_falling and !is_rising and !is_on_floor()
	var velocity_flipped = abs(_prev_velocity_x) > 10.0 and abs(velocity.x) > 10.0 and sign(_prev_velocity_x) != sign(velocity.x)

	# If playing one-shot, wait for it to finish
	if _playing_one_shot:
		_update_prev_state(is_moving, is_at_max_speed)
		return

	# Determine animation
	var target_anim: String = "idle"
	var one_shot: bool = false
	var spd: float = 1.0

	# ROLLING (highest priority for movement)
	if rolling:
		target_anim = "roll"

	# DASHING
	elif dashing:
		target_anim = "dash_attack"

	# WALL SLIDE
	elif is_on_wall() and !is_on_floor() and wallSliding != 1.0:
		if !_was_on_wall:
			target_anim = "wall_slide_contact"
			one_shot = true
		else:
			target_anim = "wall_slide_loop"

	# LANDING (just hit floor)
	elif is_on_floor() and !_was_on_floor:
		if (rightHold or leftHold) and is_moving:
			target_anim = "jumptorun"
			one_shot = true
		else:
			target_anim = "jump_landing"
			one_shot = true

	# AIRBORNE
	elif !is_on_floor():
		if is_rising:
			target_anim = "jump_rise_loop"
		elif is_transition:
			target_anim = "jump_transition"
			one_shot = true
		else:
			target_anim = "jump_fall_loop"

	# CROUCHING
	elif crouching:
		if !_was_crouching:
			target_anim = "crouch_start"
			one_shot = true
		elif is_moving:
			target_anim = "crouch_walk"
			spd = clamp(abs(velocity.x) / 80.0, 0.5, 1.2)
		else:
			target_anim = "crouch_idle"

	# CROUCH END
	elif _was_crouching and !crouching:
		target_anim = "crouch_end"
		one_shot = true

	# GROUND MOVEMENT
	elif is_on_floor():
		# Turn around from run
		if _was_at_max_speed and velocity_flipped:
			target_anim = "run_end"
			one_shot = true
		# Just reached max speed
		elif is_at_max_speed and !_was_at_max_speed and _was_moving:
			target_anim = "run_start"
			one_shot = true
		# Stopped from running
		elif !is_moving and _was_moving and _was_at_max_speed:
			target_anim = "run_end"
			one_shot = true
		# Running
		elif is_at_max_speed:
			target_anim = "run"
			spd = clamp(abs(velocity.x) / 150.0, 0.8, 1.5)
		# Walking
		elif is_moving:
			target_anim = "walk"
			spd = clamp(abs(velocity.x) / 100.0, 0.5, 1.5)
		# Idle
		else:
			target_anim = "idle"

	# Play animation
	_play_anim(target_anim, one_shot, spd)

	# Update previous state
	_update_prev_state(is_moving, is_at_max_speed)

func _play_anim(anim_name: String, one_shot: bool, spd: float):
	# Check if animation exists, use fallback if not
	if !anim.sprite_frames.has_animation(anim_name):
		anim_name = _get_fallback(anim_name)
		if !anim.sprite_frames.has_animation(anim_name):
			return

	if one_shot:
		_playing_one_shot = true
		_current_one_shot = anim_name

	if anim.animation != anim_name:
		anim.play(anim_name)
	anim.speed_scale = spd

func _get_fallback(name: String) -> String:
	match name:
		"run_start", "run_end": return "run"
		"crouch_start", "crouch_end": return "crouch_idle"
		"jump_transition": return "jump_fall_loop"
		"jump_landing", "jumptorun": return "idle"
		"wall_slide_contact": return "wall_slide_loop"
		"walk": return "run"
	return "idle"

func _on_anim_finished():
	if !_playing_one_shot:
		return

	_playing_one_shot = false

	match _current_one_shot:
		"run_start":
			anim.play("run")
		"run_end":
			anim.play("idle")
		"crouch_start":
			anim.play("crouch_idle")
		"crouch_end":
			anim.play("idle")
		"jump_transition":
			anim.play("jump_fall_loop")
		"jump_landing":
			anim.play("idle")
		"jumptorun":
			anim.play("run")
		"wall_slide_contact":
			anim.play("wall_slide_loop")

func _update_prev_state(is_moving: bool, is_at_max: bool):
	_was_on_floor = is_on_floor()
	_was_on_wall = is_on_wall()
	_was_at_max_speed = is_at_max
	_was_moving = is_moving
	_was_crouching = crouching
	_prev_velocity_x = velocity.x

func _physics_process(delta):
	if !dset:
		gdelta = delta
		dset = true

	# Input Detection
	leftHold = Input.is_action_pressed("left")
	rightHold = Input.is_action_pressed("right")
	upHold = Input.is_action_pressed("up")
	downHold = Input.is_action_pressed("down")
	leftTap = Input.is_action_just_pressed("left")
	rightTap = Input.is_action_just_pressed("right")
	leftRelease = Input.is_action_just_released("left")
	rightRelease = Input.is_action_just_released("right")
	jumpTap = Input.is_action_just_pressed("jump")
	jumpRelease = Input.is_action_just_released("jump")
	runHold = Input.is_action_pressed("run")
	latchHold = Input.is_action_pressed("latch")
	dashTap = Input.is_action_just_pressed("dash")
	rollTap = Input.is_action_just_pressed("roll")
	downTap = Input.is_action_just_pressed("down")
	twirlTap = Input.is_action_just_pressed("twirl")

	# Left and Right Movement
	if rightHold and leftHold and movementInputMonitoring:
		if !instantStop:
			_decelerate(delta, false)
		else:
			velocity.x = -0.1
	elif rightHold and movementInputMonitoring.x:
		if velocity.x > maxSpeed or instantAccel:
			velocity.x = maxSpeed
		else:
			velocity.x += acceleration * delta
		if velocity.x < 0:
			if !instantStop:
				_decelerate(delta, false)
			else:
				velocity.x = -0.1
	elif leftHold and movementInputMonitoring.y:
		if velocity.x < -maxSpeed or instantAccel:
			velocity.x = -maxSpeed
		else:
			velocity.x -= acceleration * delta
		if velocity.x > 0:
			if !instantStop:
				_decelerate(delta, false)
			else:
				velocity.x = 0.1

	if velocity.x > 0:
		wasMovingR = true
	elif velocity.x < 0:
		wasMovingR = false

	if rightTap:
		wasPressingR = true
	if leftTap:
		wasPressingR = false

	if runningModifier and !runHold:
		maxSpeed = maxSpeedLock / 2
	elif is_on_floor():
		maxSpeed = maxSpeedLock

	if !(leftHold or rightHold):
		if !instantStop:
			_decelerate(delta, false)
		else:
			velocity.x = 0

	# Crouching
	if crouch:
		if downHold and is_on_floor():
			crouching = true
		elif !downHold and !rolling:
			crouching = false

	if !is_on_floor():
		crouching = false

	if crouching:
		maxSpeed = maxSpeedLock / 2
		col.scale.y = colliderScaleLockY / 2
		col.position.y = colliderPosLockY + (8 * colliderScaleLockY)
	elif !runningModifier or (runningModifier and runHold):
		maxSpeed = maxSpeedLock
		col.scale.y = colliderScaleLockY
		col.position.y = colliderPosLockY

	# Rolling
	if canRoll and is_on_floor() and rollTap and crouching:
		_rollingTime(rollLength * 0.25)
		if wasPressingR and !upHold:
			velocity.y = 0
			velocity.x = maxSpeedLock * rollLength
			dashCount -= 1
			movementInputMonitoring = Vector2(false, false)
			_inputPauseReset(rollLength * 0.0625)
		elif !upHold:
			velocity.y = 0
			velocity.x = -maxSpeedLock * rollLength
			dashCount -= 1
			movementInputMonitoring = Vector2(false, false)
			_inputPauseReset(rollLength * 0.0625)

	# Jump and Gravity
	if velocity.y > 0:
		appliedGravity = gravityScale * descendingGravityFactor
	else:
		appliedGravity = gravityScale

	if is_on_wall() and !groundPounding:
		appliedTerminalVelocity = terminalVelocity / wallSliding
		if wallLatching and ((wallLatchingModifer and latchHold) or !wallLatchingModifer):
			appliedGravity = 0
			if velocity.y < 0:
				velocity.y += 50
			if velocity.y > 0:
				velocity.y = 0
			if wallLatchingModifer and latchHold and movementInputMonitoring == Vector2(true, true):
				velocity.x = 0
		elif wallSliding != 1 and velocity.y > 0:
			appliedGravity = appliedGravity / wallSliding
	elif !is_on_wall() and !groundPounding:
		appliedTerminalVelocity = terminalVelocity

	if gravityActive:
		if velocity.y < appliedTerminalVelocity:
			velocity.y += appliedGravity
		elif velocity.y > appliedTerminalVelocity:
			velocity.y = appliedTerminalVelocity

	if shortHopAkaVariableJumpHeight and jumpRelease and velocity.y < 0:
		velocity.y = velocity.y / jumpVariable

	if jumps == 1:
		if !is_on_floor() and !is_on_wall():
			if coyoteTime > 0:
				coyoteActive = true
				_coyoteTime()

		if jumpTap and !is_on_wall():
			if coyoteActive:
				coyoteActive = false
				_jump()
			if jumpBuffering > 0:
				jumpWasPressed = true
				_bufferJump()
			elif jumpBuffering == 0 and coyoteTime == 0 and is_on_floor():
				_jump()
		elif jumpTap and is_on_wall() and !is_on_floor():
			if wallJump:
				_wallJump()
		elif jumpTap and is_on_floor():
			_jump()

		if is_on_floor():
			jumpCount = jumps
			if coyoteTime > 0:
				coyoteActive = true
			else:
				coyoteActive = false
			if jumpWasPressed:
				_jump()

	elif jumps > 1:
		if is_on_floor():
			jumpCount = jumps
		if jumpTap and is_on_wall() and wallJump:
			_wallJump()
		elif jumpTap and jumpCount > 0:
			velocity.y = -jumpMagnitude
			jumpCount -= 1
			_endGroundPound()

	# Dashing
	if is_on_floor():
		dashCount = dashes
	if eightWayDash and dashTap and dashCount > 0 and !rolling:
		var input_direction = Input.get_vector("left", "right", "up", "down")
		var dTime = 0.0625 * dashLength
		_dashingTime(dTime)
		_pauseGravity(dTime)
		velocity = dashMagnitude * input_direction
		if !rightHold and !leftHold and !downHold and !upHold:
			velocity.x = dashMagnitude if wasMovingR else -dashMagnitude
		dashCount -= 1
		movementInputMonitoring = Vector2(false, false)
		_inputPauseReset(dTime)

	if twoWayDashVertical and dashTap and dashCount > 0 and !rolling:
		var dTime = 0.0625 * dashLength
		if upHold and !downHold:
			_dashingTime(dTime)
			_pauseGravity(dTime)
			velocity.x = 0
			velocity.y = -dashMagnitude
			dashCount -= 1
			movementInputMonitoring = Vector2(false, false)
			_inputPauseReset(dTime)
		elif downHold and !upHold:
			_dashingTime(dTime)
			_pauseGravity(dTime)
			velocity.x = 0
			velocity.y = dashMagnitude
			dashCount -= 1
			movementInputMonitoring = Vector2(false, false)
			_inputPauseReset(dTime)

	if twoWayDashHorizontal and dashTap and dashCount > 0 and !rolling:
		var dTime = 0.0625 * dashLength
		if !upHold and !downHold:
			velocity.y = 0
			velocity.x = dashMagnitude if wasPressingR else -dashMagnitude
			_pauseGravity(dTime)
			_dashingTime(dTime)
			dashCount -= 1
			movementInputMonitoring = Vector2(false, false)
			_inputPauseReset(dTime)

	if dashing and velocity.x > 0 and leftTap and dashCancel:
		velocity.x = 0
	if dashing and velocity.x < 0 and rightTap and dashCancel:
		velocity.x = 0

	# Corner Cutting
	if cornerCutting:
		if velocity.y < 0 and leftRaycast.is_colliding() and !rightRaycast.is_colliding() and !middleRaycast.is_colliding():
			position.x += correctionAmount
		if velocity.y < 0 and !leftRaycast.is_colliding() and rightRaycast.is_colliding() and !middleRaycast.is_colliding():
			position.x -= correctionAmount

	# Ground Pound
	if groundPound and downTap and !is_on_floor() and !is_on_wall():
		groundPounding = true
		gravityActive = false
		velocity.y = 0
		await get_tree().create_timer(groundPoundPause).timeout
		_groundPound()
	if is_on_floor() and groundPounding:
		_endGroundPound()

	move_and_slide()

	if upToCancel and upHold and groundPound:
		_endGroundPound()

func _bufferJump():
	await get_tree().create_timer(jumpBuffering).timeout
	jumpWasPressed = false

func _coyoteTime():
	await get_tree().create_timer(coyoteTime).timeout
	coyoteActive = false
	jumpCount -= 1

func _jump():
	if jumpCount > 0:
		velocity.y = -jumpMagnitude
		jumpCount -= 1
		jumpWasPressed = false

func _wallJump():
	var horizontalWallKick = abs(jumpMagnitude * cos(wallKickAngle * (PI / 180)))
	var verticalWallKick = abs(jumpMagnitude * sin(wallKickAngle * (PI / 180)))
	velocity.y = -verticalWallKick
	var dir = -1 if (wallLatchingModifer and latchHold) else 1
	velocity.x = -horizontalWallKick * dir if wasMovingR else horizontalWallKick * dir
	if inputPauseAfterWallJump != 0:
		movementInputMonitoring = Vector2(false, false)
		_inputPauseReset(inputPauseAfterWallJump)

func _inputPauseReset(time):
	await get_tree().create_timer(time).timeout
	movementInputMonitoring = Vector2(true, true)

func _decelerate(delta, vertical):
	if !vertical:
		if abs(velocity.x) > 0 and abs(velocity.x) <= abs(deceleration * delta):
			velocity.x = 0
		elif velocity.x > 0:
			velocity.x += deceleration * delta
		elif velocity.x < 0:
			velocity.x -= deceleration * delta
	elif vertical and velocity.y > 0:
		velocity.y += deceleration * delta

func _pauseGravity(time):
	gravityActive = false
	await get_tree().create_timer(time).timeout
	gravityActive = true

func _dashingTime(time):
	dashing = true
	await get_tree().create_timer(time).timeout
	dashing = false
	if !is_on_floor():
		velocity.y = -gravityScale * 10

func _rollingTime(time):
	rolling = true
	await get_tree().create_timer(time).timeout
	rolling = false

func _groundPound():
	appliedTerminalVelocity = terminalVelocity * 10
	velocity.y = jumpMagnitude * 2

func _endGroundPound():
	groundPounding = false
	appliedTerminalVelocity = terminalVelocity
	gravityActive = true
