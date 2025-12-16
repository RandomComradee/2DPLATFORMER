extends CharacterBody2D

## EXAMPLE: How to integrate KnightAnimationController with your movement code
## This shows the minimal changes needed to your existing player script

# Your existing movement variables (keep all of these)
@export var speed = 200.0
@export var jump_velocity = -400.0
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# Add reference to animation controller
@onready var anim_controller: KnightAnimationController = $KnightAnimationController

func _physics_process(delta):
	# YOUR MOVEMENT CODE STAYS THE SAME
	# Example movement (replace with your actual code):

	if not is_on_floor():
		velocity.y += gravity * delta

	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = jump_velocity

	var direction = Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)

	move_and_slide()

	# ADD THIS: Update sprite direction based on movement
	if direction != 0 and anim_controller:
		anim_controller.set_direction(direction > 0)

	# ADD THIS: Update crouch state if you have crouching
	if Input.is_action_pressed("ui_down") and is_on_floor():
		if anim_controller:
			anim_controller.set_crouching(true)
	else:
		if anim_controller:
			anim_controller.set_crouching(false)

# That's it! The animation controller handles everything automatically
# No need to manually call play_animation() anywhere else
