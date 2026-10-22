#!/usr/bin/env bash
# start.sh — interactive menu for running Stardust (StarCraft: Brood War bot dev environment).
# Gives numbered options for the common tools so you don't have to remember the flags.
set -u
cd "$(dirname "$0")"

PY=".venv/bin/python"

OPPONENTS=(
    Stone BunkerBoxer BananaBrain Stardust2025 ClaudeOpus55
    Steamhammer2025 Microwave McRaveZ CreativeZerg CreativeTerran
    WorkerRush PylonPuller ZZZKBot SparkTerran SparkZerg
    UAlbertaBotTerran UAlbertaBotZerg UAlbertaBotProtoss
    Locutus Iron Dragon SAIDA WillyT Steamhammer
)
# watch.py can also field the Python port itself
WATCH_BOTS=(StardustPy "${OPPONENTS[@]}")

# ask_int "prompt" min max default -> prints the validated number
ask_int() {
    local prompt="$1" min="$2" max="$3" default="$4" ans
    while true; do
        read -rp "$prompt [$default]: " ans || exit 0
        ans="${ans:-$default}"
        if [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -ge "$min" ] && [ "$ans" -le "$max" ]; then
            echo "$ans"
            return
        fi
        echo "enter a number between $min and $max" >&2
    done
}

# ask_float "prompt" min max default -> prints the validated number
ask_float() {
    local prompt="$1" min="$2" max="$3" default="$4" ans
    while true; do
        read -rp "$prompt [$default]: " ans
        ans="${ans:-$default}"
        if [[ "$ans" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v a="$ans" -v lo="$min" -v hi="$max" \
            'BEGIN { exit !(a >= lo && a <= hi) }'; then
            echo "$ans"
            return
        fi
        echo "enter a number between $min and $max" >&2
    done
}

# ask_choice "prompt" "opt1|opt2" default -> prints the validated choice (lowercased)
ask_choice() {
    local prompt="$1" opts="$2" default="$3" ans
    while true; do
        read -rp "$prompt [$default]: " ans || exit 0
        ans="${ans:-$default}"
        ans="$(echo "$ans" | tr '[:upper:]' '[:lower:]')"
        if [[ "|$opts|" == *"|$ans|"* ]]; then
            echo "$ans"
            return
        fi
        echo "choose one of: ${opts//|/, }" >&2
    done
}

# pick_bot "prompt" array_name... -> prints the chosen bot name
# array elements may be "" to mark an already-picked (disabled) entry
bot_race() {
    case "$1" in
        Stone|BunkerBoxer|CreativeTerran|WorkerRush|SparkTerran|UAlbertaBotTerran|SAIDA|Dragon|WillyT|Iron)
            echo "Terran" ;;
        Steamhammer|Steamhammer2025|Microwave|McRaveZ|CreativeZerg|ZZZKBot|SparkZerg|UAlbertaBotZerg)
            echo "Zerg" ;;
        StardustPy) echo "Python port" ;;
        *) echo "Protoss" ;;
    esac
}

pick_bot() {
    local prompt="$1" arr_name="$2"
    local -n arr="$arr_name"
    local i ans
    while true; do
        # menu goes to stderr: stdout is captured as the return value
        echo "$prompt" >&2
        for i in "${!arr[@]}"; do
            if [ -n "${arr[$i]}" ]; then
                printf "  %2d) %-22s %s\n" "$((i + 1))" "${arr[$i]}" "$(bot_race "${arr[$i]}")" >&2
            fi
        done
        read -rp "Which AI do you want to play? Enter its number: " ans || exit 0
        if [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le "${#arr[@]}" ] \
            && [ -n "${arr[$((ans - 1))]}" ]; then
            echo "${arr[$((ans - 1))]}"
            return
        fi
        echo "invalid choice, try again" >&2
    done
}

run_cmd() {
    echo "+ $*"
    "$@"
}

# --- Playing ---

option1_4pool() {
    run_cmd "$PY" tools/run_games.py Steamhammer.4PoolHard
}

option2_custom_games() {
    local bots=( "${WATCH_BOTS[@]}" )
    local ai1 ai2 games ui wins j
    ai1="$(pick_bot "Which AI do you want to play as?" bots)"
    for j in "${!bots[@]}"; do
        [ "${bots[$j]}" = "$ai1" ] && bots[$j]=""
    done
    ai2="$(pick_bot "Which AI should it play against?" bots)"
    games="$(ask_int "How many games" 1 100 12)"
    ui="$(ask_choice "Show the game windows? (Y/N)" "y|n" "n")"
    local cmd=("$PY" tools/run_games.py)
    [ "$ai1" != "StardustPy" ] && cmd+=(--bot "$ai1")
    cmd+=(--opponent "$ai2" --games "$games")
    if [ "$ui" = "y" ]; then
        wins="$(ask_int "How many windows? (1, 2, 4 or 6)" 1 6 4)"
        cmd+=(--ui "$wins")
    fi
    run_cmd "${cmd[@]}"
}

option3_watch() {
    local bots=( "${WATCH_BOTS[@]}" )
    local n i j name speed iterations chosen=()
    n="$(ask_int "How many AIs? (2-4)" 2 4 4)"
    for ((i = 1; i <= n; i++)); do
        name="$(pick_bot "Choose AI #$i:" bots)"
        chosen+=("$name")
        # disable it so it can't be picked again
        for j in "${!bots[@]}"; do
            [ "${bots[$j]}" = "$name" ] && bots[$j]=""
        done
    done
    # round robin: 2 AIs -> 1 game, 3 -> 3 games, 4 -> 6 games, each in its own window automatically
    local pair_games=$((n * (n - 1) / 2))
    echo "round robin: $pair_games game(s), one window each"
    iterations="$(ask_int "How many iterations?" 1 100 1)"
    speed="$(ask_int "Game speed? (0 = unlimited, 1 slowest - 6 fastest)" 0 6 2)"
    for ((i = 1; i <= iterations; i++)); do
        [ "$iterations" -gt 1 ] && echo "--- iteration $i of $iterations ---"
        run_cmd "$PY" tools/watch.py "${chosen[@]}" --speed "$speed"
    done
}

option4_ladder() {
    local bots=( "${WATCH_BOTS[@]}" )
    local ai games keep
    ai="$(pick_bot "Which bot should climb the ladder?" bots)"
    games="$(ask_int "Games against each opponent" 1 20 3)"
    keep="$(ask_choice "Play every opponent, even after one it can't beat? (Y/N)" "y|n" "n")"
    local cmd=("$PY" tools/ladder.py --games "$games")
    [ "$ai" != "StardustPy" ] && cmd+=(--bot "$ai")
    [ "$keep" = "y" ] && cmd+=(--keep-going)
    run_cmd "${cmd[@]}"
}

option5_round_robin() {
    local mode tier games parallel
    mode="$(ask_choice "Play the round robin, or only print the ratings? (P/T)" "p|t" "p")"
    if [ "$mode" = "t" ]; then
        run_cmd "$PY" tools/round_robin.py --table
        return
    fi
    tier="$(ask_choice "Which tier? (1, 2 or all)" "1|2|a" "a")"
    games="$(ask_int "Games per pairing" 1 50 10)"
    parallel="$(ask_int "Games at once" 1 12 4)"
    local cmd=("$PY" tools/round_robin.py --games "$games" --parallel "$parallel")
    case "$tier" in
        1) cmd+=(--tier "Tier 1") ;;
        2) cmd+=(--tier "Tier 2") ;;
    esac
    run_cmd "${cmd[@]}"
}

# --- Looking back at games ---

option6_leaderboard() {
    # Menu# matches the numbered AI list in option 2 (1=StardustPy, 2=Stone, ...)
    local numbers
    numbers="$(for i in "${!WATCH_BOTS[@]}"; do printf "%s:%d," "${WATCH_BOTS[$i]}" "$((i + 1))"; done)"
    "$PY" tools/elo.py | awk -v map="$numbers" '
        BEGIN { n = split(map, pairs, ","); for (k = 1; k <= n; k++) { split(pairs[k], kv, ":"); if (kv[1] != "") num[kv[1]] = kv[2] } }
        /^ *#  Player/ { sub(/^ *#/, " # Menu#"); print; next }
        $1 ~ /^[0-9]+$/ && NF >= 7 {
            name = $2
            menu = (name in num) ? num[name] : "--"
            sub(/^[ ]*[0-9]+/, "&" sprintf("%6s", menu))
            print
            next
        }
        { print }
    '
}

option7_replays() {
    local action
    action="$(ask_choice "Browse the games, list them, write summaries, or read the comments? (B/L/S/C)" "b|l|s|c" "b")"
    case "$action" in
        b|s)
            # the summaries need the replay reader, a build target of its own
            if [ ! -x build/tools/replay_dump ]; then
                run_cmd cmake --build build --target replay_dump
            fi
            ;;
    esac
    case "$action" in
        b) run_cmd "$PY" tools/replays.py ;;
        l) run_cmd "$PY" tools/replays.py list ;;
        s) run_cmd "$PY" tools/replays.py summary ;;
        c) run_cmd "$PY" tools/replays.py comments ;;
    esac
}

option8_live_stats() {
    run_cmd "$PY" tools/live_stats.py --open
}

# --- Training ---

option9_train() {
    local action hours approve
    action="$(ask_choice "Train, show where it stands, or sum up the issues? (T/S/I)" "t|s|i" "s")"
    case "$action" in
        s) run_cmd "$PY" tools/selfplay.py --status ;;
        i) run_cmd "$PY" tools/selfplay.py --issues ;;
        t)
            hours="$(ask_float "How many hours to train" 0.1 720 12)"
            approve="$(ask_choice "Promote every candidate that passes the gate? (Y/N)" "y|n" "n")"
            local cmd=("$PY" tools/selfplay.py --hours "$hours")
            [ "$approve" = "y" ] && cmd+=(--auto-approve)
            run_cmd "${cmd[@]}"
            ;;
    esac
}

# --- Project ---

option10_build() {
    local what threads cores
    what="$(ask_choice "Which build? (W)indows/UI, (H)eadless, or (B)oth" "w|h|b" "b")"
    cores="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    echo "detected $cores cpu cores"
    threads="$(ask_int "Build threads? (1-16)" 1 16 4)"
    case "$what" in
        w) run_cmd cmake --build build-ui -j "$threads" ;;
        h) run_cmd cmake --build build -j "$threads" ;;
        b)
            run_cmd cmake --build build -j "$threads"
            run_cmd cmake --build build-ui -j "$threads"
            ;;
    esac
}

option11_bench() {
    run_cmd "$PY" tools/bench_ui.py
}

option12_tests() {
    local action
    while true; do
        cat <<'MENU'

  Tests and checks:
    1) pytest — the bot's logic, no StarCraft needed
    2) mypy — type-check the bot
    3) stubtest — the type stub against the built module
    4) the C++ host tests (PythonHost.*)
    5) all of them
    0) back
MENU
        read -rp "> " action || exit 0
        case "$action" in
            1) run_cmd uv run pytest ;;
            2) run_cmd uv run mypy ;;
            3) run_cmd env PYTHONPATH=build/python MYPYPATH=python \
                "$PY" -m mypy.stubtest bwapi bwem fap instrumentation \
                --allowlist tools/stubtest_allowlist.txt ;;
            4) host_tests ;;
            5)
                run_cmd uv run pytest
                run_cmd uv run mypy
                run_cmd env PYTHONPATH=build/python MYPYPATH=python \
                    "$PY" -m mypy.stubtest bwapi bwem fap instrumentation \
                    --allowlist tools/stubtest_allowlist.txt
                host_tests
                ;;
            0|q|back|quit|exit) return ;;
            *) echo "unknown option: $action" ;;
        esac
        echo
        read -rp "press enter to continue..." _ || exit 0
    done
}

option13_developer() {
    local action old new
    while true; do
        cat <<'MENU'

  Developer tools:
    1) fetch an opponent bot from a recipe
    2) regenerate the BWAPI bindings
    3) rename a bot
    4) render the HUD panel preview
    5) regenerate the builder blocks
    6) regenerate the type names
    7) regenerate the HUD font
    8) regenerate the creative Steamhammer bots
    0) back
MENU
        read -rp "> " action || exit 0
        case "$action" in
            1) fetch_a_bot ;;
            2) run_cmd "$PY" tools/gen_bwapi_bindings.py ;;
            3)
                read -rp "Old name: " old || exit 0
                read -rp "New name: " new || exit 0
                [ -n "$old" ] && [ -n "$new" ] && run_cmd "$PY" tools/rename_bot.py "$old" "$new"
                ;;
            4)
                run_cmd cmake --build build --target hud_preview
                run_cmd build/hud_preview hud_preview.ppm
                echo "wrote hud_preview.ppm"
                ;;
            5) gen_blocks ;;
            6) run_cmd "$PY" tools/gen_type_names.py ;;
            7)
                if "$PY" -c "import PIL" 2>/dev/null; then
                    run_cmd "$PY" tools/gen_hud_font.py
                else
                    echo "needs Pillow, which is not one of the project's dependencies: uv pip install pillow"
                fi
                ;;
            8) run_cmd "$PY" tools/make_creative_steamhammer.py ;;
            0|q|back|quit|exit) return ;;
            *) echo "unknown option: $action" ;;
        esac
        echo
        read -rp "press enter to continue..." _ || exit 0
    done
}

# host_tests — the C++ host tests, which run from build/test
host_tests() {
    if [ ! -x build/test/tests ]; then
        echo "the test harness isn't built yet: cmake --build build --target tests"
        return
    fi
    (cd build/test && run_cmd ./tests --gtest_filter='PythonHost.*')
}

# fetch_a_bot — fetch one of the recipe bots into bots/
fetch_a_bot() {
    local recipes=() name ans
    while IFS= read -r name; do
        [ -n "$name" ] && recipes+=("$name")
    done < <("$PY" tools/fetch_bot.py --list | awk '{print $1}')
    if [ "${#recipes[@]}" -eq 0 ]; then
        echo "no recipes in bots/recipes/"
        return
    fi
    echo "recipes:"
    local i
    for i in "${!recipes[@]}"; do
        printf "  %2d) %s\n" "$((i + 1))" "${recipes[$i]}"
    done
    while true; do
        read -rp "Which bot do you want to fetch? Enter its number: " ans || exit 0
        if [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le "${#recipes[@]}" ]; then
            name="${recipes[$((ans - 1))]}"
            break
        fi
        echo "invalid choice, try again" >&2
    done
    run_cmd "$PY" tools/fetch_bot.py "$name"
    echo "rebuild to pick it up: cmake -S . -B build && cmake --build build -j 4"
}

# gen_blocks — regenerate the builder blocks from the reference sources
gen_blocks() {
    local source=".reference/Stardust/src/Builder/Blocks"
    if [ ! -d "$source" ]; then
        echo "the reference sources are not here: clone Stardust into $source"
        return
    fi
    run_cmd "$PY" tools/gen_blocks.py "$source" python/stardust/builder/blocks
}

while true; do
    cat <<'MENU'

  Stardust — pick an option:

    Playing
      1) run games vs Steamhammer 4-pool hard
      2) run games vs an AI you choose
      3) watch a multi-AI round robin
      4) play the opponent ladder
      5) rate the bots by tier (round robin)

    Looking back at games
      6) leaderboard (elo)
      7) replay summaries and playback
      8) live stats window

    Training
      9) train RL_ClaudeOpus55 (self-play)

    Project
     10) build / compile
     11) bench UI
     12) tests and checks
     13) developer tools
      0) quit
MENU
    read -rp "> " choice || exit 0
    case "$choice" in
        1) option1_4pool ;;
        2) option2_custom_games ;;
        3) option3_watch ;;
        4) option4_ladder ;;
        5) option5_round_robin ;;
        6) option6_leaderboard ;;
        7) option7_replays ;;
        8) option8_live_stats ;;
        9) option9_train ;;
        10) option10_build ;;
        11) option11_bench ;;
        12) option12_tests ;;
        13) option13_developer ;;
        0|q|quit|exit) exit 0 ;;
        *) echo "unknown option: $choice" ;;
    esac
    echo
    read -rp "press enter to continue..." _ || exit 0
done
