#!/bin/bash

# Script to recursively find H.264 videos and convert them to H.265 (HEVC)
# Outputs converted files into the same directory as the original,
# appending '_h265.mp4' to the filename (e.g., original.mkv -> original_h265.mp4).
# Preserves audio and subtitle streams.
# Allows user to choose encoding preset (fast, medium, slow) for CPU.
# Allows user to choose between CPU (libx265) and GPU (VAAPI) encoding.
# Processes files and folders in alphabetical order.
#
# Features:
# - External configuration file
# - Command-line arguments for key settings
# - Dry run mode
# - Granular logging levels
# - Uses temporary files for conversion safety
# - Signal handling for cleanup
#
# !!! WARNING !!!
# This script will AUTOMATICALLY DELETE files based on size comparison:
# 1. If the new H.265 file is SMALLER than the original H.264 file, THE ORIGINAL H.264 FILE WILL BE DELETED.
# 2. If the new H.265 file is NOT SMALLER (same size or larger) than the original,
#    THE NEWLY CREATED H.265 FILE WILL BE DELETED.
# Ensure you have backups or understand this behavior before proceeding.
# !!! WARNING !!!

# --- Configuration Defaults (can be overridden by config file or CLI args) ---
DEFAULT_LOG_FILE="conversion_log.txt"
DEFAULT_QUALITY_VALUE=28
DEFAULT_ALLOWED_CPU_PRESETS=("fast" "medium" "slow")
DEFAULT_CPU_PRESET_VALUE="medium"
DEFAULT_VAAPI_DEVICE="/dev/dri/renderD128"
DEFAULT_VIDEO_EXTENSIONS_ARRAY=("mp4" "mkv" "mov" "avi" "flv" "webm" "mpg" "mpeg" "wmv")
DEFAULT_CONFIG_FILE_PATH="./convert_h265.conf" # Default path for config file

# --- Logging Levels ---
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARNING=2
LOG_LEVEL_ERROR=3
DEFAULT_LOG_LEVEL=$LOG_LEVEL_INFO # Default log level

# --- Initialize variables that will be set by defaults, config, or CLI ---
LOG_FILE="$DEFAULT_LOG_FILE"
QUALITY_VALUE="$DEFAULT_QUALITY_VALUE"
ALLOWED_CPU_PRESETS=("${DEFAULT_ALLOWED_CPU_PRESETS[@]}")
# CPU_PRESET will be set after user prompt or default from DEFAULT_CPU_PRESET_VALUE
VAAPI_DEVICE="$DEFAULT_VAAPI_DEVICE"
VIDEO_EXTENSIONS=("${DEFAULT_VIDEO_EXTENSIONS_ARRAY[@]}")
CURRENT_LOG_LEVEL="$DEFAULT_LOG_LEVEL"
CONFIG_FILE_PATH="$DEFAULT_CONFIG_FILE_PATH"
ENCODER_TYPE="" # Will be set by user
CPU_PRESET="$DEFAULT_CPU_PRESET_VALUE" # Default, can be changed by user or config

# --- Runtime Variables ---
DRY_RUN=0 # 0 for false (execute), 1 for true (simulate)
CURRENT_TEMP_FILE="" # Holds the path to the current temporary ffmpeg output

# --- Signal Handling & Cleanup ---
cleanup_on_exit() {
    if [[ -n "$CURRENT_TEMP_FILE" && -f "$CURRENT_TEMP_FILE" ]]; then
        # log_message might not be available if exit is too early / log file not set
        # So, echo as well for critical cleanup info
        echo "Attempting cleanup of temporary file: $CURRENT_TEMP_FILE"
        if [[ "$DRY_RUN" -eq 0 ]]; then
            rm -f "$CURRENT_TEMP_FILE"
            # If log_message is available and LOG_FILE is set:
            if command -v log_message &> /dev/null && [[ -n "$LOG_FILE" ]]; then
                 log_message "$LOG_LEVEL_WARNING" "Cleaned up temporary file on exit: $CURRENT_TEMP_FILE"
            else
                echo "Cleaned up temporary file on exit: $CURRENT_TEMP_FILE"
            fi
        else
            if command -v log_message &> /dev/null && [[ -n "$LOG_FILE" ]]; then
                log_message "$LOG_LEVEL_WARNING" "DRY RUN: Would have cleaned up temporary file on exit: $CURRENT_TEMP_FILE"
            else
                echo "DRY RUN: Would have cleaned up temporary file on exit: $CURRENT_TEMP_FILE"
            fi
        fi
    fi
    echo "Script exiting."
}
trap 'cleanup_on_exit' SIGINT SIGTERM EXIT

# --- Helper Functions ---
log_message() {
    local level="$1"
    local message="$2"

    if [[ "$level" -ge "$CURRENT_LOG_LEVEL" ]]; then
        local level_str="INFO" # Default
        if [[ "$level" -eq "$LOG_LEVEL_DEBUG" ]]; then level_str="DEBUG";
        elif [[ "$level" -eq "$LOG_LEVEL_WARNING" ]]; then level_str="WARNING";
        elif [[ "$level" -eq "$LOG_LEVEL_ERROR" ]]; then level_str="ERROR";
        fi
        
        # Ensure LOG_FILE is set before trying to tee to it
        if [[ -n "$LOG_FILE" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [$level_str] - $message" | tee -a "$LOG_FILE"
        else # Fallback if LOG_FILE isn't set (e.g. very early error)
            echo "$(date '+%Y-%m-%d %H:%M:%S') [$level_str] - $message"
        fi
    fi
}

get_file_size() {
    stat -c%s "$1" 2>/dev/null || echo "0" # return 0 if stat fails
}

log_conversion_details() {
    local original_file="$1"
    local original_size="$2"
    local converted_file_path_info="$3" # Could be temp path or final path, or N/A
    local converted_size_info="$4"    # Could be size of temp or final, or N/A
    local status="$5"
    local notes="$6"

    local details_message
    details_message=$(cat <<EOF
--- Conversion Record ---
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Original File: $original_file
Original Size: $original_size bytes
Converted File Path: $converted_file_path_info
Converted Size: $converted_size_info bytes
Status: $status
EOF
    )
    if [[ -n "$notes" ]]; then
        details_message+=$'\n'"Notes: $notes"
    fi

    if [[ "$status" == "SUCCESS_ORIGINAL_DELETED" && "$original_size" -gt 0 && "$converted_size_info" =~ ^[0-9]+$ && "$converted_size_info" -gt 0 && "$converted_size_info" -lt "$original_size" ]]; then
        local reduction_percentage=$(( ( (original_size - converted_size_info) * 100) / original_size ))
        details_message+=$'\n'"Size Reduction: $reduction_percentage%"
    fi
    details_message+=$'\n'"-------------------------"

    log_message "$LOG_LEVEL_INFO" "$details_message"
}

check_dependencies() {
    if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null; then
        log_message "$LOG_LEVEL_ERROR" "ffmpeg and ffprobe are not installed. Please install them first."
        echo "Error: ffmpeg and ffprobe are not installed. Please install them first."
        echo "On Arch Linux, you can use: sudo pacman -S ffmpeg"
        exit 1
    fi
    if ! command -v vainfo &> /dev/null; then
        local vainfo_msg="vainfo is not installed. It's useful for checking VAAPI setup. On Arch Linux: sudo pacman -S libva-utils"
        log_message "$LOG_LEVEL_WARNING" "$vainfo_msg"
        echo "Warning: $vainfo_msg" # Keep echo for immediate user feedback
    fi
}

display_help() {
cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -c, --config FILE     Path to configuration file (default: $DEFAULT_CONFIG_FILE_PATH).
  -d, --dry-run         Simulate conversions and deletions without actual changes.
  -e, --extensions EXT  Comma-separated list of video extensions to process (e.g., "mp4,mkv,avi").
                        Overrides config file and script defaults.
  -l, --log-level LEVEL Log level: DEBUG, INFO, WARNING, ERROR (default: INFO).
  -h, --help            Display this help message and exit.

Configuration file variables (example format: VAR_NAME="value"):
  LOG_FILE="$DEFAULT_LOG_FILE"
  QUALITY_VALUE="$DEFAULT_QUALITY_VALUE"
  DEFAULT_CPU_PRESET_VALUE="$DEFAULT_CPU_PRESET_VALUE" # Affects default if CPU chosen
  VAAPI_DEVICE="$DEFAULT_VAAPI_DEVICE"
  VIDEO_EXTENSIONS_STRING="mp4,mkv,mov" # In config, use a string
  CURRENT_LOG_LEVEL_NAME_CONFIG="INFO"  # For setting log level from config
EOF
exit 0
}

# --- Argument Parsing ---
# Variables for CLI arguments that might override config
cli_extensions_string=""
cli_log_level_name="" # Store name to parse later
cli_config_file_path=""

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -c|--config)
        cli_config_file_path="$2"
        shift; shift
        ;;
        -d|--dry-run)
        DRY_RUN=1
        shift
        ;;
        -e|--extensions)
        cli_extensions_string="$2"
        shift; shift
        ;;
        -l|--log-level)
        cli_log_level_name=$(echo "$2" | tr '[:lower:]' '[:upper:]')
        shift; shift
        ;;
        -h|--help)
        display_help
        ;;
        *)    # unknown option
        echo "Unknown option: $1"
        display_help # Exits
        ;;
    esac
done

# Set config file path (CLI overrides default)
if [[ -n "$cli_config_file_path" ]]; then
    CONFIG_FILE_PATH="$cli_config_file_path"
fi

# --- Load Configuration File (if exists) ---
# Variables sourced from config will override script defaults
if [[ -f "$CONFIG_FILE_PATH" ]]; then
    # Define a list of allowed variables from config to be sourced
    # This is a security measure to prevent arbitrary code execution from config file
    # For simplicity, we are directly sourcing, but for more security, parse key=value.
    ALLOWED_CONFIG_VARS=("LOG_FILE" "QUALITY_VALUE" "DEFAULT_CPU_PRESET_VALUE" "VAAPI_DEVICE" "VIDEO_EXTENSIONS_STRING" "CURRENT_LOG_LEVEL_NAME_CONFIG")
    
    TEMP_CONFIG_ENV=$(mktemp)
    # Filter config file to only include allowed variables assignments
    grep -E "^($(IFS=\|; echo "${ALLOWED_CONFIG_VARS[*]}"))\s*=" "$CONFIG_FILE_PATH" > "$TEMP_CONFIG_ENV"
    
    # Temporarily disable unbound variable errors if config is sparse
    set +u
    # shellcheck source=/dev/null
    source "$TEMP_CONFIG_ENV"
    set -u # Re-enable unbound variable errors
    rm "$TEMP_CONFIG_ENV"
    
    echo "Loaded configuration from: $CONFIG_FILE_PATH"

    # If VIDEO_EXTENSIONS_STRING is set in config, parse it
    # CLI -e option will override this later if provided
    if [[ -n "${VIDEO_EXTENSIONS_STRING:-}" ]]; then # Use :- for safety if var unbound
        IFS=',' read -r -a VIDEO_EXTENSIONS <<< "$VIDEO_EXTENSIONS_STRING"
    fi
    # If CURRENT_LOG_LEVEL_NAME_CONFIG is set in config, use it as current log level name
    # CLI -l option will override this later if provided
    if [[ -n "${CURRENT_LOG_LEVEL_NAME_CONFIG:-}" ]]; then
        CURRENT_LOG_LEVEL_NAME="$CURRENT_LOG_LEVEL_NAME_CONFIG"
    else # Ensure CURRENT_LOG_LEVEL_NAME has a default if not in config
        CURRENT_LOG_LEVEL_NAME=$( ( (($DEFAULT_LOG_LEVEL == LOG_LEVEL_DEBUG)) && echo "DEBUG" ) || ( (($DEFAULT_LOG_LEVEL == LOG_LEVEL_INFO)) && echo "INFO" ) || ( (($DEFAULT_LOG_LEVEL == LOG_LEVEL_WARNING)) && echo "WARNING" ) || ( (($DEFAULT_LOG_LEVEL == LOG_LEVEL_ERROR)) && echo "ERROR" ) )
    fi
    # Update CPU_PRESET default from config if set
    if [[ -n "${DEFAULT_CPU_PRESET_VALUE:-}" ]]; then
        CPU_PRESET="$DEFAULT_CPU_PRESET_VALUE"
    fi
else
    echo "Configuration file not found at $CONFIG_FILE_PATH. Using script defaults or CLI arguments."
    CURRENT_LOG_LEVEL_NAME=$( ( (($DEFAULT_LOG_LEVEL == LOG_LEVEL_DEBUG)) && echo "DEBUG" ) || ( (($DEFAULT_LOG_LEVEL == LOG_LEVEL_INFO)) && echo "INFO" ) || ( (($DEFAULT_LOG_LEVEL == LOG_LEVEL_WARNING)) && echo "WARNING" ) || ( (($DEFAULT_LOG_LEVEL == LOG_LEVEL_ERROR)) && echo "ERROR" ) )
fi

# Apply CLI argument overrides for extensions and log level
if [[ -n "$cli_extensions_string" ]]; then
    IFS=',' read -r -a VIDEO_EXTENSIONS <<< "$cli_extensions_string"
    echo "Using video extensions from command line: ${VIDEO_EXTENSIONS[*]}"
fi
if [[ -n "$cli_log_level_name" ]]; then
    CURRENT_LOG_LEVEL_NAME="$cli_log_level_name"
    echo "Using log level from command line: $CURRENT_LOG_LEVEL_NAME"
fi

# Set numeric CURRENT_LOG_LEVEL based on resolved CURRENT_LOG_LEVEL_NAME
case "$CURRENT_LOG_LEVEL_NAME" in
    DEBUG) CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
    INFO)  CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
    WARNING) CURRENT_LOG_LEVEL=$LOG_LEVEL_WARNING ;;
    ERROR) CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
    *)
      echo "Invalid log level '$CURRENT_LOG_LEVEL_NAME'. Defaulting to INFO."
      CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
      CURRENT_LOG_LEVEL_NAME="INFO" # Correct the name too
      ;;
esac

# --- Script Start ---
# Initialize log file with a header (overwrites previous log for this run)
# Ensure directory for LOG_FILE exists if it's in a subdir
mkdir -p "$(dirname "$LOG_FILE")"
echo "--- Log Start $(date '+%Y-%m-%d %H:%M:%S') ---" > "$LOG_FILE"
# Now that LOG_FILE is prepared, log_message can be used safely

check_dependencies

if [[ "$DRY_RUN" -eq 1 ]]; then
    log_message "$LOG_LEVEL_WARNING" "DRY RUN MODE ENABLED. No actual changes will be made."
fi

echo "H.264 to H.265 Video Conversion Script with Auto-Delete, Sorting & GPU Option"
echo "---------------------------------------------------------------------------"
echo "Converted files will be saved in the SAME DIRECTORY as their originals,"
echo "with '_h265.mp4' appended to the original filename (before extension)."
echo "Files and folders will be processed in alphabetical order."
echo ""
echo "!!! WARNING !!!"
echo "This script will AUTOMATICALLY DELETE files based on size comparison:"
echo "1. If H.265 is SMALLER -> ORIGINAL H.264 IS DELETED."
echo "2. If H.265 is NOT SMALLER -> NEW H.265 IS DELETED."
echo "Review the script comments and ensure you understand this before proceeding."
echo "A detailed log will be kept in: $(pwd)/$LOG_FILE (Log Level: $CURRENT_LOG_LEVEL_NAME)"
echo "For GPU encoding, ensure VAAPI drivers are installed (e.g., libva-mesa-driver on Arch)."
echo "You can check VAAPI with 'vainfo'."
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "!!! DRY RUN MODE IS ACTIVE !!! NO FILES WILL BE CONVERTED OR DELETED."
fi
echo "!!! WARNING !!!"
echo ""

# --- Get Encoder Type & CPU Preset ---
read -r -p "Choose encoder: (1) CPU (libx265) or (2) GPU (VAAPI hevc_vaapi) [default: 1]: " encoder_choice
case "$encoder_choice" in
    2)
        ENCODER_TYPE="gpu"
        log_message "$LOG_LEVEL_INFO" "User chose GPU (VAAPI hevc_vaapi) for encoding."
        echo "Using GPU (VAAPI hevc_vaapi) for encoding."
        if [ ! -e "$VAAPI_DEVICE" ]; then
            log_message "$LOG_LEVEL_WARNING" "VAAPI device $VAAPI_DEVICE not found. GPU encoding might fail."
            echo "WARNING: VAAPI device $VAAPI_DEVICE not found. GPU encoding might fail. Check device path or drivers."
        fi
        ;;
    1|*)
        ENCODER_TYPE="cpu"
        log_message "$LOG_LEVEL_INFO" "User chose CPU (libx265) for encoding."
        echo "Using CPU (libx265) for encoding."
        echo ""
        echo "Please choose a CPU encoding preset for H.265 (libx265):"
        echo "  fast   - Faster encoding, potentially larger file size for the same quality."
        echo "  medium - Balanced encoding speed and compression (good all-rounder)."
        echo "  slow   - Slower encoding, potentially smaller file size for the same quality."
        read -r -p "Enter preset (${ALLOWED_CPU_PRESETS[*]}) [default: $CPU_PRESET]: " CHOSEN_CPU_PRESET_INPUT

        if [[ -z "$CHOSEN_CPU_PRESET_INPUT" ]]; then
            # CPU_PRESET already holds default from DEFAULT_CPU_PRESET_VALUE or config
            log_message "$LOG_LEVEL_INFO" "No CPU preset entered, using current default: $CPU_PRESET"
            echo "No CPU preset entered, using default: $CPU_PRESET"
        else
            CHOSEN_CPU_PRESET_LOWER=$(echo "$CHOSEN_CPU_PRESET_INPUT" | tr '[:upper:]' '[:lower:]')
            is_valid_preset=false
            for valid_opt in "${ALLOWED_CPU_PRESETS[@]}"; do
                if [[ "$CHOSEN_CPU_PRESET_LOWER" == "$valid_opt" ]]; then
                    CPU_PRESET="$CHOSEN_CPU_PRESET_LOWER"
                    is_valid_preset=true
                    break
                fi
            done
            if ! $is_valid_preset; then
                log_message "$LOG_LEVEL_WARNING" "Invalid CPU preset '$CHOSEN_CPU_PRESET_INPUT'. Using default: $DEFAULT_CPU_PRESET_VALUE."
                echo "Invalid CPU preset '$CHOSEN_CPU_PRESET_INPUT'. Using default: $DEFAULT_CPU_PRESET_VALUE."
                CPU_PRESET="$DEFAULT_CPU_PRESET_VALUE" # Fallback to original script default if invalid
            else
                log_message "$LOG_LEVEL_INFO" "User chose CPU preset: $CPU_PRESET"
                echo "Using CPU preset: $CPU_PRESET"
            fi
        fi
        ;;
esac
echo ""

# --- Get Input Directory ---
INPUT_DIR_RAW=""
read -r -p "Enter the full path to the root directory to scan (e.g., /mnt/Videos or . for current): " INPUT_DIR_RAW
if [[ -z "$INPUT_DIR_RAW" ]]; then
    log_message "$LOG_LEVEL_ERROR" "No input directory provided. Exiting."
    echo "Error: No input directory provided. Exiting."
    exit 1
fi
# Resolve to absolute path for consistency
INPUT_DIR=$(realpath "$INPUT_DIR_RAW")
if [[ ! -d "$INPUT_DIR" ]]; then
    log_message "$LOG_LEVEL_ERROR" "Input directory '$INPUT_DIR' (from '$INPUT_DIR_RAW') does not exist or is not a directory. Exiting."
    echo "Error: Input directory '$INPUT_DIR' (from '$INPUT_DIR_RAW') does not exist or is not a directory. Exiting."
    exit 1
fi
echo ""

# --- Configuration Summary ---
log_message "$LOG_LEVEL_INFO" "--- Current Configuration ---"
log_message "$LOG_LEVEL_INFO" "  Input Directory: $INPUT_DIR"
log_message "$LOG_LEVEL_INFO" "  Log File: $(pwd)/$LOG_FILE"
log_message "$LOG_LEVEL_INFO" "  Log Level: $CURRENT_LOG_LEVEL_NAME"
log_message "$LOG_LEVEL_INFO" "  Chosen Encoder: $ENCODER_TYPE"
if [[ "$ENCODER_TYPE" == "cpu" ]]; then
    log_message "$LOG_LEVEL_INFO" "  CPU Preset: $CPU_PRESET"
    log_message "$LOG_LEVEL_INFO" "  CPU Quality (CRF): $QUALITY_VALUE"
else # gpu
    log_message "$LOG_LEVEL_INFO" "  GPU VAAPI Device: $VAAPI_DEVICE"
    log_message "$LOG_LEVEL_INFO" "  GPU Quality (QP): $QUALITY_VALUE (Note: QP is not directly equivalent to CRF)"
fi
log_message "$LOG_LEVEL_INFO" "  Video Extensions: ${VIDEO_EXTENSIONS[*]}"
if [[ "$DRY_RUN" -eq 1 ]]; then
    log_message "$LOG_LEVEL_WARNING" "  DRY RUN MODE: ENABLED"
fi
echo "Configuration summary logged. Check $(pwd)/$LOG_FILE for details."
echo ""

# --- Final Confirmation ---
if [[ "$DRY_RUN" -eq 0 ]]; then
    read -r -p "ARE YOU ABSOLUTELY SURE you want to proceed with actual conversions and potential file deletions? (yes/no): " CONFIRMATION
    if [[ "$CONFIRMATION" != "yes" ]]; then
        log_message "$LOG_LEVEL_INFO" "Conversion cancelled by user."
        echo "Conversion cancelled by user."
        exit 0
    fi
else
    read -r -p "This is a DRY RUN. No files will be changed. Proceed? (yes/no): " CONFIRMATION
    if [[ "$CONFIRMATION" != "yes" ]]; then
        log_message "$LOG_LEVEL_INFO" "Dry run cancelled by user."
        echo "Dry run cancelled by user."
        exit 0
    fi
fi

log_message "$LOG_LEVEL_INFO" "Script processing started. Input: '$INPUT_DIR'. Encoder: '$ENCODER_TYPE'. Quality Value: '$QUALITY_VALUE'. CPU Preset (if CPU): '$CPU_PRESET'. AUTO-DELETION LOGIC ACTIVE. Order: Alphabetical."

# --- Initialize Counters ---
total_files_checked=0
h264_files_identified=0
successful_conversions_kept=0
reverted_conversions_not_smaller=0
failed_ffmpeg_conversions=0
skipped_already_hevc=0
failed_original_deletions=0 # For when original H.264 deletion fails
failed_temp_deletions=0   # For when temp H.265 (not smaller) deletion fails

# --- Prepare for File Processing ---
IFS_BAK=$IFS
IFS=$'\n' # Handle filenames with spaces correctly

# Build find command options for extensions
find_cmd_opts=()
if [ ${#VIDEO_EXTENSIONS[@]} -gt 0 ]; then
    for ext in "${VIDEO_EXTENSIONS[@]}"; do
        if [ ${#find_cmd_opts[@]} -eq 0 ]; then
            find_cmd_opts+=(-iname "*.$ext")
        else
            find_cmd_opts+=(-o -iname "*.$ext")
        fi
    done
else
    log_message "$LOG_LEVEL_ERROR" "VIDEO_EXTENSIONS array is empty. Cannot find files."
    echo "ERROR: VIDEO_EXTENSIONS array is empty. Cannot find files. Check config or -e option."
    exit 1
fi

if [ ${#find_cmd_opts[@]} -eq 0 ]; then
    log_message "$LOG_LEVEL_ERROR" "No valid file extensions criteria for find. Check VIDEO_EXTENSIONS."
    echo "ERROR: No valid file extensions. Check VIDEO_EXTENSIONS."
    exit 1
fi

# Populate file list
file_list=()
log_message "$LOG_LEVEL_DEBUG" "Searching for files in '$INPUT_DIR' with options: ${find_cmd_opts[*]}"
while IFS= read -r -d $'\0' file; do
    file_list+=("$file")
done < <(find "$INPUT_DIR" -type f \( "${find_cmd_opts[@]}" \) -print0 | sort -z)

total_files_checked=${#file_list[@]}
log_message "$LOG_LEVEL_INFO" "Found $total_files_checked potential video file(s) to check (sorted alphabetically)."
current_file_number=0

# --- Main Processing Loop ---
for current_file in "${file_list[@]}"; do
    ((current_file_number++))
    CURRENT_TEMP_FILE="" # Reset for each file

    log_message "$LOG_LEVEL_DEBUG" "-----------------------------------------------------"
    log_message "$LOG_LEVEL_INFO" "Processing file $current_file_number of $total_files_checked: $current_file"

    video_codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$current_file")
    log_message "$LOG_LEVEL_DEBUG" "Detected codec for '$current_file': '$video_codec'"

    if [[ "$video_codec" == "h264" ]]; then
        ((h264_files_identified++))
        log_message "$LOG_LEVEL_INFO" "Found H.264 video: $current_file"

        original_size_bytes=$(get_file_size "$current_file")
        if [[ "$original_size_bytes" -eq 0 && -s "$current_file" ]]; then # Fallback if stat failed but file not empty
             original_size_bytes=$(du -b "$current_file" | cut -f1)
             log_message "$LOG_LEVEL_DEBUG" "Used du for original_size_bytes: $original_size_bytes"
        fi
        log_message "$LOG_LEVEL_DEBUG" "Original size: $original_size_bytes bytes"


        original_dir=$(dirname "$current_file")
        base_name=$(basename "$current_file")
        file_name_no_ext="${base_name%.*}"
        
        output_file_name="${file_name_no_ext}_h265.mp4"
        final_output_path="$original_dir/$output_file_name"
        
        # Using PID for basic temp file uniqueness. mktemp is more robust if needed.
        TEMP_OUTPUT_PATH="$original_dir/.tmp_${output_file_name}.$$"
        CURRENT_TEMP_FILE="$TEMP_OUTPUT_PATH" # For signal trap cleanup
        log_message "$LOG_LEVEL_DEBUG" "Target final output: $final_output_path, Temp output: $TEMP_OUTPUT_PATH"

        # Check if target H.265 file already exists
        if [[ -f "$final_output_path" ]]; then
            existing_codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$final_output_path" 2>/dev/null)
            if [[ "$existing_codec" == "hevc" ]]; then
                log_message "$LOG_LEVEL_INFO" "Skipping conversion: Target file '$final_output_path' already exists and is HEVC."
                echo "Skipping, target file '$final_output_path' already exists and is HEVC."
                log_conversion_details "$current_file" "$original_size_bytes" "$final_output_path" "$(get_file_size "$final_output_path")" "SKIPPED_ALREADY_HEVC" "Target HEVC file exists."
                ((skipped_already_hevc++))
                CURRENT_TEMP_FILE="" # No temp file used for this path
                continue # Move to next file in the list
            else
                 log_message "$LOG_LEVEL_WARNING" "Target file '$final_output_path' already exists but is NOT HEVC (codec: $existing_codec). Will attempt to overwrite if conversion proceeds (via temp file)."
                 echo "Warning: Target file '$final_output_path' already exists but is NOT HEVC (codec: $existing_codec). Will attempt to overwrite."
            fi
        fi

        log_message "$LOG_LEVEL_INFO" "Preparing to convert to H.265 (HEVC) using $ENCODER_TYPE..."
        
        ffmpeg_initial_opts=(-hide_banner -loglevel error -stats -y) # -y will overwrite TEMP_OUTPUT_PATH
        ffmpeg_input_specific_opts=()
        ffmpeg_video_encode_opts=()

        if [[ "$ENCODER_TYPE" == "cpu" ]]; then
            ffmpeg_input_specific_opts=(-i "$current_file")
            ffmpeg_video_encode_opts=(
                -c:v libx265 -crf "$QUALITY_VALUE" -preset "$CPU_PRESET"
            )
            log_message "$LOG_LEVEL_DEBUG" "Using CPU preset: $CPU_PRESET, CRF: $QUALITY_VALUE"
        else # gpu
            ffmpeg_input_specific_opts=(
                -hwaccel vaapi 
                -hwaccel_device "$VAAPI_DEVICE" 
                -hwaccel_output_format vaapi
                -i "$current_file"
            )
            ffmpeg_video_encode_opts=(
                -c:v hevc_vaapi 
                -qp "$QUALITY_VALUE"
            )
            log_message "$LOG_LEVEL_DEBUG" "Using GPU (VAAPI), QP: $QUALITY_VALUE. Device: $VAAPI_DEVICE"
        fi

        conversion_status_note=""
        ffmpeg_success=0
        converted_size_bytes=0 # Initialize

        if [[ "$DRY_RUN" -eq 1 ]]; then
            log_message "$LOG_LEVEL_INFO" "DRY RUN: Would attempt ffmpeg conversion of '$current_file' to '$TEMP_OUTPUT_PATH'"
            ffmpeg_success=1 # Simulate successful conversion for dry run
            # Simulate smaller file for testing deletion logic
            if [[ "$original_size_bytes" -gt 0 ]]; then
                converted_size_bytes=$((original_size_bytes / 2))
                if [[ "$converted_size_bytes" -eq 0 ]]; then converted_size_bytes=1; fi # Ensure not zero if original wasn't
            else
                converted_size_bytes=0
            fi
            log_message "$LOG_LEVEL_DEBUG" "DRY RUN: Simulated converted size: $converted_size_bytes"
        else
            # Actual ffmpeg execution
            log_message "$LOG_LEVEL_DEBUG" "Executing ffmpeg: ffmpeg ${ffmpeg_initial_opts[*]} ${ffmpeg_input_specific_opts[*]} ${ffmpeg_video_encode_opts[*]} -c:a copy -c:s copy -map 0 $TEMP_OUTPUT_PATH"
            if ffmpeg "${ffmpeg_initial_opts[@]}" \
               "${ffmpeg_input_specific_opts[@]}" \
               "${ffmpeg_video_encode_opts[@]}" \
               -c:a copy \
               -c:s copy \
               -map 0 \
               "$TEMP_OUTPUT_PATH"; then
                ffmpeg_success=1
                converted_size_bytes=$(get_file_size "$TEMP_OUTPUT_PATH")
                log_message "$LOG_LEVEL_DEBUG" "ffmpeg successful. Temp file size: $converted_size_bytes"
            else
                log_message "$LOG_LEVEL_ERROR" "FFmpeg failed to convert '$current_file' to '$TEMP_OUTPUT_PATH' using $ENCODER_TYPE."
                echo "FFmpeg conversion FAILED for $current_file using $ENCODER_TYPE."
                log_conversion_details "$current_file" "$original_size_bytes" "$TEMP_OUTPUT_PATH" "N/A" "FAILURE_FFMPEG" "FFMPEG process failed"
                ((failed_ffmpeg_conversions++))
                # Cleanup temp file if ffmpeg failed
                if [[ -f "$TEMP_OUTPUT_PATH" ]]; then
                    log_message "$LOG_LEVEL_DEBUG" "Cleaning up failed temp file: $TEMP_OUTPUT_PATH"
                    rm -f "$TEMP_OUTPUT_PATH"
                fi
            fi
        fi # End of DRY_RUN / actual ffmpeg block

        if [[ "$ffmpeg_success" -eq 1 ]]; then
            if [[ "$converted_size_bytes" -gt 0 ]]; then
                if [[ "$converted_size_bytes" -lt "$original_size_bytes" ]]; then
                    log_message "$LOG_LEVEL_INFO" "SUCCESS: Conversion resulted in a smaller file (Original: $original_size_bytes B, New: $converted_size_bytes B)."
                    echo "Conversion successful. New H.265 file is smaller."
                    
                    if [[ "$DRY_RUN" -eq 0 ]]; then
                        if mv -f "$TEMP_OUTPUT_PATH" "$final_output_path"; then
                            log_message "$LOG_LEVEL_INFO" "Successfully moved '$TEMP_OUTPUT_PATH' to '$final_output_path'."
                            CURRENT_TEMP_FILE="" # Temp file is now the final output, no longer "temp" for cleanup
                            
                            log_message "$LOG_LEVEL_WARNING" "DELETING original H.264 file: $current_file"
                            echo "Deleting original H.264 file: $current_file"
                            if rm -f "$current_file"; then
                                log_message "$LOG_LEVEL_INFO" "Successfully deleted original H.264 file: $current_file"
                                conversion_status_note="Original H.264 deleted."
                                log_conversion_details "$current_file (DELETED)" "$original_size_bytes" "$final_output_path" "$converted_size_bytes" "SUCCESS_ORIGINAL_DELETED" "$conversion_status_note"
                                ((successful_conversions_kept++))
                            else
                                log_message "$LOG_LEVEL_ERROR" "Failed to delete original H.264 file: $current_file"
                                ((failed_original_deletions++))
                                conversion_status_note="Original H.264 DELETION FAILED."
                                log_conversion_details "$current_file (DELETE FAILED)" "$original_size_bytes" "$final_output_path" "$converted_size_bytes" "SUCCESS_ORIGINAL_DELETE_FAILED" "$conversion_status_note"
                                # Still counts as a kept H.265 if H.264 deletion failed
                                ((successful_conversions_kept++))
                            fi
                        else
                            log_message "$LOG_LEVEL_ERROR" "Failed to move '$TEMP_OUTPUT_PATH' to '$final_output_path'. Original H.264 file KEPT. Temp file remains."
                            echo "ERROR: Failed to move temp file. Original kept. Temp file: $TEMP_OUTPUT_PATH"
                            # Temp file still exists and CURRENT_TEMP_FILE is still set, trap will clean it if script exits.
                            # Or explicitly clean it here if preferred, but trap should catch it.
                            # Forcing cleanup here to be explicit for this failure case:
                            if [[ -f "$TEMP_OUTPUT_PATH" ]]; then rm -f "$TEMP_OUTPUT_PATH"; fi
                            CURRENT_TEMP_FILE=""
                            ((failed_ffmpeg_conversions++)) # Count as a failure if move fails
                            log_conversion_details "$current_file" "$original_size_bytes" "$TEMP_OUTPUT_PATH (move failed, deleted)" "$converted_size_bytes" "FAILURE_MOVE_TEMP_FILE" "Failed to rename temp file"
                        fi
                    else # DRY RUN
                        log_message "$LOG_LEVEL_INFO" "DRY RUN: Would move '$TEMP_OUTPUT_PATH' to '$final_output_path'."
                        log_message "$LOG_LEVEL_WARNING" "DRY RUN: Would DELETE original H.264 file: $current_file"
                        conversion_status_note="DRY RUN: Original H.264 would be deleted."
                        log_conversion_details "$current_file (DRY_RUN_DELETED)" "$original_size_bytes" "$final_output_path (simulated)" "$converted_size_bytes (simulated)" "DRY_RUN_SUCCESS_ORIGINAL_DELETED" "$conversion_status_note"
                        ((successful_conversions_kept++))
                    fi
                else # Converted is NOT smaller
                    log_message "$LOG_LEVEL_INFO" "Converted file ('$TEMP_OUTPUT_PATH') is NOT smaller (Original: $original_size_bytes B, New: $converted_size_bytes B). Original H.264 file will be kept."
                    echo "Conversion successful, but new H.265 file is NOT smaller. Original will be kept."
                    
                    if [[ "$DRY_RUN" -eq 0 ]]; then
                        log_message "$LOG_LEVEL_WARNING" "DELETING newly converted H.265 file (did not save space): $TEMP_OUTPUT_PATH"
                        echo "Deleting newly converted H.265 file (did not save space): $TEMP_OUTPUT_PATH"
                        if rm -f "$TEMP_OUTPUT_PATH"; then
                            log_message "$LOG_LEVEL_INFO" "Successfully deleted non-space-saving H.265 file: $TEMP_OUTPUT_PATH"
                            conversion_status_note="H.265 temp file deleted (was not smaller)."
                            log_conversion_details "$current_file" "$original_size_bytes" "$TEMP_OUTPUT_PATH (DELETED)" "$converted_size_bytes" "REVERTED_H265_DELETED_NOT_SMALLER" "$conversion_status_note"
                            ((reverted_conversions_not_smaller++))
                        else
                            log_message "$LOG_LEVEL_ERROR" "Failed to delete non-space-saving H.265 file: $TEMP_OUTPUT_PATH"
                            ((failed_temp_deletions++))
                            conversion_status_note="H.265 temp file (not smaller) DELETION FAILED."
                            log_conversion_details "$current_file" "$original_size_bytes" "$TEMP_OUTPUT_PATH (DELETE FAILED)" "$converted_size_bytes" "REVERTED_H265_DELETE_FAILED_NOT_SMALLER" "$conversion_status_note"
                            # Still counts as reverted as the H.265 wasn't kept, even if deletion of temp failed.
                            ((reverted_conversions_not_smaller++))
                        fi
                    else # DRY RUN
                        log_message "$LOG_LEVEL_WARNING" "DRY RUN: Would DELETE newly converted H.265 file (did not save space): $TEMP_OUTPUT_PATH"
                        conversion_status_note="DRY RUN: H.265 file would be deleted (was not smaller)."
                        log_conversion_details "$current_file" "$original_size_bytes" "$TEMP_OUTPUT_PATH (DRY_RUN_DELETED)" "$converted_size_bytes (simulated)" "DRY_RUN_REVERTED_H265_DELETED_NOT_SMALLER" "$conversion_status_note"
                        ((reverted_conversions_not_smaller++))
                    fi
                    CURRENT_TEMP_FILE="" # Temp file actioned (deleted or dry run)
                fi
            else # Converted size is 0 or temp file doesn't exist (even if ffmpeg command reported success in dry run)
                log_message "$LOG_LEVEL_ERROR" "Converted file '$TEMP_OUTPUT_PATH' has zero size or does not exist after ffmpeg process for '$current_file'."
                echo "ERROR: Converted file is empty or missing for '$current_file'."
                log_conversion_details "$current_file" "$original_size_bytes" "$TEMP_OUTPUT_PATH (empty/missing)" "0" "FAILURE_EMPTY_CONVERTED_FILE" "FFMPEG produced empty or no file"
                ((failed_ffmpeg_conversions++))
                if [[ "$DRY_RUN" -eq 0 && -f "$TEMP_OUTPUT_PATH" ]]; then # Clean up empty temp file if it somehow exists
                    log_message "$LOG_LEVEL_DEBUG" "Cleaning up empty/failed temp file: $TEMP_OUTPUT_PATH"
                    rm -f "$TEMP_OUTPUT_PATH"
                fi
                CURRENT_TEMP_FILE=""
            fi
        fi # end if ffmpeg_success
    
    elif [[ -n "$video_codec" ]]; then # Codec identified but not H.264
        log_message "$LOG_LEVEL_INFO" "Skipping non-H.264 video: $current_file (Codec: $video_codec)"
        echo "Skipping, not H.264 (Codec: $video_codec)"
    else # Could not determine video codec
        log_message "$LOG_LEVEL_WARNING" "Skipping file (could not determine video codec or not a recognized video file): $current_file"
        echo "Skipping, could not determine video codec or not a recognized video file: $current_file"
    fi
    # Ensure CURRENT_TEMP_FILE is cleared if it wasn't already handled by logic paths above
    if [[ -n "$CURRENT_TEMP_FILE" && -f "$CURRENT_TEMP_FILE" && "$DRY_RUN" -eq 0 ]]; then
        log_message "$LOG_LEVEL_WARNING" "Orphaned temp file found and cleaned up: $CURRENT_TEMP_FILE"
        rm -f "$CURRENT_TEMP_FILE"
    fi
    CURRENT_TEMP_FILE="" # Final clear for this iteration
done # End of main processing loop

IFS=$IFS_BAK # Restore IFS

# --- Conversion Summary ---
echo ""
log_message "$LOG_LEVEL_INFO" "--- Conversion Summary ---"
summary_lines=(
    "Total files checked: $total_files_checked"
    "H.264 files identified for processing: $h264_files_identified"
    "Successful conversions (H.265 kept, original H.264 deleted or delete failed): $successful_conversions_kept"
    "Reverted (H.265 deleted as not smaller, or delete failed): $reverted_conversions_not_smaller"
    "Failed FFmpeg conversions or critical errors (empty output, move fail): $failed_ffmpeg_conversions"
    "Skipped (target H.265 file already existed as HEVC): $skipped_already_hevc"
    "Failed original H.264 deletions (H.265 was kept): $failed_original_deletions"
    "Failed temp H.265 deletions (H.265 was not smaller): $failed_temp_deletions"
)

for line in "${summary_lines[@]}"; do
    echo "$line"
    log_message "$LOG_LEVEL_INFO" "$line"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
    final_dry_run_msg="DRY RUN COMPLETED. No actual file changes were made."
    echo "$final_dry_run_msg"
    log_message "$LOG_LEVEL_WARNING" "$final_dry_run_msg"
fi
log_message "$LOG_LEVEL_INFO" "Script finished."
echo "--------------------------"
# Trap will call cleanup_on_exit automatically here