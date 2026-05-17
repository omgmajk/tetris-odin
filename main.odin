package main

import "core:fmt"
import "core:math/rand"
import "vendor:raylib"

WINDOW_WIDTH  :: 800
WINDOW_HEIGHT :: 600

import "core:time"

main :: proc() {
    rand.reset(u64(time.to_unix_nanoseconds(time.now())))

    raylib.SetConfigFlags({.WINDOW_RESIZABLE})
    raylib.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Odin Tetris")
    defer raylib.CloseWindow()

    gs: GameState
    init_game(&gs)

    raylib.SetTargetFPS(60)

    for !raylib.WindowShouldClose() {
        if raylib.IsKeyPressed(.Q) do break
        if raylib.IsKeyPressed(.P) {
            gs.paused = !gs.paused
        }
        if raylib.IsKeyPressed(.R) && !gs.entering_name {
            init_game(&gs)
        }

        dt := raylib.GetFrameTime()

        if !gs.game_over && !gs.paused {
            // Input
            moved := false

            // Rotation
            if raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
                new_rotation := (gs.current_piece.rotation + 1) % 4
                if !check_collision(&gs, gs.current_piece.pos, new_rotation) {
                    gs.current_piece.rotation = new_rotation
                    moved = true
                }
            }

            // Stash
            if raylib.IsKeyPressed(.C) {
                stash_piece(&gs)
                moved = true
            }

            // Horizontal Movement with DAS
            left_pressed  := raylib.IsKeyPressed(.LEFT)  || raylib.IsKeyPressed(.A)
            right_pressed := raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressed(.D)
            left_down     := raylib.IsKeyDown(.LEFT)     || raylib.IsKeyDown(.A)
            right_down    := raylib.IsKeyDown(.RIGHT)    || raylib.IsKeyDown(.D)

            dir := 0
            if left_pressed do dir = -1
            else if right_pressed do dir = 1

            if dir != 0 {
                gs.das_dir = dir
                gs.das_timer = 0
                new_pos := gs.current_piece.pos + {dir, 0}
                if !check_collision(&gs, new_pos, gs.current_piece.rotation) {
                    gs.current_piece.pos = new_pos
                    moved = true
                }
            } else if gs.das_dir != 0 {
                is_dir_down := (gs.das_dir == -1 && left_down) || (gs.das_dir == 1 && right_down)
                if is_dir_down {
                    gs.das_timer += dt
                    if gs.das_timer >= DAS_DELAY {
                        new_pos := gs.current_piece.pos + {gs.das_dir, 0}
                        if !check_collision(&gs, new_pos, gs.current_piece.rotation) {
                            gs.current_piece.pos = new_pos
                            moved = true
                        }
                        gs.das_timer = DAS_DELAY - DAS_INTERVAL
                    }
                } else {
                    if left_down {
                        gs.das_dir = -1
                        gs.das_timer = 0
                    } else if right_down {
                        gs.das_dir = 1
                        gs.das_timer = 0
                    } else {
                        gs.das_dir = 0
                    }
                }
            }

            if moved && gs.is_locking {
                gs.lock_timer = 0
            }

            if raylib.IsKeyPressed(.SPACE) {
                for !check_collision(&gs, gs.current_piece.pos + {0, 1}, gs.current_piece.rotation) {
                    gs.current_piece.pos.y += 1
                }
                lock_piece(&gs)
            }

            speed_multiplier: f32 = 1.0
            if raylib.IsKeyDown(.DOWN) || raylib.IsKeyDown(.S) {
                speed_multiplier = 20.0
            }
            if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) {
                new_pos := gs.current_piece.pos + {0, 1}
                if !check_collision(&gs, new_pos, gs.current_piece.rotation) {
                    gs.current_piece.pos = new_pos
                    gs.fall_timer = 0
                    moved = true
                }
            }

            // Update
            gs.fall_timer += dt * speed_multiplier
            if gs.fall_timer >= gs.fall_speed {
                gs.fall_timer = 0
                new_pos := gs.current_piece.pos + {0, 1}
                if !check_collision(&gs, new_pos, gs.current_piece.rotation) {
                    gs.current_piece.pos = new_pos
                    if speed_multiplier > 1.0 {
                        moved = true
                    }
                } else {
                    gs.is_locking = true
                }
            }

            if gs.is_locking {
                gs.lock_timer += dt
                if gs.lock_timer >= LOCK_DELAY {
                    lock_piece(&gs)
                }

                if !check_collision(&gs, gs.current_piece.pos + {0, 1}, gs.current_piece.rotation) {
                    gs.is_locking = false
                    gs.lock_timer = 0
                }
            }
        } else {
            if gs.entering_name {
                key := raylib.GetCharPressed()
                for key > 0 {
                    if (key >= 32) && (key <= 125) && (gs.name_len < 31) {
                        gs.player_name[gs.name_len] = u8(key)
                        gs.name_len += 1
                    }
                    key = raylib.GetCharPressed()
                }

                if raylib.IsKeyPressed(.BACKSPACE) {
                    gs.name_len -= 1
                    if gs.name_len < 0 do gs.name_len = 0
                    gs.player_name[gs.name_len] = 0
                }

                if raylib.IsKeyPressed(.ENTER) {
                    name := string(gs.player_name[:gs.name_len])
                    add_high_score(&gs, name, gs.score)
                    gs.entering_name = false
                }
            } else {
                // Restart handled at top of loop
            }
        }

        // Draw
        raylib.BeginDrawing()
        raylib.ClearBackground(raylib.BLACK)

        screen_w := f32(raylib.GetScreenWidth())
        screen_h := f32(raylib.GetScreenHeight())
        field_pixel_w := f32(GRID_WIDTH * BLOCK_SIZE)
        field_pixel_h := f32(GRID_HEIGHT * BLOCK_SIZE)
        offset_x := (screen_w - field_pixel_w) / 2
        offset_y := (screen_h - field_pixel_h) / 2

        raylib.DrawRectangleV({offset_x, offset_y}, {field_pixel_w, field_pixel_h}, {20, 20, 20, 255})
        raylib.DrawRectangleLinesEx({offset_x - 2, offset_y - 2, field_pixel_w + 4, field_pixel_h + 4}, 2, raylib.DARKGRAY)

        for y in 0..<GRID_HEIGHT {
            for x in 0..<GRID_WIDTH {
                if gs.grid_filled[y][x] {
                    draw_block(x, y, gs.grid[y][x], offset_x, offset_y)
                }
            }
        }

        if !gs.game_over {
            // Ghost piece
            ghost_pos := get_ghost_pos(&gs)
            shape := TETROMINO_SHAPES[gs.current_piece.type][gs.current_piece.rotation]
            ghost_color := TETROMINO_COLORS[gs.current_piece.type]
            ghost_color.a = 50
            for p in shape {
                draw_block_with_color(ghost_pos.x + p.x, ghost_pos.y + p.y, ghost_color, offset_x, offset_y)
            }

            // Current piece
            color := TETROMINO_COLORS[gs.current_piece.type]
            if gs.is_locking {
                color.a = 150 + u8(50 * raylib.GetTime() * 10) % 105
            }
            for p in shape {
                draw_block_with_color(gs.current_piece.pos.x + p.x, gs.current_piece.pos.y + p.y, color, offset_x, offset_y)
            }
        }

        ui_offset_x := offset_x + field_pixel_w + 20
        raylib.DrawText("NEXT:", i32(ui_offset_x), i32(offset_y), 20, raylib.WHITE)
        draw_preview(gs.next_piece_type, ui_offset_x, offset_y + 30)

        raylib.DrawText("STASH:", i32(ui_offset_x), i32(offset_y + 150), 20, raylib.WHITE)
        if stashed, ok := gs.stashed_piece_type.?; ok {
            draw_preview(stashed, ui_offset_x, offset_y + 180)
        }

        raylib.DrawText(fmt.ctprintf("SCORE: %d", gs.score), i32(ui_offset_x), i32(offset_y + 300), 20, raylib.WHITE)

        // Control Legend
        legend_y := offset_y + 350
        raylib.DrawText("CONTROLS:", i32(ui_offset_x), i32(legend_y), 20, raylib.YELLOW)
        raylib.DrawText("Arrows/WASD: Move", i32(ui_offset_x), i32(legend_y + 30), 18, raylib.WHITE)
        raylib.DrawText("Up/W: Rotate", i32(ui_offset_x), i32(legend_y + 55), 18, raylib.WHITE)
        raylib.DrawText("Space: Hard Drop", i32(ui_offset_x), i32(legend_y + 80), 18, raylib.WHITE)
        raylib.DrawText("C: Stash Piece", i32(ui_offset_x), i32(legend_y + 105), 18, raylib.WHITE)
        raylib.DrawText("P: Pause Game", i32(ui_offset_x), i32(legend_y + 130), 18, raylib.WHITE)
        raylib.DrawText("R: Restart Game", i32(ui_offset_x), i32(legend_y + 155), 18, raylib.WHITE)

        // High scores on the side
        raylib.DrawText("TOP 10:", i32(offset_x - 200), i32(offset_y), 20, raylib.YELLOW)
        for i in 0..<10 {
            if gs.high_scores[i].score > 0 {
                score_str := fmt.ctprintf("%d. %s: %d", i + 1, gs.high_scores[i].name, gs.high_scores[i].score)
                raylib.DrawText(score_str, i32(offset_x - 200), i32(offset_y + 30 + f32(i * 25)), 18, raylib.WHITE)
            }
        }

        raylib.DrawText("Q: Quit", i32(ui_offset_x), i32(offset_y + field_pixel_h - 20), 20, raylib.GRAY)

        if gs.game_over {
            raylib.DrawRectangle(0, 0, i32(screen_w), i32(screen_h), {0, 0, 0, 200})
            if gs.entering_name {
                raylib.DrawText("NEW HIGH SCORE!", i32(screen_w/2 - 150), i32(screen_h/2 - 100), 30, raylib.YELLOW)
                raylib.DrawText("Enter your name:", i32(screen_w/2 - 120), i32(screen_h/2 - 40), 20, raylib.WHITE)

                name_str := fmt.ctprintf("%s_", gs.player_name[:gs.name_len])
                raylib.DrawText(name_str, i32(screen_w/2 - 100), i32(screen_h/2), 30, raylib.SKYBLUE)

                raylib.DrawText("Press ENTER to save", i32(screen_w/2 - 100), i32(screen_h/2 + 60), 18, raylib.GRAY)
            } else {
                raylib.DrawText("GAME OVER", i32(screen_w/2 - 100), i32(screen_h/2 - 100), 40, raylib.RED)
                raylib.DrawText(fmt.ctprintf("Final Score: %d", gs.score), i32(screen_w/2 - 80), i32(screen_h/2 - 40), 20, raylib.WHITE)

                raylib.DrawText("LEADERBOARD", i32(screen_w/2 - 70), i32(screen_h/2), 20, raylib.YELLOW)
                for i in 0..<10 {
                    if gs.high_scores[i].score > 0 {
                        score_str := fmt.ctprintf("%d. %s - %d", i + 1, gs.high_scores[i].name, gs.high_scores[i].score)
                        raylib.DrawText(score_str, i32(screen_w/2 - 80), i32(screen_h/2 + 30 + f32(i * 20)), 18, raylib.WHITE)
                    }
                }

                raylib.DrawText("Press R to restart", i32(screen_w/2 - 80), i32(screen_h/2 + 250), 20, raylib.WHITE)
            }
        } else if gs.paused {
            raylib.DrawRectangle(0, 0, i32(screen_w), i32(screen_h), {0, 0, 0, 150})
            raylib.DrawText("PAUSED", i32(screen_w/2 - 60), i32(screen_h/2 - 20), 40, raylib.WHITE)
            raylib.DrawText("Press P to resume", i32(screen_w/2 - 80), i32(screen_h/2 + 30), 20, raylib.GRAY)
        }

        raylib.EndDrawing()
    }
}

draw_block :: proc(x, y: int, type: TetrominoType, offset_x, offset_y: f32) {
    draw_block_with_color(x, y, TETROMINO_COLORS[type], offset_x, offset_y)
}

draw_block_with_color :: proc(x, y: int, color: Color, offset_x, offset_y: f32) {
    if y < 0 do return
    rect := raylib.Rectangle{
        offset_x + f32(x * BLOCK_SIZE),
        offset_y + f32(y * BLOCK_SIZE),
        f32(BLOCK_SIZE),
        f32(BLOCK_SIZE),
    }
    raylib.DrawRectangleRec(rect, color)
    raylib.DrawRectangleLinesEx(rect, 1, raylib.BLACK)
}

draw_preview :: proc(type: TetrominoType, x, y: f32) {
    shape := TETROMINO_SHAPES[type][0]
    for p in shape {
        rect := raylib.Rectangle{
            x + f32(p.x * BLOCK_SIZE),
            y + f32(p.y * BLOCK_SIZE),
            f32(BLOCK_SIZE),
            f32(BLOCK_SIZE),
        }
        raylib.DrawRectangleRec(rect, TETROMINO_COLORS[type])
        raylib.DrawRectangleLinesEx(rect, 1, raylib.BLACK)
    }
}
