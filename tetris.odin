package main

import "vendor:raylib"
import "core:math/rand"
import "core:os"
import "core:strconv"
import "core:fmt"
import "core:strings"

GRID_WIDTH  :: 10
GRID_HEIGHT :: 20

BASE_BLOCK_SIZE :: 30

Color :: raylib.Color

GameMode :: enum {
    Playing,      // Normal gameplay active.
    Paused,       // Game logic halted, overlay shown.
    GameOver,     // Game ended, results shown.
    EnteringName, // Player achieved a high score and is typing their name.
}

TetrominoType :: enum {
    I, O, T, S, Z, J, L,
}

Tetromino :: struct {
    type:     TetrominoType,
    pos:      [2]int,
    rotation: int,
}

// Shapes and rotation in the 4x4 grid

TETROMINO_SHAPES := [TetrominoType][4][4][2]int{
    .I = {
        {{0, 1}, {1, 1}, {2, 1}, {3, 1}},
        {{2, 0}, {2, 1}, {2, 2}, {2, 3}},
        {{0, 2}, {1, 2}, {2, 2}, {3, 2}},
        {{1, 0}, {1, 1}, {1, 2}, {1, 3}},
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

TETROMINO_COLORS := [TetrominoType]Color{
    .I = raylib.SKYBLUE,
    .O = raylib.YELLOW,
    .T = raylib.PURPLE,
    .S = raylib.LIME,
    .Z = raylib.RED,
    .J = raylib.BLUE,
    .L = raylib.ORANGE,
}

// Kicks for J, L, S, T, Z pieces.
SRS_KICKS_JLSTZ := [4][5][2]int{
    {{0, 0}, {-1, 0}, {-1, -1}, {0, 2}, {-1, 2}},
    {{0, 0}, {1, 0}, {1, 1}, {0, -2}, {1, -2}},
    {{0, 0}, {1, 0}, {1, -1}, {0, 2}, {1, 2}},
    {{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}},
}

// Kicks for the I-piece, which has unique pivot rules due to its long shape.
SRS_KICKS_I := [4][5][2]int{
    {{0, 0}, {-2, 0}, {1, 0}, {-2, 1}, {1, -2}},
    {{0, 0}, {-1, 0}, {2, 0}, {-1, -2}, {2, 1}},
    {{0, 0}, {2, 0}, {-1, 0}, {2, -1}, {-1, 2}},
    {{0, 0}, {1, 0}, {-2, 0}, {1, 2}, {-2, -1}},
}

LOCK_DELAY    :: 0.5
LOCK_MOVE_MAX :: 15
DAS_DELAY     :: 0.2
DAS_INTERVAL  :: 0.05

LINE_SCORE := [5]int{0, 100, 300, 500, 800}

Audio :: struct {
    enabled:    bool,
    move:       raylib.Sound,
    rotate:     raylib.Sound,
    lock:       raylib.Sound,
    line_clear: raylib.Sound,
    tetris:     raylib.Sound,
    level_up:   raylib.Sound,
    game_over:  raylib.Sound,
}

load_audio :: proc(audio: ^Audio) {
    audio.move       = raylib.LoadSound("audio/move.wav")
    audio.rotate     = raylib.LoadSound("audio/rotate.wav")
    audio.lock       = raylib.LoadSound("audio/lock.wav")
    audio.line_clear = raylib.LoadSound("audio/line_clear.wav")
    audio.tetris     = raylib.LoadSound("audio/tetris.wav")
    audio.level_up   = raylib.LoadSound("audio/level_up.wav")
    audio.game_over  = raylib.LoadSound("audio/game_over.wav")
    audio.enabled    = true
}

unload_audio :: proc(audio: ^Audio) {
    if !audio.enabled do return
    if raylib.IsSoundValid(audio.move)       do raylib.UnloadSound(audio.move)
    if raylib.IsSoundValid(audio.rotate)     do raylib.UnloadSound(audio.rotate)
    if raylib.IsSoundValid(audio.lock)       do raylib.UnloadSound(audio.lock)
    if raylib.IsSoundValid(audio.line_clear) do raylib.UnloadSound(audio.line_clear)
    if raylib.IsSoundValid(audio.tetris)     do raylib.UnloadSound(audio.tetris)
    if raylib.IsSoundValid(audio.level_up)   do raylib.UnloadSound(audio.level_up)
    if raylib.IsSoundValid(audio.game_over)  do raylib.UnloadSound(audio.game_over)
}

play_sound :: proc(audio: ^Audio, sound: raylib.Sound) {
    if audio.enabled && raylib.IsSoundValid(sound) {
        raylib.PlaySound(sound)
    }
}

HighScoreEntry :: struct {
    name:  string,
    score: int,
}

// Game state struct
GameState :: struct {

    grid: [GRID_HEIGHT][GRID_WIDTH]Maybe(TetrominoType),

    current_piece:     Tetromino,
    next_piece_type:   TetrominoType,
    stashed_piece_type: Maybe(TetrominoType),
    can_stash:         bool, // Prevents multiple swaps within the same piece spawn.

    mode: GameMode,

    score: int,
    level: int,
    lines_total: int,

    high_scores: [10]HighScoreEntry,

    fall_timer: f32,
    fall_speed: f32, // Calculated based on current level.

    lock_timer:     f32,
    is_locking:     bool,
    lock_move_count: int,

    // Back-to-back bonus: True if the previous clear was a Tetris or T-Spin.
    last_clear_was_special: bool,

    // 7 bag system
    bag:       [7]TetrominoType,
    bag_index: int,

    player_name: [32]u8,
    name_len:    int,

    das_timer: f32,
    das_dir:   int,

    // Internal flag to track rotation for T-spin detection.
    _last_action_was_rotation: bool,

    audio: Audio,
}

init_game :: proc(gs: ^GameState) {
    // Clean up allocated strings from the previous session to avoid memory leaks.
    free_high_scores(gs)

    // Preserve the audio device handle during the reset.
    audio_backup := gs.audio

    // Odin's shortcut to zero-initialize the entire struct.
    gs^ = {}
    gs.audio = audio_backup

    // Initialize the first bag and spawn the first piece.
    refill_bag(gs)
    gs.current_piece = {
        type     = get_next_piece_from_bag(gs),
        pos      = {GRID_WIDTH / 2 - 2, 0},
        rotation = 0,
    }
    gs.next_piece_type = get_next_piece_from_bag(gs)
    gs.stashed_piece_type = nil
    gs.can_stash = true
    gs.mode = .Playing
    gs.score = 0
    gs.level = 1
    gs.lines_total = 0
    gs.fall_speed = fall_speed_for_level(1)
    gs.last_clear_was_special = false

    // Load leaderboard from disk.
    load_high_scores(gs)
}

free_high_scores :: proc(gs: ^GameState) {
    for i in 0..<10 {
        if gs.high_scores[i].name != "" {
            delete(gs.high_scores[i].name)
            gs.high_scores[i].name = ""
        }
    }
}

fall_speed_for_level :: proc(level: int) -> f32 {
    speed := f32(0.8) - f32(level - 1) * 0.010
    if speed < 0.05 do speed = 0.05 // Cap the max speed for playability.
    return speed
}

level_for_lines :: proc(lines: int) -> int {
    return lines / 10 + 1
}

// Implements the Fisher-Yates shuffle algorithm to generate a fair piece sequence.

refill_bag :: proc(gs: ^GameState) {
    // Fill the bag with one of each type.
    for i in 0..<7 {
        gs.bag[i] = TetrominoType(i)
    }
    // Shuffle.
    for i in 0..<7 {
        j := i + rand.int_max(7 - i)
        gs.bag[i], gs.bag[j] = gs.bag[j], gs.bag[i]
    }
    gs.bag_index = 0
}

get_next_piece_from_bag :: proc(gs: ^GameState) -> TetrominoType {
    if gs.bag_index >= 7 do refill_bag(gs)
    type := gs.bag[gs.bag_index]
    gs.bag_index += 1
    return type
}

check_collision :: proc(gs: ^GameState, piece_type: TetrominoType, pos: [2]int, rotation: int) -> bool {
    shape := TETROMINO_SHAPES[piece_type][rotation]
    for p in shape {
        x := pos.x + p.x
        y := pos.y + p.y
        // Wall and floor collisions.
        if x < 0 || x >= GRID_WIDTH || y >= GRID_HEIGHT do return true
        // Grid cell collisions.
        if y >= 0 {
            if _, filled := gs.grid[y][x].?; filled do return true
        }
    }
    return false
}

try_rotate :: proc(gs: ^GameState, from_rotation: int, new_rotation: int) -> bool {
    kicks: [5][2]int
    // Pick the correct kick table based on piece type.
    if gs.current_piece.type == .I {
        kicks = SRS_KICKS_I[from_rotation]
    } else {
        kicks = SRS_KICKS_JLSTZ[from_rotation]
    }

    // Iteratively test all 5 kick offsets defined by SRS.
    for kick in kicks {
        test_pos := gs.current_piece.pos + {kick.x, kick.y}
        if !check_collision(gs, gs.current_piece.type, test_pos, new_rotation) {
            // Found a valid position, apply and exit.
            gs.current_piece.pos      = test_pos
            gs.current_piece.rotation = new_rotation
            return true
        }
    }
    // All kicks failed, rotation is blocked.
    return false
}

get_ghost_pos :: proc(gs: ^GameState) -> [2]int {
    ghost := gs.current_piece.pos
    for !check_collision(gs, gs.current_piece.type, ghost + {0, 1}, gs.current_piece.rotation) {
        ghost.y += 1
    }
    return ghost
}
// Check for t-spin
is_tspin :: proc(gs: ^GameState, last_action_was_rotation: bool) -> bool {
    // Requirements: Must be a T-piece and must have just rotated.
    if gs.current_piece.type != .T        do return false
    if !last_action_was_rotation          do return false

    // Identify the four corner cells surrounding the T-piece's center.
    cx := gs.current_piece.pos.x + 1
    cy := gs.current_piece.pos.y + 1
    corners := [4][2]int{{cx-1, cy-1}, {cx+1, cy-1}, {cx-1, cy+1}, {cx+1, cy+1}}

    filled_corners := 0
    for c in corners {
        x, y := c.x, c.y
        // Bounds count as "filled" for T-spin logic.
        if x < 0 || x >= GRID_WIDTH || y < 0 || y >= GRID_HEIGHT {
            filled_corners += 1
            continue
        }
        // Check if the grid cell is occupied.
        if _, ok := gs.grid[y][x].?; ok {
            filled_corners += 1
        }
    }
    // Standard rule: At least 3 corners must be filled.
    return filled_corners >= 3
}

lock_piece :: proc(gs: ^GameState, last_action_was_rotation: bool) {
    shape := TETROMINO_SHAPES[gs.current_piece.type][gs.current_piece.rotation]
    for p in shape {
        x := gs.current_piece.pos.x + p.x
        y := gs.current_piece.pos.y + p.y
        if y >= 0 && y < GRID_HEIGHT && x >= 0 && x < GRID_WIDTH {
            // Bake the piece type into the grid.
            gs.grid[y][x] = gs.current_piece.type
        }
    }

    // Check if this placement qualifies as a T-Spin before clearing lines.
    spin := is_tspin(gs, last_action_was_rotation)
    clear_lines(gs, spin)
    play_sound(&gs.audio, gs.audio.lock)
    spawn_piece(gs)
}

clear_lines :: proc(gs: ^GameState, was_tspin: bool) {
    lines_cleared := 0
    // Scan from bottom to top.
    for y := GRID_HEIGHT - 1; y >= 0; y -= 1 {
        full := true
        for x in 0..<GRID_WIDTH {
            if _, ok := gs.grid[y][x].?; !ok {
                full = false
                break
            }
        }
        if full {
            lines_cleared += 1
            // Shift every row above this one down.
            for yy := y; yy > 0; yy -= 1 {
                gs.grid[yy] = gs.grid[yy - 1]
            }
            // Top row becomes empty.
            gs.grid[0] = {}
            // Stay on the current Y because it now contains a new uncleared row.
            y += 1
        }
    }

    if lines_cleared == 0 {
        gs.last_clear_was_special = false
        return
    }

    is_special := (lines_cleared == 4) || was_tspin
    base := LINE_SCORE[lines_cleared]
    if was_tspin {
        base *= 2 // T-Spin doubles the line clear value.
    }

    btb_bonus := 0
    if is_special && gs.last_clear_was_special {
        btb_bonus = base / 2 // Back-to-back special clears award 50% extra.
    }

    gs.score += (base + btb_bonus) * gs.level
    gs.last_clear_was_special = is_special

    // Handle Level progression.
    gs.lines_total += lines_cleared
    new_level := level_for_lines(gs.lines_total)
    if new_level > gs.level {
        gs.level = new_level
        gs.fall_speed = fall_speed_for_level(gs.level)
        play_sound(&gs.audio, gs.audio.level_up)
    }

    // Play feedback audio.
    if lines_cleared == 4 {
        play_sound(&gs.audio, gs.audio.tetris)
    } else {
        play_sound(&gs.audio, gs.audio.line_clear)
    }
}

spawn_piece :: proc(gs: ^GameState) {
    gs.current_piece = {
        type     = gs.next_piece_type,
        pos      = {GRID_WIDTH / 2 - 2, 0},
        rotation = 0,
    }
    gs.next_piece_type = get_next_piece_from_bag(gs)
    gs.can_stash   = true
    gs.is_locking  = false
    gs.lock_timer  = 0
    gs.lock_move_count = 0

    // If the newly spawned piece immediately collides, the player loses.
    if check_collision(gs, gs.current_piece.type, gs.current_piece.pos, gs.current_piece.rotation) {
        gs.mode = .GameOver
        play_sound(&gs.audio, gs.audio.game_over)
        // Switch to name entry if the score qualifies for the top 10.
        if gs.score > gs.high_scores[9].score {
            gs.mode = .EnteringName
        }
    }
}

stash_piece :: proc(gs: ^GameState) {
    // Only one swap allowed per piece spawn.
    if !gs.can_stash do return

    if stashed, ok := gs.stashed_piece_type.?; ok {
        // Swap currently falling piece with held piece.
        temp := gs.current_piece.type
        gs.current_piece.type = stashed
        gs.stashed_piece_type = temp
    } else {
        // Nothing was held, so stash current and spawn a new one.
        gs.stashed_piece_type = gs.current_piece.type
        spawn_piece(gs)
        if gs.mode == .GameOver || gs.mode == .EnteringName do return
    }

    // Reset piece properties for the newly swapped piece.
    gs.current_piece.pos      = {GRID_WIDTH / 2 - 2, 0}
    gs.current_piece.rotation = 0
    gs.can_stash  = false
    gs.is_locking = false
    gs.lock_timer = 0
    gs.lock_move_count = 0
}

load_high_scores :: proc(gs: ^GameState) {
    data, ok := os.read_entire_file("highscores.txt")
    if !ok do return // No file found, starting with empty leaderboard.
    defer delete(data)

    count := 0
    for line in strings.split_lines(string(data)) {
        if count >= 10 || line == "" do continue
        parts := strings.split(line, ":")
        if len(parts) == 2 {
            // Allocate a new string for the name.
            gs.high_scores[count].name  = strings.clone(parts[0])
            val, _ := strconv.parse_int(parts[1])
            gs.high_scores[count].score = val
            count += 1
        }
    }
}

save_high_scores :: proc(gs: ^GameState) {
    b: strings.Builder
    strings.builder_init(&b)
    defer strings.builder_destroy(&b)

    for i in 0..<10 {
        if gs.high_scores[i].score > 0 {
            fmt.sbprintf(&b, "%s:%d\n", gs.high_scores[i].name, gs.high_scores[i].score)
        }
    }
    // transmute converts the string into a byte slice without copying.
    os.write_entire_file("highscores.txt", transmute([]u8)strings.to_string(b))
}

add_high_score :: proc(gs: ^GameState, name: string, score: int) {
    insert_idx := -1
    for i in 0..<10 {
        if score > gs.high_scores[i].score {
            insert_idx = i
            break
        }
    }
    // Score didn't make the cut.
    if insert_idx == -1 do return

    // Evict the 10th place entry.
    if gs.high_scores[9].name != "" {
        delete(gs.high_scores[9].name)
    }

    // Shift lower scores down by one rank.
    for i := 9; i > insert_idx; i -= 1 {
        gs.high_scores[i] = gs.high_scores[i - 1]
    }
    // Insert new record.
    gs.high_scores[insert_idx] = {
        name  = strings.clone(name),
        score = score,
    }
    // Save updated list.
    save_high_scores(gs)
}
