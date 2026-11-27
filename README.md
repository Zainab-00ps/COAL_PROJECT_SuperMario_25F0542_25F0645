# COAL_PROJECT_SuperMario_25F0542_25F0645

A 16-bit side-scrolling platform game written in x86 assembly (NASM, 8086 real mode) and run in DOSBox.
Everything is built by us: VGA mode 13h drawing, own keyboard and timer interrupt handlers, fixed-point physics,
enemies, blocks, score and HUD. No libraries, no engine, no code from other sources.

## 1. Team

| Name         | Roll number | Modules developed |

| Zainab Aslam | 25F-0542    | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12 |
| Javeria Abid | 25F-0645    | 11, 13, 14, 15 |

Section: BCS 3F(3rd semester) | Lab instructor: Sir Shahzad tanver

### Which part of `src/mario.asm` belongs to which module

| Module                       | Owner         | Procedures (and data) |

| 1 Skeleton and build         | Zainab Aslam  | constants (EQU), data layout, `start`, `mainloop`, `quit`, `InitData`, `ConvertBlock` |
| 2 Video mode and colours     | Zainab Aslam  | `InitVideo`, `RestoreText`, `PutPixel`, `FillRect`, `DrawRects` |
| 3 Level map and tiles        | Zainab Aslam  | `TileIndex`, `GetTile`, `Solid`, `DrawTile`, `DrawMap`, `ResetMap`, `origmap`, `workmap`, tile tables |
| 4 Sprites                    | Zainab Aslam  | `DrawSprite`, all `spr_...` art |
| 5 Frame buffer               | Zainab Aslam  | `ClearBuffer`, `FlipBuffer` |
| 6 Camera and scrolling       |Zainab Aslam   | `UpdateCamera` |
| 7 Keyboard interrupt         |Zainab Aslam   | `kbisr`, `HookKeyboard`, `UnhookKeyboard`, key table |
| 8 Timer and clock            |Zainab Aslam   | `timerisr`, `HookTimer`, `UnhookTimer`, `WaitTick`, `UpdateClock` |
| 9 Movement and physics       |Zainab Aslam   | `UpdateMario` (8.8 fixed point) |
| 10 Collision detection       | Zainab Aslam  | `CheckSide`, `CheckHoriz`, `MoveMarioX`, `MoveMarioY`, `RectOverlap`, `CheckEntity` |
| 11 Enemies and shells        | Javeria Abid  | `EntWalk`, `EntFall`, `HitOther`, `UpdateEnemy`, `UpdateEnemies`, `DrawEnemies`, `CheckEnemies`, `ChainScore`, enemy table |
| 12 Blocks, coins, power-ups  | Javeria Abid  | `HitBlock`, `UpdateMushroom`, `MakeSuper`, `CollectCoins`, `TouchRow`, `TouchPoint` |
| 13 Score, health, lives, HUD | Javeria Abid  | `AddScore`, `AddCoin`, `AddLife`, `HurtMario`, `PrintStr`, `PrintTable`, `PrintNumber`, `DrawHUD`, `DrawHUDText` |
| 14 States, screens, menus    | Javeria Abid  | `StateTitle`, `StatePlaying`, `StatePaused`, `StateLifeLost`, `StateComplete`, `StateGameOver`, `DrawWorld`, `DrawMario`, text tables |
| 15 Win, lose, restart, exit  | Javeria Abid  | `KillMario`, `StateDying`, `StateWin`, `StartWin`, `ResetLevel`, `NewGame` |


## 3. Controls

| Key                | Action |
| Left / Right arrow | Move left / right |
| Left Shift         | Run |
| Space              | Jump (hold for a higher jump, no double jump) |
| P                  | Pause / resume |
| Up / Down arrow    | Move the menu highlight |
| Enter              | Select in menus, continue on end screens |
| Esc                | Back to title (from game) / exit (from title) |


## 4. Game states (in words)

- **TITLE**: Up/Down moves the highlight, Enter on START begins a new game, Enter on EXIT or Esc leaves the game.
- **PLAYING**: the game runs; P pauses, Esc returns to the title; death goes to DYING, touching the flag goes to the win sequence.
- **PAUSED**: everything frozen with "PAUSED" on the picture; P resumes, Esc returns to the title.
- **DYING**: about 1.5 s death animation (hop and fall), then one life is removed.
- **LIFE LOST**: screen with the world name and lives left for about 2 s, then the level restarts (score and coins are kept).
- **WIN SEQUENCE**: flag points are added, Mario slides down the pole and walks off the screen, then the time bonus (seconds x 50) is added.
- **LEVEL COMPLETE**: shows score, coins and time left; Enter returns to the title.
- **GAME OVER**: shown when the last life is lost, with the final score; Enter returns to the title.
- **EXIT**: restores the keyboard and timer vectors and the timer rate, returns to text mode and to DOS.

The game state is a variable and the main loop calls the handler through a jump table.

**Debug keys:** none.

## 5. How the main requirements are met

- Keyboard: own INT 9 handler with a key-state table, so Left, Right, Shift and Space work together.
- Timer: own INT 8 handler; the timer chip is set to 30 Hz, the game waits for the tick counter, and the game clock (300 s) counts 30 ticks per second.
- Physics: 8.8 fixed point for speeds; gravity, friction, run, variable jump height; one axis at a time collision.
- Score: 32-bit with `add`/`adc`, shown as decimal digits by repeated division by 10.
- Procedures take parameters through the stack, save and restore the registers they use, and every procedure has a comment block.

## 6. Deviations from the manual

1. **Position format:** the level is 960 pixels wide, which does not fit in the high byte of an 8.8 word.
   Position is a whole-pixel word plus a fraction byte; speeds are true 8.8 values.
2. **Timer:** the timer chip is reprogrammed to 30 Hz. 3 of every 5 ticks are passed on to the original BIOS
   handler so the DOS clock stays correct. The original rate is restored on exit.
3. **Physics values:** walk and run speeds and acceleration are tuned for better feel (walk 2.5, run 4.5
   pixels/frame). The required checks (3-tile pipe, 3-tile pit, "?" block from the ground, four stair steps) still pass.
4. **Stomp test:** Mario is falling and his feet are in the upper part of the enemy (about 12 pixels), instead of comparing against the previous frame.
5. **Far jumps:** conditional jumps that were out of short-jump range are written as an opposite condition plus `jmp`.
6. **HUD text:** letters and numbers are drawn with BIOS text output (INT 10h, service 13h) right after the buffer is copied to the screen.
7. **End of level:** Mario slides down the pole and walks off the right edge (no castle graphic).
8. Not implemented: coin pop-up animation, brick bump for Small Mario.

## 7. Bonus features

- Simple walking animation: Mario's run pose alternates while moving, enemies flip as they walk.

## 8. Known limitations

- One level only (World 1-1).
- Only one mushroom can be active at a time.
- Enemies fall at a constant speed.
- HUD text is drawn after the screen copy, so it may flicker slightly on slow settings.
- Tested in DOSBox with `cycles=max`; on the default cycle setting the game runs too slowly.
