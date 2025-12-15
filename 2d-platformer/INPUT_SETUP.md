# Input Map Setup Guide

This guide explains how to configure the required input actions in Godot for the enhanced knight animation system.

## Required Input Actions

Go to **Project > Project Settings > Input Map** in Godot and add the following actions:

### Movement Controls (Required)
- **left** - Move left (default: A or Left Arrow)
- **right** - Move right (default: D or Right Arrow)
- **up** - Move up/climb (default: W or Up Arrow)
- **down** - Move down/crouch (default: S or Down Arrow)
- **jump** - Jump (default: Space)
- **run** - Sprint/Run faster (default: Left Shift)

### Advanced Movement (Optional - already supported by controller)
- **dash** - Dash movement (default: Left Ctrl)
- **roll** - Roll dodge (default: Q)
- **latch** - Wall latch (default: E)
- **twirl** - Twirl action (default: R)

### Combat Controls (New - Required for Combat System)
- **attack** - Basic attack (default: Left Mouse Button or J)
- **heavy_attack** - Heavy/charged attack (default: Right Mouse Button or K)
- **block** - Block/parry (default: Middle Mouse Button or L)

## Quick Setup in Godot

1. Open your project in Godot
2. Go to **Project > Project Settings**
3. Click on the **Input Map** tab
4. For each action above:
   - Type the action name in the text field at the top
   - Click **Add**
   - Click the **+** button next to the action
   - Press the key/button you want to assign
   - Click **OK**

## Default Control Scheme

### Keyboard Layout
```
Movement:
  W/↑     - Up/Climb
A/←   D/→ - Left/Right
  S/↓     - Down/Crouch

Actions:
Space     - Jump
Shift     - Run
Ctrl      - Dash
Q         - Roll
E         - Wall Latch

Combat:
J         - Attack
K         - Heavy Attack
L         - Block
```

### Mouse + Keyboard Layout (Recommended)
```
Movement: WASD or Arrow Keys
Jump: Space
Run: Shift
Dash: Ctrl
Roll: Q

Combat:
Left Click    - Attack
Right Click   - Heavy Attack
Middle Click  - Block
```

## Testing Your Setup

Once configured, you can test:
1. Run the game
2. Move around with WASD/Arrows - should play walk/run animations
3. Press Space to jump - should play jump animations
4. Press attack key - should play attack animations
5. Hold block key - should play blocking animations
6. Try attacking multiple times quickly - should trigger combo animations

## Animation System Features

The enhanced animation system automatically handles:
- ✓ Basic movement (idle, walk, run)
- ✓ Jumping and falling
- ✓ Wall sliding and jumping
- ✓ Crouching and rolling
- ✓ Attack combos (4-hit combo)
- ✓ Heavy attacks
- ✓ Air attacks
- ✓ Blocking and parrying
- ✓ Hit reactions
- ✓ Dash attacks

All 70 knight animations are integrated and will play at the appropriate times!
