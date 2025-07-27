#!/bin/bash

# --- Logging Levels ---
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3

# Fix: Initialize with a default value
CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
export CURRENT_LOG_LEVEL

# --- Logging & Helpers ---
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ "$level" -ge "$CURRENT_LOG_LEVEL" ]]; then
        case "$level" in
            "$LOG_LEVEL_DEBUG") echo -e "[DEBUG] [$timestamp] $message" | tee -a "$LOG_FILE" ;;
            "$LOG_LEVEL_INFO") echo -e "[INFO] [$timestamp] $message" | tee -a "$LOG_FILE" ;;
            "$LOG_LEVEL_WARNING") echo -e "[WARNING] [$timestamp] $message" | tee -a "$LOG_FILE" >&2 ;;
            "$LOG_LEVEL_ERROR") echo -e "[ERROR] [$timestamp] $message" | tee -a "$LOG_FILE" >&2 ;;
            *) echo -e "[UNKNOWN] [$timestamp] $message" | tee -a "$LOG_FILE" >&2 ;;
        esac
    fi
}
export -f log_message

get_file_size() {
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        stat -f "%z" "$file_path" 2>/dev/null || du -b "$file_path" | awk '{print $1}'
    else
        echo "0"
    fi
}
export -f get_file_size

check_dependencies() {
    log_message "$LOG_LEVEL_INFO" "Checking for required dependencies: ffmpeg, ffprobe, mediainfo..."
    local missing_deps=()
    for cmd in ffmpeg ffprobe mediainfo; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ "${#missing_deps[@]}" -gt 0 ]]; then
        log_message "$LOG_LEVEL_ERROR" "Missing required dependencies: ${missing_deps[*]}."
        log_message "$LOG_LEVEL_ERROR" "Please install them to proceed. Exiting."
        exit 1
    fi
    log_message "$LOG_LEVEL_INFO" "All required dependencies found."
}
export -f check_dependencies

cleanup_on_exit() {
    local exit_code=$?
    if [[ "$exit_code" -ne 0 ]]; then
        log_message "$LOG_LEVEL_ERROR" "Script terminated unexpectedly with exit code $exit_code."
    else
        log_message "$LOG_LEVEL_INFO" "Script execution completed."
    fi
    # Add any other cleanup actions here, e.g., removing temporary files
    # rm -f /tmp/my_temp_file
}
export -f cleanup_on_exit