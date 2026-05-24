package main

import "core:fmt"
import "core:math/rand"
import "vendor:raylib"
import "core:time"

WINDOW_WIDTH  :: 800
WINDOW_HEIGHT :: 600

block_size :: proc() -> f32 {
    h := f32(raylib.GetScreenHeight())
    bs := (h - 40) / GRID_HEIGHT
    if bs < 10 do bs = 10
    if bs > 50 do bs = 50

    return bs
}

main :: proc() {

    rand.reset(u64(time.to_unix_nanoseconds(time.now())))

    // Init window
    raylib.SetConfigFlags({.WINDOW_RESIZABLE})
    raylib.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Odin Tetris")

    defer raylib.CloseWindow()

    // Init audio
    raylib.InitAudioDevice()
    defer raylib.CloseAudioDevice()

    // Init game state struct
    gs: GameState
    load_audio(&gs.audio)
    defer unload_audio(&gs.audio)
    init_game(&gs)

    raylib.SetTargetFPS(60)

    // Main loop
    for !raylib.WindowShouldClose() {

        if raylib.IsKeyPressed(.Q) do break

        dt := raylib.GetFrameTime()
        handle_input(&gs, dt)

        update(&gs, dt)

        raylib.BeginDrawing()
        raylib.ClearBackground(raylib.BLACK)
        draw(&gs)
        raylib.EndDrawing()
    }
}

handle_input :: proc(gs: ^GameState, dt: f32) {

    if raylib.IsKeyPressed(.P) {
        switch gs.mode {
        case .Playing:  gs.mode = .Paused
        case .Paused:   gs.mode = .Playing
        case .GameOver, .EnteringName: // Game state reset elsewhere, no input handling, empty case
        }
    }

    if raylib.IsKeyPressed(.R) && gs.mode != .EnteringName {
        init_game(gs)
        return
    }

    switch gs.mode {
    case .Playing:
        handle_playing_input(gs, dt)
    case .EnteringName:
        handle_name_input(gs)
    case .Paused, .GameOver:
        // No specific input processing needed here as global keys handled it.
    }
}

handle_playing_input :: proc(gs: ^GameState, dt: f32) {

    moved := false
    last_action_was_rotation := false

    if raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
        from := gs.current_piece.rotation
        new_r := (from + 1) % 4
        if try_rotate(gs, from, new_r) {
            play_sound(&gs.audio, gs.audio.rotate)
            moved = true
            last_action_was_rotation = true
        }
    }

    if raylib.IsKeyPressed(.C) {
        stash_piece(gs)
        moved = true
    }

    left_pressed  := raylib.IsKeyPressed(.LEFT)  || raylib.IsKeyPressed(.A)
    right_pressed := raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressed(.D)
    left_down     := raylib.IsKeyDown(.LEFT)     || raylib.IsKeyDown(.A)
    right_down    := raylib.IsKeyDown(.RIGHT)    || raylib.IsKeyDown(.D)

    dir := 0
    if left_pressed       do dir = -1
    else if right_pressed do dir =  1


     // INITIAL PRESS HANDLING:
     // If a key was just pressed, we move immediately and reset the DAS timer.

    if dir != 0 {
        gs.das_dir   = dir
        gs.das_timer = 0
        new_pos := gs.current_piece.pos + {dir, 0}

        if !check_collision(gs, gs.current_piece.type, new_pos, gs.current_piece.rotation) {
            gs.current_piece.pos = new_pos
            play_sound(&gs.audio, gs.audio.move)
            moved = true
        }
    } else if gs.das_dir != 0 {

         // HELD KEY HANDLING:
         // If the direction we are DAS-ing in is still held down, increment timer.

        is_dir_down := (gs.das_dir == -1 && left_down) || (gs.das_dir == 1 && right_down)
        if is_dir_down {
            gs.das_timer += dt
            if gs.das_timer >= DAS_DELAY {
                new_pos := gs.current_piece.pos + {gs.das_dir, 0}
                if !check_collision(gs, gs.current_piece.type, new_pos, gs.current_piece.rotation) {
                    gs.current_piece.pos = new_pos
                    play_sound(&gs.audio, gs.audio.move)
                    moved = true
                }
                // Subtract interval to allow for smooth repeat movement.
                gs.das_timer = DAS_DELAY - DAS_INTERVAL
            }
        } else {
            if      left_down  do gs.das_dir = -1
            else if right_down do gs.das_dir =  1
            else               do gs.das_dir =  0
            gs.das_timer = 0
        }
    }

    // Reset lock time if piece is moved when in lock state
    if moved && gs.is_locking && gs.lock_move_count < LOCK_MOVE_MAX {
        gs.lock_timer = 0
        gs.lock_move_count += 1
    }

    // Hard drop
    if raylib.IsKeyPressed(.SPACE) {
        for !check_collision(gs, gs.current_piece.type, gs.current_piece.pos + {0, 1}, gs.current_piece.rotation) {
            gs.current_piece.pos.y += 1
        }
        lock_piece(gs, last_action_was_rotation)
        return
    }

    // Soft drop
    if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) {
        new_pos := gs.current_piece.pos + {0, 1}
        if !check_collision(gs, gs.current_piece.type, new_pos, gs.current_piece.rotation) {
            gs.current_piece.pos = new_pos
            gs.fall_timer = 0 // Reset gravity timer to prevent double-drops.
        }
    }

    gs._last_action_was_rotation = last_action_was_rotation
}

handle_name_input :: proc(gs: ^GameState) {

    key := raylib.GetCharPressed()
    for key > 0 {
        // Only accept printable ASCII characters (32-125) and limit name length to 31. Do not accept a space (32).
        if key >= 33 && key <= 125 && gs.name_len < 31 {
            gs.player_name[gs.name_len] = u8(key)
            gs.name_len += 1
        }
        key = raylib.GetCharPressed() // Drain the buffer
    }

    if raylib.IsKeyPressed(.BACKSPACE) && gs.name_len > 0 {
        gs.name_len -= 1
        gs.player_name[gs.name_len] = 0 // Null-terminate string before handing over to RayLib
    }

    if raylib.IsKeyPressed(.ENTER) {
        name := string(gs.player_name[:gs.name_len])
        add_high_score(gs, name, gs.score)
        gs.mode = .GameOver
    }
}

update :: proc(gs: ^GameState, dt: f32) {
    if gs.mode != .Playing do return

    // Speed increase on key down
    speed_multiplier: f32 = 1.0
    if raylib.IsKeyDown(.DOWN) || raylib.IsKeyDown(.S) {
        speed_multiplier = 20.0
    }

    // Fall logic
    gs.fall_timer += dt * speed_multiplier
    if gs.fall_timer >= gs.fall_speed {
        gs.fall_timer = 0
        new_pos := gs.current_piece.pos + {0, 1}
        if !check_collision(gs, gs.current_piece.type, new_pos, gs.current_piece.rotation) {
            gs.current_piece.pos = new_pos
        } else {
            gs.is_locking = true
        }
    }

    // Locking mechanic
    if gs.is_locking {
        gs.lock_timer += dt
        if gs.lock_timer >= LOCK_DELAY || gs.lock_move_count >= LOCK_MOVE_MAX {
            lock_piece(gs, gs._last_action_was_rotation)
            gs._last_action_was_rotation = false
            return
        }
        // Cancel lock
        if !check_collision(gs, gs.current_piece.type, gs.current_piece.pos + {0, 1}, gs.current_piece.rotation) {
            gs.is_locking      = false
            gs.lock_timer      = 0
            gs.lock_move_count = 0
        }
    }
}

draw :: proc(gs: ^GameState) {
    bs := block_size()

    // Layout constants: find the center of the screen for the main grid.
    screen_w := f32(raylib.GetScreenWidth())
    screen_h := f32(raylib.GetScreenHeight())
    field_w  := f32(GRID_WIDTH)  * bs
    field_h  := f32(GRID_HEIGHT) * bs
    ox       := (screen_w - field_w) / 2 // Horizontal Offset
    oy       := (screen_h - field_h) / 2 // Vertical Offset

    raylib.DrawRectangleV({ox, oy}, {field_w, field_h}, {20, 20, 20, 255})
    raylib.DrawRectangleLinesEx({ox - 2, oy - 2, field_w + 4, field_h + 4}, 2, raylib.DARKGRAY)

    // Iterate through grid array
    for y in 0..<GRID_HEIGHT {
        for x in 0..<GRID_WIDTH {
            if t, ok := gs.grid[y][x].?; ok {
                draw_block(x, y, t, ox, oy, bs)
            }
        }
    }

    if gs.mode == .Playing || gs.mode == .Paused {

        // Ghost piece to show where a piece will fall
        ghost_pos := get_ghost_pos(gs)
        shape     := TETROMINO_SHAPES[gs.current_piece.type][gs.current_piece.rotation]

        ghost_color := TETROMINO_COLORS[gs.current_piece.type]
        ghost_color.a = 50 // Alpha channel color, transparancy
        for p in shape {
            draw_block_color(ghost_pos.x + p.x, ghost_pos.y + p.y, ghost_color, ox, oy, bs)
        }

        color := TETROMINO_COLORS[gs.current_piece.type]
        if gs.is_locking {
            // Pulse the alpha channel using a sine-wave like calculation based on time.
            color.a = 150 + u8(u32(raylib.GetTime() * 10) % 105)
        }
        for p in shape {
            draw_block_color(gs.current_piece.pos.x + p.x, gs.current_piece.pos.y + p.y, color, ox, oy, bs)
        }
    }

    ui_x := ox + field_w + 20
    draw_right_panel(gs, ui_x, oy, bs)

    left_x := ox - 210
    if left_x > 0 {
        draw_left_panel(gs, left_x, oy)
    }

    raylib.DrawText("Q: Quit", i32(ui_x), i32(oy + field_h - 20), 20, raylib.GRAY)

    switch gs.mode {
    case .Paused:
        draw_overlay_paused(screen_w, screen_h)
    case .GameOver:
        draw_overlay_gameover(gs, screen_w, screen_h)
    case .EnteringName:
        draw_overlay_name(gs, screen_w, screen_h)
    case .Playing:
        // No overlay while playing.
    }
}

get_level_color :: proc(level: int) -> raylib.Color {
    // Determine how aggressively the color shifts per level.
    // 15 means it will reach pure red by level 17 (255 / 15 = 17).
    loss_amount := level * 15

    // Calculate the remaining green/blue value, ensuring it doesn't underflow.
    if loss_amount > 255 do loss_amount = 255
    gb_value := u8(255 - loss_amount)

    return raylib.Color{255, gb_value, gb_value, 255}
}

draw_right_panel :: proc(gs: ^GameState, ui_x, oy, bs: f32) {
    // We cap the preview block size so it doesn't get too massive on large screens.
    preview_bs := min(bs, f32(BASE_BLOCK_SIZE))

    // Next piece preview
    raylib.DrawText("NEXT:", i32(ui_x), i32(oy), 20, raylib.WHITE)
    draw_preview(gs.next_piece_type, ui_x, oy + 30, preview_bs)

    // Stashed piece preview
    raylib.DrawText("HOLD:", i32(ui_x), i32(oy + 150), 20, raylib.WHITE)
    if stashed, ok := gs.stashed_piece_type.?; ok {
        col := TETROMINO_COLORS[stashed]
        // If the player has already used the 'hold' function for this piece,
        // we dim it to indicate it's unavailable.
        if !gs.can_stash do col.a = 100
        draw_preview_color(stashed, ui_x, oy + 180, preview_bs, col)
    }

    // Gameplay Statistics
    raylib.DrawText(fmt.ctprintf("SCORE: %d", gs.score),  i32(ui_x), i32(oy + 310), 20, raylib.WHITE)
    raylib.DrawText(fmt.ctprintf("LEVEL: %d", gs.level),  i32(ui_x), i32(oy + 340), 20, get_level_color(gs.level))
    raylib.DrawText(fmt.ctprintf("LINES: %d", gs.lines_total), i32(ui_x), i32(oy + 365), 18, raylib.GRAY)

    ly := oy + 410
    raylib.DrawText("CONTROLS:", i32(ui_x), i32(ly),       20, raylib.YELLOW)
    raylib.DrawText("L/R/A/D: Move",   i32(ui_x), i32(ly + 28),  18, raylib.WHITE)
    raylib.DrawText("U/W: Rotate",   i32(ui_x), i32(ly + 52),  18, raylib.WHITE)
    raylib.DrawText("D/S: Soft Drop",i32(ui_x), i32(ly + 76),  18, raylib.WHITE)
    raylib.DrawText("Space: Hard Drop",i32(ui_x),i32(ly + 100), 18, raylib.WHITE)
    raylib.DrawText("C: Hold Piece", i32(ui_x), i32(ly + 124), 18, raylib.WHITE)
    raylib.DrawText("P: Pause",      i32(ui_x), i32(ly + 148), 18, raylib.WHITE)
    raylib.DrawText("R: Restart",    i32(ui_x), i32(ly + 172), 18, raylib.WHITE)
}

draw_left_panel :: proc(gs: ^GameState, left_x, oy: f32) {
    raylib.DrawText("TOP 10:", i32(left_x), i32(oy), 20, raylib.YELLOW)
    for i in 0..<10 {
        if gs.high_scores[i].score > 0 {
            s := fmt.ctprintf("%d. %s: %d", i + 1, gs.high_scores[i].name, gs.high_scores[i].score)
            raylib.DrawText(s, i32(left_x), i32(oy + 30 + f32(i * 25)), 18, raylib.WHITE)
        }
    }
}

draw_overlay_paused :: proc(sw, sh: f32) {
    raylib.DrawRectangle(0, 0, i32(sw), i32(sh), {0, 0, 0, 150})
    raylib.DrawText("PAUSED", i32(sw/2 - 60), i32(sh/2 - 20), 40, raylib.WHITE)
    raylib.DrawText("P to resume / R to restart", i32(sw/2 - 120), i32(sh/2 + 30), 20, raylib.GRAY)
}

draw_overlay_gameover :: proc(gs: ^GameState, sw, sh: f32) {
    raylib.DrawRectangle(0, 0, i32(sw), i32(sh), {0, 0, 0, 200})
    raylib.DrawText("GAME OVER", i32(sw/2 - 100), i32(sh/2 - 140), 40, raylib.RED)
    raylib.DrawText(fmt.ctprintf("Score: %d  Level: %d", gs.score, gs.level),
        i32(sw/2 - 100), i32(sh/2 - 80), 20, raylib.WHITE)

    raylib.DrawText("LEADERBOARD", i32(sw/2 - 80), i32(sh/2 - 40), 20, raylib.YELLOW)
    for i in 0..<10 {
        if gs.high_scores[i].score > 0 {
            s := fmt.ctprintf("%d. %s - %d", i + 1, gs.high_scores[i].name, gs.high_scores[i].score)
            raylib.DrawText(s, i32(sw/2 - 90), i32(sh/2 - 10 + f32(i * 22)), 18, raylib.WHITE)
        }
    }
    raylib.DrawText("R to restart", i32(sw/2 - 60), i32(sh/2 + 230), 20, raylib.WHITE)
}

draw_overlay_name :: proc(gs: ^GameState, sw, sh: f32) {
    raylib.DrawRectangle(0, 0, i32(sw), i32(sh), {0, 0, 0, 200})
    raylib.DrawText("NEW HIGH SCORE!", i32(sw/2 - 150), i32(sh/2 - 100), 30, raylib.YELLOW)
    raylib.DrawText("Enter your name:", i32(sw/2 - 120), i32(sh/2 - 40), 20, raylib.WHITE)

    // Append an underscore to the end of the name to simulate a cursor.
    name_str := fmt.ctprintf("%s_", gs.player_name[:gs.name_len])
    raylib.DrawText(name_str, i32(sw/2 - 100), i32(sh/2), 30, raylib.SKYBLUE)
    raylib.DrawText("ENTER to save", i32(sw/2 - 80), i32(sh/2 + 60), 18, raylib.GRAY)
}

draw_block :: proc(x, y: int, type: TetrominoType, ox, oy, bs: f32) {
    draw_block_color(x, y, TETROMINO_COLORS[type], ox, oy, bs)
}

draw_block_color :: proc(x, y: int, color: Color, ox, oy, bs: f32) {
    // Blocks above the visible grid (in the buffer zone) are not drawn.
    if y < 0 do return

    rect := raylib.Rectangle{
        ox + f32(x) * bs,
        oy + f32(y) * bs,
        bs,
        bs,
    }

    raylib.DrawRectangleRec(rect, color)
    raylib.DrawRectangleLinesEx(rect, 1, raylib.BLACK)
}

draw_preview :: proc(type: TetrominoType, x, y, bs: f32) {
    draw_preview_color(type, x, y, bs, TETROMINO_COLORS[type])
}

draw_preview_color :: proc(type: TetrominoType, x, y, bs: f32, color: Color) {
    shape := TETROMINO_SHAPES[type][0]
    for p in shape {
        rect := raylib.Rectangle{
            x + f32(p.x) * bs,
            y + f32(p.y) * bs,
            bs,
            bs,
        }
        raylib.DrawRectangleRec(rect, color)
        raylib.DrawRectangleLinesEx(rect, 1, raylib.BLACK)
    }
}
