# Knight Animation Controller Setup

This is a clean, modular animation system that works with your existing movement code.

## Features

✅ All requested animations working:
- **wall_slide_contact** - Plays once when touching wall
- **wall_slide_loop** - Loops while sliding down
- **jump_transition** - Plays at jump peak
- **jump_rise_loop** - Loops while rising
- **jump_fall_loop** - Loops while falling
- **jump_landing** - Landing while standing
- **jumptorun** - Landing while moving
- **run_start** - Starting to run (reaching max speed)
- **run_end** - Stopping from run or turning around
- **crouch_start/idle/walk/end** - Full crouch system
- **walk** - Walking animation
- **idle** - Standing still

## How to Set Up

### Option 1: Quick Setup (Add to existing player)

1. **Open your Player scene** in Godot
2. **Select your Player (CharacterBody2D) node**
3. **Add a child node:**
   - Click the + icon
   - Search for "Node"
   - Name it "KnightAnimationController"
4. **Attach the script:**
   - Select the new node
   - Click the script icon
   - Load `Player/KnightAnimationController.gd`
5. **Assign references in Inspector:**
   - **Anim Sprite** → Drag your AnimatedSprite2D node here
   - **Player Body** → Drag your CharacterBody2D (Player) node here

### Option 2: Add to Your Player Script

Add these lines to your existing player script:

```gdscript
# At the top with your other variables
@onready var anim_controller: KnightAnimationController = $KnightAnimationController

# In your _physics_process, after move_and_slide():

# Update sprite direction (flip based on movement)
var direction = Input.get_axis("left", "right")  # Or however you get input
if direction != 0 and anim_controller:
    anim_controller.set_direction(direction > 0)

# Update crouch state (if you have crouching)
if is_crouching and anim_controller:  # Replace with your crouch condition
    anim_controller.set_crouching(true)
else:
    anim_controller.set_crouching(false)
```

That's it! Everything else is automatic.

## How It Works

The animation controller automatically detects:
- When you land (plays landing or jumptorun)
- When you start running (plays run_start then run)
- When you stop running (plays run_end then idle)
- When you turn around while running (plays run_end)
- When you hit a wall (plays wall_slide_contact once)
- When sliding on wall (loops wall_slide_loop)
- Jump peak transition (jump_rise_loop → jump_transition → jump_fall_loop)
- Crouch transitions (start → idle/walk → end)

## Speed Thresholds

You can adjust these in the Inspector:
- **Walk Speed Threshold**: 50.0 (default) - Speed to switch from idle to walk
- **Run Speed Threshold**: 150.0 (default) - Speed to play run animations

## Animation Speed Scaling

Animations automatically speed up/slow down based on movement:
- **Walk**: Scales 0.6x to 1.2x based on speed
- **Run**: Scales 0.8x to 1.5x based on speed
- **Crouch Walk**: Scales 0.5x to 1.2x based on speed

## No Changes Needed to Movement Code

Your movement code stays exactly the same! The animation controller just reads:
- `player_body.velocity`
- `player_body.is_on_floor()`
- `player_body.is_on_wall()`

It doesn't modify any physics or movement.

## Troubleshooting

**Animations not playing?**
- Check that Anim Sprite and Player Body are assigned in Inspector
- Check the Output/Debugger for "Animation not found" warnings

**Wrong animations playing?**
- Adjust Walk Speed Threshold and Run Speed Threshold in Inspector
- Check that your AnimatedSprite2D has all the required animations

**Sprite not flipping?**
- Make sure you call `anim_controller.set_direction(facing_right)` in your movement code

## Architecture

This uses **composition** - the animation logic is completely separate from movement:
- `KnightAnimationController.gd` - Pure animation logic (no movement code)
- Your movement script - Pure movement logic (no animation code)
- They communicate through the CharacterBody2D properties (velocity, is_on_floor, etc.)

This keeps code clean, modular, and easy to modify!
