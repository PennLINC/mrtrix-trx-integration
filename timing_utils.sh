#!/usr/bin/env bash
# timing_utils.sh — source this file before running the walkthrough
#
# Provides mtime(): runs a command, shows its stderr live in the chunk output,
# then appends a one-line timing + memory summary.
#
# How the stderr separation works:
#   /usr/bin/time -l writes its timing block to stderr AFTER the command exits.
#   The command's own progress output also goes to stderr.  Both land in $tmp.
#   We locate the timing block by finding the last line matching
#   "^ *[0-9.]+ real " (the first line of /usr/bin/time -l output), forward
#   every line before that as the command's stderr, then parse the timing block.
#
# Memory metric: "peak memory footprint" (phys_footprint from TASK_VM_INFO).
#   Excludes clean read-only mmap pages, so TRX files are not counted twice.
#   RSS ("maximum resident set size") would be inflated for TRX inputs.
#
# Linux: replace -l with -v; the footprint grep becomes:
#   awk '/Maximum resident/{print $NF * 1024}' "$tmp"

mtime() {
    local label="$1"; shift
    local tmp; tmp=$(mktemp)

    /usr/bin/time -l "$@" 2>"$tmp"
    local exit_code=$?

    # Find where /usr/bin/time's own output starts.
    # Its first line always matches "^ *[0-9.]+ real " (BSD time format).
    local timing_line
    timing_line=$(grep -n "^[[:space:]]*[0-9.]\+ real " "$tmp" \
                  | tail -1 | cut -d: -f1)

    if [ -n "$timing_line" ] && [ "$timing_line" -gt 1 ]; then
        # Replay the command's stderr (lines before the timing block)
        head -n "$((timing_line - 1))" "$tmp"
    fi

    if [ -z "$timing_line" ]; then
        # /usr/bin/time didn't produce output — command likely failed
        cat "$tmp"
        rm -f "$tmp"
        return "$exit_code"
    fi

    # Parse wall / user / sys from the timing line
    local wall user sys
    read -r wall _ user _ sys _ \
        < <(sed -n "${timing_line}p" "$tmp")

    # Parse physical footprint (excludes clean mmap pages)
    local fp_bytes fp_gb
    fp_bytes=$(tail -n "+${timing_line}" "$tmp" \
               | awk '/peak memory footprint/{print $1}')
    fp_gb=$(awk "BEGIN {printf \"%.2f\", ${fp_bytes:-0} / 1073741824}")

    printf "\n┌─ %-28s ─────────────────────────────────────────────┐\n" "$label"
    printf "│  wall: %8ss    user: %8ss    sys: %6ss    peak mem: %5s GB  │\n" \
           "$wall" "$user" "$sys" "$fp_gb"
    printf "└────────────────────────────────────────────────────────────────────────────┘\n\n"

    rm -f "$tmp"
    return "$exit_code"
}
