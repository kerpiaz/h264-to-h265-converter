#!/bin/bash
set -euo pipefail

# --- Source Libraries ---
# Ensure lib directory is accessible
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/core.sh"

main() {
    # 1. Setup
    trap 'cleanup_on_exit' EXIT SIGINT SIGTERM
    initialize_config "$@"

    # 2. Initialize Log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "--- Log Start $(date '+%Y-%m-%d %H:%M:%S') ---" > "$LOG_FILE"
    
    # 3. Pre-flight checks
    check_dependencies
    
    # 4. User Interaction
    display_welcome_banner
    prompt_for_settings
    prompt_for_input_dir
    display_config_summary
    prompt_for_confirmation
    
    # 5. Core Logic
    # The process_files function will handle the main loop and the final summary display
    process_files
    
    log_message "$LOG_LEVEL_INFO" "Script finished successfully."
}

# --- Execute Main ---
main "$@"