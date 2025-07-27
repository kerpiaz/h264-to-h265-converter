#!/bin/bash

process_files() {
    log_message "$LOG_LEVEL_INFO" "Script processing started."
    
    # --- Initialize Counters ---
    local total_files_checked=0
    local total_files_converted=0
    local total_files_skipped=0
    local total_files_failed=0
    local total_original_size_mb=0
    local total_converted_size_mb=0

    # --- Prepare and loop through files ---
    if [[ -z "$INPUT_DIR" ]]; then
        log_message "$LOG_LEVEL_ERROR" "Input directory is not set. Please provide an input directory using -i or by prompt."
        exit 1
    fi

    log_message "$LOG_LEVEL_INFO" "Searching for video files in '$INPUT_DIR'..."
    local file_list=()
    for ext in "${VIDEO_EXTENSIONS[@]}"; do
        while IFS= read -r -d $'\0' file; do
            file_list+=("$file")
        done < <(find "$INPUT_DIR" -type f -iname "*.$ext" -print0)
    done

    if [[ "${#file_list[@]}" -eq 0 ]]; then
        log_message "$LOG_LEVEL_WARNING" "No video files found in '$INPUT_DIR' with extensions: ${VIDEO_EXTENSIONS[*]}."
        display_final_summary 0 0 0 0 0 0
        return
    fi

    log_message "$LOG_LEVEL_INFO" "Found ${#file_list[@]} video files."

    for current_file in "${file_list[@]}"; do
        total_files_checked=$((total_files_checked + 1))
        local filename=$(basename "$current_file")
        local dirname=$(dirname "$current_file")
        local relative_path="${current_file#$INPUT_DIR/}"
        local output_subdir=$(dirname "$relative_path")
        local output_filename="${filename%.*}.mp4" # Always output to MP4 for H.265
        local output_file="$OUTPUT_DIR/$output_subdir/$output_filename"
        local temp_output_file="${output_file}.temp"

        log_message "$LOG_LEVEL_INFO" "Processing: $current_file"

        # Check if output file already exists and is H.265
        if [[ -f "$output_file" ]]; then
            local output_codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$output_file" 2>/dev/null)
            if [[ "$output_codec" == "hevc" ]]; then
                log_message "$LOG_LEVEL_INFO" "Skipping '$filename': H.265 version already exists."
                total_files_skipped=$((total_files_skipped + 1))
                continue
            fi
        fi

        local original_codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$current_file" 2>/dev/null)
        if [[ "$original_codec" == "hevc" ]]; then
            log_message "$LOG_LEVEL_INFO" "Skipping '$filename': Already H.265. No conversion needed."
            total_files_skipped=$((total_files_skipped + 1))
            continue
        fi

        local original_size=$(get_file_size "$current_file")
        total_original_size_mb=$(echo "scale=2; $total_original_size_mb + ($original_size / 1048576)" | bc -l)

        mkdir -p "$(dirname "$output_file")"

        local ffmpeg_command="ffmpeg -i \"$current_file\" -c:v "
        if [[ "$ENCODER_TYPE" == "cpu" ]]; then
            ffmpeg_command+="libx265 -preset \"$CPU_PRESET\" -crf \"$QUALITY_VALUE\""
        elif [[ "$ENCODER_TYPE" == "gpu" ]]; then
            # Attempt to auto-detect GPU encoder
            if command -v nvidia-smi &> /dev/null && ffmpeg -encoders | grep -q "hevc_nvenc"; then
                ffmpeg_command+="hevc_nvenc -cq \"$QUALITY_VALUE\""
                log_message "$LOG_LEVEL_INFO" "Using NVIDIA NVENC for GPU encoding."
            elif command -v amdgpu_top &> /dev/null && ffmpeg -encoders | grep -q "hevc_amf"; then
                ffmpeg_command+="hevc_amf -qp_i \"$QUALITY_VALUE\" -qp_p \"$QUALITY_VALUE\""
                log_message "$LOG_LEVEL_INFO" "Using AMD AMF for GPU encoding."
            elif ffmpeg -encoders | grep -q "hevc_qsv"; then
                ffmpeg_command+="hevc_qsv -qp \"$QUALITY_VALUE\""
                log_message "$LOG_LEVEL_INFO" "Using Intel QSV for GPU encoding."
            else
                log_message "$LOG_LEVEL_ERROR" "No supported GPU encoder found or detected. Falling back to CPU (libx265)."
                ffmpeg_command+="libx265 -preset \"$CPU_PRESET\" -crf \"$QUALITY_VALUE\""
                ENCODER_TYPE="cpu" # Update for logging
            fi
        fi
        ffmpeg_command+=" -c:a copy -c:s copy -map 0 -y \"$temp_output_file\""

        log_message "$LOG_LEVEL_DEBUG" "FFmpeg command: $ffmpeg_command"

        if [[ "$DRY_RUN" -eq 1 ]]; then
            log_message "$LOG_LEVEL_INFO" "DRY RUN: Would execute: $ffmpeg_command"
            log_message "$LOG_LEVEL_INFO" "DRY RUN: Would move '$temp_output_file' to '$output_file'"
            if [[ "$KEEP_ORIGINALS" -eq 0 ]]; then
                log_message "$LOG_LEVEL_INFO" "DRY RUN: Would delete original '$current_file'"
            fi
            total_files_converted=$((total_files_converted + 1)) # Count as converted in dry run
            continue
        fi

        if eval "$ffmpeg_command"; then
            local converted_size=$(get_file_size "$temp_output_file")
            if [[ "$converted_size" -eq 0 ]]; then
                log_message "$LOG_LEVEL_ERROR" "Conversion failed for '$filename': Output file is empty."
                rm -f "$temp_output_file"
                total_files_failed=$((total_files_failed + 1))
                continue
            fi

            local original_size_mb=$(echo "scale=2; $original_size / 1048576" | bc -l)
            local converted_size_mb=$(echo "scale=2; $converted_size / 1048576" | bc -l)
            local size_diff_percent=$(echo "scale=2; (1 - ($converted_size / $original_size)) * 100" | bc -l)

            log_message "$LOG_LEVEL_INFO" "Successfully converted '$filename'."
            log_message "$LOG_LEVEL_INFO" "Original size: $(printf "%.2f" "$original_size_mb") MB, Converted size: $(printf "%.2f" "$converted_size_mb") MB, Saved: $(printf "%.2f" "$size_diff_percent")%"
            
            total_converted_size_mb=$(echo "scale=2; $total_converted_size_mb + $converted_size_mb" | bc -l)

            mv "$temp_output_file" "$output_file"
            log_message "$LOG_LEVEL_DEBUG" "Moved '$temp_output_file' to '$output_file'."

            if [[ "$KEEP_ORIGINALS" -eq 0 ]]; then
                rm "$current_file"
                log_message "$LOG_LEVEL_INFO" "Deleted original file: '$current_file'."
            else
                log_message "$LOG_LEVEL_INFO" "Kept original file: '$current_file'."
            fi
            total_files_converted=$((total_files_converted + 1))
        else
            log_message "$LOG_LEVEL_ERROR" "FFmpeg conversion failed for '$filename'."
            rm -f "$temp_output_file"
            total_files_failed=$((total_files_failed + 1))
        fi
    done

    display_final_summary "$total_files_checked" "$total_files_converted" "$total_files_skipped" "$total_files_failed" "$total_original_size_mb" "$total_converted_size_mb"
}
export -f process_files