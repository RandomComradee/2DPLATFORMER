extends CharacterBody2D

@export var README: String = "Assign 'left' 'right' 'jump' 'dash' 'up' 'down' 'roll' 'latch' 'run' in project input settings."

@export_category("Required Nodes")
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
@export_enum("None", "Horizontal", "Vertical", "Four Way", "Eight Way") var dashType: int = 0
@export_range(0, 10) var dashes: int = 1
@export var dashCancel: bool = true
@export_range(1.5, 4) var dashLength: float = 2.5

@export_category("Corner Cutting")
@export var cornerCutting: bool = false
@export_range(1, 5) var correctionAmount: float = 1.5
@export var leftRaycast: RayCast2D
@export var middleRaycast: RayCast2D
@export var rightRaycast: RayCast2D

@export_category("Crouch & Roll")
@export var crouch: bool = false
@export var canRoll: bool = false
@export_range(1.25, 2) var rollLength: float = 2
@export var groundPound: bool = false
@export_range(0.05, 0.75) var groundPoundPause: float = 0.25
@export var upToCancel: bool = false

# Internal state - exposed for animation state machine to read
var crouching: bool = false
var rolling: bool = false
var dashing: bool = false
var latched: bool = false
var groundPounding: bool = false

# Private vars
var _maxSpeedLock: float
var _acceleration: float
var _deceleration: float
var _instantAccel: bool = false
var _instantStop: bool = false
var _jumpMagnitude: float = 500.0
var _jumpCount: int
var _jumpWasPressed: bool = false
var _coyoteActive: bool = false
var _dashMagnitude: float
var _gravityActive: bool = true
var _dashCount: int
var _appliedGravity: float
var _appliedTerminalVelocity: float

var _twoWayDashH: bool = false
var _twoWayDashV: bool = false
var _eightWayDash: bool = false

var _wasMovingR: bool = true
var _wasPressingR: bool = true
var _moveInputEnabled: Vector2 = Vector2(true, true)

var _colliderScaleY: float
var _colliderPosY: float
var _spriteScale: Vector2

var _animMachine: AnimationStateMachine

func _ready() -> void:
	_setup()
	_createAnimationMachine()

func _setup() -> void:
	_maxSpeedLock = maxSpeed
	_acceleration = maxSpeed / max(timeToReachMaxSpeed, 0.001)
	_deceleration = -maxSpeed / max(timeToReachZeroSpeed, 0.001)
	_jumpMagnitude = (10.0 * jumpHeight) * gravityScale
	_jumpCount = jumps
	_dashMagnitude = maxSpeed * dashLength
	_dashCount = dashes

	_spriteScale = abs(PlayerSprite.scale)
	_colliderScaleY = PlayerCollider.scale.y
	_colliderPosY = PlayerCollider.position.y

	_instantAccel = timeToReachMaxSpeed == 0 or directionalSnap
	_instantStop = timeToReachZeroSpeed == 0 or directionalSnap

	if jumps > 1:
		jumpBuffering = 0
		coyoteTime = 0

	_twoWayDashH = dashType == 1 or dashType == 3
	_twoWayDashV = dashType == 2 or dashType == 3
	_eightWayDash = dashType == 4

func _createAnimationMachine() -> void:
	_animMachine = AnimationStateMachine.new()
	_animMachine.name = "AnimationStateMachine"
	add_child(_animMachine)
	_animMachine.setup(PlayerSprite, self, _maxSpeedLock, wallSliding)

func _physics_process(delta: float) -> void:
	_handleInput()
	_handleHorizontalMovement(delta)
	_handleCrouch()
	_handleRoll()
	_handleGravity()
	_handleJump()
	_handleDash()
	_handleCornerCutting()
	_handleGroundPound()
	move_and_slide()

func _handleInput() -> void:
	# Input is read fresh each frame
	pass

func _handleHorizontalMovement(delta: float) -> void:
	var leftHold := Input.is_action_pressed("left")
	var rightHold := Input.is_action_pressed("right")
	var leftTap := Input.is_action_just_pressed("left")
	var rightTap := Input.is_action_just_pressed("right")
	var runHold := Input.is_action_pressed("run")

	# Update latched state
	var latchHold := Input.is_action_pressed("latch")
	if is_on_wall() and !is_on_floor() and wallLatching:
		if !wallLatchingModifer or latchHold:
			latched = true
		else:
			latched = false
	else:
		latched = false

	# Both directions pressed
	if rightHold and leftHold and _moveInputEnabled:
		if !_instantStop:
			_decel(delta)
		else:
			velocity.x = 0

	# Right movement
	elif rightHold and _moveInputEnabled.x:
		if velocity.x >= maxSpeed or _instantAccel:
			velocity.x = maxSpeed
		else:
			velocity.x += _acceleration * delta
		if velocity.x < 0:
			if _instantStop:
				velocity.x = 0
			else:
				_decel(delta)

	# Left movement
	elif leftHold and _moveInputEnabled.y:
		if velocity.x <= -maxSpeed or _instantAccel:
			velocity.x = -maxSpeed
		else:
			velocity.x -= _acceleration * delta
		if velocity.x > 0:
			if _instantStop:
				velocity.x = 0
			else:
				_decel(delta)

	# No input - decelerate
	elif !leftHold and !rightHold:
		if _instantStop:
			velocity.x = 0
		else:
			_decel(delta)

	# Track direction
	if velocity.x > 0:
		_wasMovingR = true
	elif velocity.x < 0:
		_wasMovingR = false

	if rightTap:
		_wasPressingR = true
	elif leftTap:
		_wasPressingR = false

	# Running modifier
	if runningModifier and !runHold:
		maxSpeed = _maxSpeedLock / 2
	elif is_on_floor():
		maxSpeed = _maxSpeedLock

func _handleCrouch() -> void:
	if !crouch:
		return

	var downHold := Input.is_action_pressed("down")

	if downHold and is_on_floor():
		crouching = true
	elif !downHold and !rolling:
		crouching = false

	if !is_on_floor():
		crouching = false

	if crouching:
		maxSpeed = _maxSpeedLock / 2
		PlayerCollider.scale.y = _colliderScaleY / 2
		PlayerCollider.position.y = _colliderPosY + (8 * _colliderScaleY)
	else:
		if !runningModifier or Input.is_action_pressed("run"):
			maxSpeed = _maxSpeedLock
		PlayerCollider.scale.y = _colliderScaleY
		PlayerCollider.position.y = _colliderPosY

func _handleRoll() -> void:
	if !canRoll:
		return

	var rollTap := Input.is_action_just_pressed("roll")
	var upHold := Input.is_action_pressed("up")

	if is_on_floor() and rollTap and crouching:
		_startRoll()
		velocity.y = 0
		if _wasPressingR and !upHold:
			velocity.x = _maxSpeedLock * rollLength
		elif !upHold:
			velocity.x = -_maxSpeedLock * rollLength
		_dashCount -= 1
		_moveInputEnabled = Vector2(false, false)
		_resetMoveInput(rollLength * 0.0625)

func _startRoll() -> void:
	rolling = true
	await get_tree().create_timer(rollLength * 0.25).timeout
	rolling = false

func _handleGravity() -> void:
	if velocity.y > 0:
		_appliedGravity = gravityScale * descendingGravityFactor
	else:
		_appliedGravity = gravityScale

	if is_on_wall() and !groundPounding:
		_appliedTerminalVelocity = terminalVelocity / wallSliding
		var latchHold := Input.is_action_pressed("latch")
		if wallLatching and (!wallLatchingModifer or latchHold):
			_appliedGravity = 0
			if velocity.y < 0:
				velocity.y += 50
			if velocity.y > 0:
				velocity.y = 0
			if wallLatchingModifer and latchHold and _moveInputEnabled == Vector2(true, true):
				velocity.x = 0
		elif wallSliding != 1 and velocity.y > 0:
			_appliedGravity = _appliedGravity / wallSliding
	else:
		_appliedTerminalVelocity = terminalVelocity

	if _gravityActive:
		if velocity.y < _appliedTerminalVelocity:
			velocity.y += _appliedGravity
		else:
			velocity.y = _appliedTerminalVelocity

	# Variable jump height
	if shortHopAkaVariableJumpHeight and Input.is_action_just_released("jump") and velocity.y < 0:
		velocity.y /= jumpVariable

func _handleJump() -> void:
	var jumpTap := Input.is_action_just_pressed("jump")

	if jumps == 1:
		# Coyote time
		if !is_on_floor() and !is_on_wall() and coyoteTime > 0:
			_coyoteActive = true
			_startCoyoteTimer()

		if jumpTap and !is_on_wall():
			if _coyoteActive:
				_coyoteActive = false
				_jump()
			elif jumpBuffering > 0:
				_jumpWasPressed = true
				_startJumpBuffer()
			elif jumpBuffering == 0 and coyoteTime == 0 and is_on_floor():
				_jump()
		elif jumpTap and is_on_wall() and !is_on_floor() and wallJump:
			_wallJump()
		elif jumpTap and is_on_floor():
			_jump()

		if is_on_floor():
			_jumpCount = jumps
			_coyoteActive = coyoteTime > 0
			if _jumpWasPressed:
				_jump()

	else:
		if is_on_floor():
			_jumpCount = jumps
		if jumpTap and is_on_wall() and wallJump:
			_wallJump()
		elif jumpTap and _jumpCount > 0:
			velocity.y = -_jumpMagnitude
			_jumpCount -= 1
			_endGroundPound()

func _jump() -> void:
	if _jumpCount > 0:
		velocity.y = -_jumpMagnitude
		_jumpCount -= 1
		_jumpWasPressed = false

func _wallJump() -> void:
	var hKick: float = absf(_jumpMagnitude * cos(wallKickAngle * PI / 180))
	var vKick: float = absf(_jumpMagnitude * sin(wallKickAngle * PI / 180))
	velocity.y = -vKick
	var latchHold: bool = Input.is_action_pressed("latch")
	var dir: int = -1 if (wallLatchingModifer and latchHold) else 1
	velocity.x = (-hKick if _wasMovingR else hKick) * dir
	if inputPauseAfterWallJump > 0:
		_moveInputEnabled = Vector2(false, false)
		_resetMoveInput(inputPauseAfterWallJump)

func _startCoyoteTimer() -> void:
	await get_tree().create_timer(coyoteTime).timeout
	_coyoteActive = false
	_jumpCount -= 1

func _startJumpBuffer() -> void:
	await get_tree().create_timer(jumpBuffering).timeout
	_jumpWasPressed = false

func _handleDash() -> void:
	var dashTap := Input.is_action_just_pressed("dash")
	var upHold := Input.is_action_pressed("up")
	var downHold := Input.is_action_pressed("down")
	var leftHold := Input.is_action_pressed("left")
	var rightHold := Input.is_action_pressed("right")

	if is_on_floor():
		_dashCount = dashes

	# 8-way dash
	if _eightWayDash and dashTap and _dashCount > 0 and !rolling:
		var dir := Input.get_vector("left", "right", "up", "down")
		var dTime := 0.0625 * dashLength
		_startDash(dTime)
		_pauseGravity(dTime)
		velocity = _dashMagnitude * dir
		if !rightHold and !leftHold and !downHold and !upHold:
			velocity.x = _dashMagnitude if _wasMovingR else -_dashMagnitude
		_dashCount -= 1
		_moveInputEnabled = Vector2(false, false)
		_resetMoveInput(dTime)

	# Vertical dash
	if _twoWayDashV and dashTap and _dashCount > 0 and !rolling:
		var dTime := 0.0625 * dashLength
		if upHold and !downHold:
			_startDash(dTime)
			_pauseGravity(dTime)
			velocity = Vector2(0, -_dashMagnitude)
			_dashCount -= 1
			_moveInputEnabled = Vector2(false, false)
			_resetMoveInput(dTime)
		elif downHold and !upHold:
			_startDash(dTime)
			_pauseGravity(dTime)
			velocity = Vector2(0, _dashMagnitude)
			_dashCount -= 1
			_moveInputEnabled = Vector2(false, false)
			_resetMoveInput(dTime)

	# Horizontal dash
	if _twoWayDashH and dashTap and _dashCount > 0 and !rolling:
		var dTime := 0.0625 * dashLength
		if !upHold and !downHold:
			_startDash(dTime)
			_pauseGravity(dTime)
			velocity = Vector2(_dashMagnitude if _wasPressingR else -_dashMagnitude, 0)
			_dashCount -= 1
			_moveInputEnabled = Vector2(false, false)
			_resetMoveInput(dTime)

	# Dash cancel
	if dashing and dashCancel:
		if velocity.x > 0 and Input.is_action_just_pressed("left"):
			velocity.x = 0
		if velocity.x < 0 and Input.is_action_just_pressed("right"):
			velocity.x = 0

func _startDash(time: float) -> void:
	dashing = true
	await get_tree().create_timer(time).timeout
	dashing = false
	if !is_on_floor():
		velocity.y = -gravityScale * 10

func _pauseGravity(time: float) -> void:
	_gravityActive = false
	await get_tree().create_timer(time).timeout
	_gravityActive = true

func _handleCornerCutting() -> void:
	if !cornerCutting or !leftRaycast or !middleRaycast or !rightRaycast:
		return

	if velocity.y < 0:
		if leftRaycast.is_colliding() and !rightRaycast.is_colliding() and !middleRaycast.is_colliding():
			position.x += correctionAmount
		elif !leftRaycast.is_colliding() and rightRaycast.is_colliding() and !middleRaycast.is_colliding():
			position.x -= correctionAmount

func _handleGroundPound() -> void:
	if !groundPound:
		return

	var downTap := Input.is_action_just_pressed("down")
	var upHold := Input.is_action_pressed("up")

	if downTap and !is_on_floor() and !is_on_wall():
		groundPounding = true
		_gravityActive = false
		velocity.y = 0
		await get_tree().create_timer(groundPoundPause).timeout
		_appliedTerminalVelocity = terminalVelocity * 10
		velocity.y = _jumpMagnitude * 2

	if is_on_floor() and groundPounding:
		_endGroundPound()

	if upToCancel and upHold and groundPounding:
		_endGroundPound()

func _endGroundPound() -> void:
	groundPounding = false
	_appliedTerminalVelocity = terminalVelocity
	_gravityActive = true

func _decel(delta: float) -> void:
	if abs(velocity.x) > 0 and abs(velocity.x) <= abs(_deceleration * delta):
		velocity.x = 0
	elif velocity.x > 0:
		velocity.x += _deceleration * delta
	elif velocity.x < 0:
		velocity.x -= _deceleration * delta

func _resetMoveInput(time: float) -> void:
	await get_tree().create_timer(time).timeout
	_moveInputEnabled = Vector2(true, true)
