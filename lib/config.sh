#!/bin/bash

# --- Configuration Defaults ---
readonly DEFAULT_LOG_FILE="conversion_log.txt"
readonly DEFAULT_QUALITY_VALUE=28
readonly DEFAULT_ENCODER_TYPE="cpu"
readonly DEFAULT_CPU_PRESET="medium"
readonly DEFAULT_VIDEO_EXTENSIONS=("mp4" "mkv" "avi" "mov" "flv" "wmv")
readonly DEFAULT_LOG_LEVEL_NAME="INFO"

# --- Initialize variables ---
DRY_RUN=0
KEEP_ORIGINALS=0
LOG_FILE="$DEFAULT_LOG_FILE"
QUALITY_VALUE="$DEFAULT_QUALITY_VALUE"
ENCODER_TYPE="$DEFAULT_ENCODER_TYPE"
CPU_PRESET="$DEFAULT_CPU_PRESET"
INPUT_DIR=""
OUTPUT_DIR=""
VIDEO_EXTENSIONS=("${DEFAULT_VIDEO_EXTENSIONS[@]}")
CURRENT_LOG_LEVEL_NAME="$DEFAULT_LOG_LEVEL_NAME"

export DRY_RUN KEEP_ORIGINALS LOG_FILE QUALITY_VALUE ENCODER_TYPE CPU_PRESET INPUT_DIR OUTPUT_DIR VIDEO_EXTENSIONS CURRENT_LOG_LEVEL_NAME

load_config_file() {
    local config_file="convert_h265.conf"
    if [[ -f "$config_file" ]]; then
        log_message "$LOG_LEVEL_INFO" "Loading configuration from $config_file..."
        source "$config_file"
        # Override defaults with values from config file if set
        : "${LOG_FILE:=$DEFAULT_LOG_FILE}"
        : "${QUALITY_VALUE:=$DEFAULT_QUALITY_VALUE}"
        : "${ENCODER_TYPE:=$DEFAULT_ENCODER_TYPE}"
        : "${CPU_PRESET:=$DEFAULT_CPU_PRESET}"
        : "${INPUT_DIR:=$INPUT_DIR}" # Keep existing if set by args
        : "${OUTPUT_DIR:=$OUTPUT_DIR}" # Keep existing if set by args
        : "${CURRENT_LOG_LEVEL_NAME:=$DEFAULT_LOG_LEVEL_NAME}"
        log_message "$LOG_LEVEL_INFO" "Configuration loaded."
    else
        log_message "$LOG_LEVEL_INFO" "No configuration file '$config_file' found. Using default settings."
    fi
}
export -f load_config_file

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--input)
                INPUT_DIR="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -q|--quality)
                QUALITY_VALUE="$2"
                shift 2
                ;;
            -e|--encoder)
                ENCODER_TYPE="$2"
                shift 2
                ;;
            -p|--preset)
                CPU_PRESET="$2"
                shift 2
                ;;
            -l|--log-level)
                CURRENT_LOG_LEVEL_NAME="$2"
                shift 2
                ;;
            -f|--log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -k|--keep-originals)
                KEEP_ORIGINALS=1
                shift
                ;;
            -h|--help)
                display_help
                exit 0
                ;;
            *)
                log_message "$LOG_LEVEL_ERROR" "Unknown option: $1"
                display_help
                exit 1
                ;;
        esac
    done

    # Ensure output directory is set if input directory is provided via arguments
    if [[ -n "$INPUT_DIR" && -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="$INPUT_DIR"
    fi
}
export -f parse_arguments

initialize_config() {
    load_config_file
    parse_arguments "$@"

    # Resolve CURRENT_LOG_LEVEL from name to numeric value
    case "$CURRENT_LOG_LEVEL_NAME" in
        "DEBUG") CURRENT_LOG_LEVEL="$LOG_LEVEL_DEBUG" ;;
        "INFO") CURRENT_LOG_LEVEL="$LOG_LEVEL_INFO" ;;
        "WARNING") CURRENT_LOG_LEVEL="$LOG_LEVEL_WARNING" ;;
        "ERROR") CURRENT_LOG_LEVEL="$LOG_LEVEL_ERROR" ;;
        *)
            log_message "$LOG_LEVEL_WARNING" "Invalid log level '$CURRENT_LOG_LEVEL_NAME' specified. Defaulting to INFO."
            CURRENT_LOG_LEVEL="$LOG_LEVEL_INFO"
            CURRENT_LOG_LEVEL_NAME="INFO"
            ;;
    esac
    export CURRENT_LOG_LEVEL
}
export -f initialize_config