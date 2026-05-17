package main

import "vendor:raylib"
import "core:math/rand"
import "core:os"
import "core:strconv"
import "core:fmt"
import "core:strings"

GRID_WIDTH  :: 10
GRID_HEIGHT :: 20
BLOCK_SIZE  :: 30

Color :: raylib.Color

TetrominoType :: enum {
    I, O, T, S, Z, J, L,
}

Tetromino :: struct {
    type: TetrominoType,
    pos: [2]int,
    rotation: int, // 0-3
}

TETROMINO_SHAPES := [TetrominoType][4][4][2]int {
    .I = {
        {{0, 1}, {1, 1}, {2, 1}, {3, 1}}, // 0
        {{2, 0}, {2, 1}, {2, 2}, {2, 3}}, // 1
        {{0, 2}, {1, 2}, {2, 2}, {3, 2}}, // 2
        {{1, 0}, {1, 1}, {1, 2}, {1, 3}}, // 3
    },
    .O = {
        {{1, 0}, {2, 0}, {1, 1}, {2, 1}},
        {{1, 0}, {2, 0}, {1, 1}, {2, 1}},
        {{1, 0}, {2, 0}, {1, 1}, {2, 1}},
        {{1, 0}, {2, 0}, {1, 1}, {2, 1}},
    },
    .T = {
        {{1, 0}, {0, 1}, {1, 1}, {2, 1}},
        {{1, 0}, {1, 1}, {2, 1}, {1, 2}},
        {{0, 1}, {1, 1}, {2, 1}, {1, 2}},
        {{1, 0}, {0, 1}, {1, 1}, {1, 2}},
    },
    .S = {
        {{1, 0}, {2, 0}, {0, 1}, {1, 1}},
        {{1, 0}, {1, 1}, {2, 1}, {2, 2}},
        {{1, 1}, {2, 1}, {0, 2}, {1, 2}},
        {{0, 0}, {0, 1}, {1, 1}, {1, 2}},
    },
    .Z = {
        {{0, 0}, {1, 0}, {1, 1}, {2, 1}},
        {{2, 0}, {1, 1}, {2, 1}, {1, 2}},
        {{0, 1}, {1, 1}, {1, 2}, {2, 2}},
        {{1, 0}, {0, 1}, {1, 1}, {0, 2}},
    },
    .J = {
        {{0, 0}, {0, 1}, {1, 1}, {2, 1}},
        {{1, 0}, {2, 0}, {1, 1}, {1, 2}},
        {{0, 1}, {1, 1}, {2, 1}, {2, 2}},
        {{1, 0}, {1, 1}, {0, 2}, {1, 2}},
    },
    .L = {
        {{2, 0}, {0, 1}, {1, 1}, {2, 1}},
        {{1, 0}, {1, 1}, {1, 2}, {2, 2}},
        {{0, 1}, {1, 1}, {2, 1}, {0, 2}},
        {{0, 0}, {1, 0}, {1, 1}, {1, 2}},
    },
}

TETROMINO_COLORS := [TetrominoType]Color {
    .I = raylib.SKYBLUE,
    .O = raylib.YELLOW,
    .T = raylib.PURPLE,
    .S = raylib.LIME,
    .Z = raylib.RED,
    .J = raylib.BLUE,
    .L = raylib.ORANGE,
}

HighScoreEntry :: struct {
    name: string,
    score: int,
}

LOCK_DELAY :: 0.5
DAS_DELAY  :: 0.2
DAS_INTERVAL :: 0.05

GameState :: struct {
    grid: [GRID_HEIGHT][GRID_WIDTH]TetrominoType,
    grid_filled: [GRID_HEIGHT][GRID_WIDTH]bool,
    current_piece: Tetromino,
    next_piece_type: TetrominoType,
    stashed_piece_type: Maybe(TetrominoType),
    can_stash: bool,
    game_over: bool,
    score: int,
    high_scores: [10]HighScoreEntry,
    fall_timer: f32,
    fall_speed: f32,
    lock_timer: f32,
    is_locking: bool,

    bag: [7]TetrominoType,
    bag_index: int,

    player_name: [32]u8,
    name_len: int,
    entering_name: bool,
    paused: bool,

    das_timer: f32,
    das_dir: int, // -1 for left, 1 for right, 0 for none
}

init_game :: proc(gs: ^GameState) {
    gs.grid = {}
    gs.grid_filled = {}

    refill_bag(gs)
    gs.current_piece = {
        type = get_next_piece_from_bag(gs),
        pos = {GRID_WIDTH / 2 - 2, 0},
        rotation = 0,
    }
    gs.next_piece_type = get_next_piece_from_bag(gs)

    gs.stashed_piece_type = nil
    gs.can_stash = true
    gs.game_over = false
    gs.score = 0
    gs.fall_timer = 0
    gs.fall_speed = 0.5
    gs.lock_timer = 0
    gs.is_locking = false
    gs.entering_name = false
    gs.paused = false
    gs.name_len = 0
    gs.player_name = {}
    gs.das_timer = 0
    gs.das_dir = 0

    load_high_scores(gs)
}

refill_bag :: proc(gs: ^GameState) {
    for i in 0..<7 {
        gs.bag[i] = TetrominoType(i)
    }
    for i in 0..<7 {
        j := rand.int_max(7)
        gs.bag[i], gs.bag[j] = gs.bag[j], gs.bag[i]
    }
    gs.bag_index = 0
}

get_next_piece_from_bag :: proc(gs: ^GameState) -> TetrominoType {
    if gs.bag_index >= 7 {
        refill_bag(gs)
    }
    type := gs.bag[gs.bag_index]
    gs.bag_index += 1
    return type
}

load_high_scores :: proc(gs: ^GameState) {
    data, ok := os.read_entire_file("highscores.txt")
    if ok {
        defer delete(data)
        content := string(data)
        lines_count := 0
        for line in strings.split_lines(content) {
            if lines_count >= 10 do break
            if line == "" do continue

            parts := strings.split(line, ":")
            if len(parts) == 2 {
                gs.high_scores[lines_count].name = strings.clone(parts[0])
                val, _ := strconv.parse_int(parts[1])
                gs.high_scores[lines_count].score = val
                lines_count += 1
            }
        }
    }
}

save_high_scores :: proc(gs: ^GameState) {
    builder: strings.Builder
    strings.builder_init(&builder)
    defer strings.builder_destroy(&builder)

    for i in 0..<10 {
        if gs.high_scores[i].score > 0 {
            fmt.sbprintf(&builder, "%s:%d\n", gs.high_scores[i].name, gs.high_scores[i].score)
        }
    }

    os.write_entire_file("highscores.txt", transmute([]u8)strings.to_string(builder))
}

add_high_score :: proc(gs: ^GameState, name: string, score: int) {
    insert_idx := -1
    for i in 0..<10 {
        if score > gs.high_scores[i].score {
            insert_idx = i
            break
        }
    }

    if insert_idx != -1 {
        for i := 9; i > insert_idx; i -= 1 {
            gs.high_scores[i] = gs.high_scores[i-1]
        }
        gs.high_scores[insert_idx] = {
            name = strings.clone(name),
            score = score,
        }
        save_high_scores(gs)
    }
}

spawn_piece :: proc(gs: ^GameState) {
    gs.current_piece = {
        type = gs.next_piece_type,
        pos = {GRID_WIDTH / 2 - 2, 0},
        rotation = 0,
    }
    gs.next_piece_type = get_next_piece_from_bag(gs)
    gs.can_stash = true
    gs.is_locking = false
    gs.lock_timer = 0

    if check_collision(gs, gs.current_piece.pos, gs.current_piece.rotation) {
        gs.game_over = true
        if gs.score > gs.high_scores[9].score {
            gs.entering_name = true
        }
    }
}

get_ghost_pos :: proc(gs: ^GameState) -> [2]int {
    ghost_pos := gs.current_piece.pos
    for !check_collision(gs, ghost_pos + {0, 1}, gs.current_piece.rotation) {
        ghost_pos.y += 1
    }
    return ghost_pos
}

check_collision :: proc(gs: ^GameState, pos: [2]int, rotation: int) -> bool {
    shape := TETROMINO_SHAPES[gs.current_piece.type][rotation]
    for p in shape {
        x := pos.x + p.x
        y := pos.y + p.y
        if x < 0 || x >= GRID_WIDTH || y >= GRID_HEIGHT {
            return true
        }
        if y >= 0 && gs.grid_filled[y][x] {
            return true
        }
    }
    return false
}

lock_piece :: proc(gs: ^GameState) {
    shape := TETROMINO_SHAPES[gs.current_piece.type][gs.current_piece.rotation]
    for p in shape {
        x := gs.current_piece.pos.x + p.x
        y := gs.current_piece.pos.y + p.y
        if y >= 0 && y < GRID_HEIGHT && x >= 0 && x < GRID_WIDTH {
            gs.grid_filled[y][x] = true
            gs.grid[y][x] = gs.current_piece.type
        }
    }
    clear_lines(gs)
    spawn_piece(gs)
}

clear_lines :: proc(gs: ^GameState) {
    lines_cleared := 0
    for y := GRID_HEIGHT - 1; y >= 0; y -= 1 {
        full := true
        for x := 0; x < GRID_WIDTH; x += 1 {
            if !gs.grid_filled[y][x] {
                full = false
                break
            }
        }
        if full {
            lines_cleared += 1
            for yy := y; yy > 0; yy -= 1 {
                gs.grid_filled[yy] = gs.grid_filled[yy - 1]
                gs.grid[yy] = gs.grid[yy - 1]
            }
            gs.grid_filled[0] = {}
            gs.grid[0] = {}
            y += 1
        }
    }

    switch lines_cleared {
    case 1: gs.score += 100
    case 2: gs.score += 300
    case 3: gs.score += 500
    case 4: gs.score += 800
    }

    // Dynamic fall speed: starts at 0.5, decreases by 0.05 every 1000 points, min 0.1
    gs.fall_speed = 0.5 - f32(gs.score / 1000) * 0.05
    if gs.fall_speed < 0.1 {
        gs.fall_speed = 0.1
    }
}

stash_piece :: proc(gs: ^GameState) {
    if !gs.can_stash do return

    if stashed, ok := gs.stashed_piece_type.?; ok {
        temp := gs.current_piece.type
        gs.current_piece.type = stashed
        gs.stashed_piece_type = temp
    } else {
        gs.stashed_piece_type = gs.current_piece.type
        spawn_piece(gs)
    }

    gs.current_piece.pos = {GRID_WIDTH / 2 - 2, 0}
    gs.current_piece.rotation = 0
    gs.can_stash = false
}
