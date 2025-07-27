#!/bin/bash

display_help() {
    cat << EOF
Usage: convert_videos.sh [OPTIONS]

This script converts H.264 videos to H.265 (HEVC) using ffmpeg.

Options:
  -i <directory>    Input directory containing H.264 videos.
  -o <directory>    Output directory for H.265 videos. (Default: same as input)
  -q <value>        CRF (Constant Rate Factor) value for H.265 encoding (0-51).
                    Lower values mean higher quality and larger file sizes.
                    (Default: 28)
  -e <type>         Encoder type: 'cpu' (libx265) or 'gpu' (nvenc/amf/qsv).
                    (Default: 'cpu')
  -p <preset>       CPU preset for libx265 (e.g., 'medium', 'fast', 'slow').
                    Ignored for GPU encoding. (Default: 'medium')
  -l <level>        Log level: DEBUG, INFO, WARNING, ERROR. (Default: INFO)
  -f <file>         Log file path. (Default: conversion_log.txt)
  -d                Dry run: show commands without executing them.
  -k                Keep original H.264 files after successful conversion.
  -h                Display this help message.

Examples:
  convert_videos.sh -i /path/to/videos -q 26 -e gpu
  convert_videos.sh -i /path/to/videos -e cpu -p slow -d
  convert_videos.sh -h
EOF
}
export -f display_help

display_welcome_banner() {
    echo -e "\n####################################################"
    echo -e "#         H.264 to H.265 Video Conversion        #"
    echo -e "####################################################"
    echo -e "\nThis script will convert H.264 videos to H.265 (HEVC)."
    echo -e "WARNING: By default, original H.264 files will be DELETED after successful conversion."
    echo -e "Use the -k option to keep original files."
    echo -e "Ensure you have sufficient disk space for temporary files."
    echo -e "Press Ctrl+C at any time to abort."
}
export -f display_welcome_banner

prompt_for_settings() {
    if [[ -z "$ENCODER_TYPE" ]]; then
        while true; do
            read -rp "Choose encoder type (cpu/gpu) [cpu]: " ENCODER_TYPE_INPUT
            ENCODER_TYPE_INPUT=${ENCODER_TYPE_INPUT:-"cpu"}
            if [[ "$ENCODER_TYPE_INPUT" == "cpu" || "$ENCODER_TYPE_INPUT" == "gpu" ]]; then
                ENCODER_TYPE="$ENCODER_TYPE_INPUT"
                break
            else
                echo "Invalid encoder type. Please enter 'cpu' or 'gpu'."
            fi
        done
    fi

    if [[ "$ENCODER_TYPE" == "cpu" && -z "$CPU_PRESET" ]]; then
        while true; do
            read -rp "Choose CPU preset (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow) [medium]: " CPU_PRESET_INPUT
            CPU_PRESET_INPUT=${CPU_PRESET_INPUT:-"medium"}
            case "$CPU_PRESET_INPUT" in
                ultrafast|superfast|veryfast|faster|fast|medium|slow|slower|veryslow)
                    CPU_PRESET="$CPU_PRESET_INPUT"
                    break
                    ;;
                *)
                    echo "Invalid CPU preset. Please choose from the list."
                    ;;
            esac
        done
    fi
}
export -f prompt_for_settings

prompt_for_input_dir() {
    if [[ -z "$INPUT_DIR" ]]; then
        while true; do
            read -rp "Enter the input directory containing H.264 videos: " INPUT_DIR_INPUT
            if [[ -d "$INPUT_DIR_INPUT" ]]; then
                INPUT_DIR="$INPUT_DIR_INPUT"
                break
            else
                echo "Directory not found: '$INPUT_DIR_INPUT'. Please enter a valid directory."
            fi
        done
    fi
    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="$INPUT_DIR" # Default output to input if not specified
    fi
}
export -f prompt_for_input_dir

display_config_summary() {
    echo -e "\n--- Configuration Summary ---"
    echo "Input Directory: $INPUT_DIR"
    echo "Output Directory: $OUTPUT_DIR"
    echo "Quality (CRF): $QUALITY_VALUE"
    echo "Encoder Type: $ENCODER_TYPE"
    if [[ "$ENCODER_TYPE" == "cpu" ]]; then
        echo "CPU Preset: $CPU_PRESET"
    fi
    echo "Log Level: $(log_level_to_name "$CURRENT_LOG_LEVEL")"
    echo "Log File: $LOG_FILE"
    echo "Dry Run: $( [[ "$DRY_RUN" -eq 1 ]] && echo "Yes" || echo "No" )"
    echo "Keep Originals: $( [[ "$KEEP_ORIGINALS" -eq 1 ]] && echo "Yes" || echo "No" )"
    echo "Video Extensions: ${VIDEO_EXTENSIONS[*]}"
    echo "-----------------------------"
}
export -f display_config_summary

prompt_for_confirmation() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo -e "\nThis is a DRY RUN. No files will be converted or deleted."
        read -rp "Proceed with dry run? (y/N): " CONFIRMATION
    else
        read -rp "Do you want to proceed with the conversion? (y/N): " CONFIRMATION
    fi

    if [[ ! "$CONFIRMATION" =~ ^[Yy]$ ]]; then
        log_message "$LOG_LEVEL_INFO" "User aborted script."
        echo "Aborting."
        exit 0
    fi
}
export -f prompt_for_confirmation

display_final_summary() {
    local total_files_checked="$1"
    local total_files_converted="$2"
    local total_files_skipped="$3"
    local total_files_failed="$4"
    local total_original_size_mb="$5"
    local total_converted_size_mb="$6"

    echo -e "\n####################################################"
    echo -e "#             Conversion Summary                   #"
    echo -e "####################################################"
    echo "Total files checked: $total_files_checked"
    echo "Total files converted: $total_files_converted"
    echo "Total files skipped: $total_files_skipped"
    echo "Total files failed: $total_files_failed"
    echo "Total original size: $(printf "%.2f" "$total_original_size_mb") MB"
    echo "Total converted size: $(printf "%.2f" "$total_converted_size_mb") MB"
    if (( $(echo "$total_original_size_mb > 0" | bc -l) )); then
        local percentage_saved=$(echo "scale=2; (1 - ($total_converted_size_mb / $total_original_size_mb)) * 100" | bc -l)
        echo "Space saved: $(printf "%.2f" "$percentage_saved")%"
    fi
    echo "####################################################"
}
export -f display_final_summary

# Helper function for display_config_summary
log_level_to_name() {
    case "$1" in
        "$LOG_LEVEL_DEBUG") echo "DEBUG" ;;
        "$LOG_LEVEL_INFO") echo "INFO" ;;
        "$LOG_LEVEL_WARNING") echo "WARNING" ;;
        "$LOG_LEVEL_ERROR") echo "ERROR" ;;
        *) echo "UNKNOWN" ;;
    esac
}
export -f log_level_to_name