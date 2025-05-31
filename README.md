Batch H.264 to H.265 (HEVC) Video Converter

This Bash script automates the process of recursively finding H.264 video files within a specified directory and converting them to the H.265 (HEVC) codec. It aims to reduce file sizes while preserving audio and subtitle streams. The script offers options for CPU (libx265) and GPU (VAAPI for AMD/Intel) encoding and includes an automatic file management system based on size reduction.
Key Features

    Recursive Conversion: Processes videos in the target directory and all its subdirectories.

    H.265 (HEVC) Encoding: Utilizes ffmpeg for efficient video compression.

    CPU & GPU Encoding:

        CPU: libx265 with selectable presets (fast, medium, slow).

        GPU: VAAPI-based hevc_vaapi for hardware-accelerated encoding (primarily for AMD and Intel GPUs on Linux). Note: NVIDIA GPU support (e.g., via NVENC) is not currently implemented in this script due to a lack of testing hardware; contributions are welcome.

    Stream Preservation: Copies audio and subtitle tracks without re-encoding by default.

    Automatic File Management (Size-Based):

        If the H.265 converted file is smaller, the original H.264 file is deleted.

        If the H.265 file is not smaller, the newly created H.265 file is deleted.

    External Configuration: Settings like quality, default paths, and extensions can be managed via a convert_h265.conf file.

    Command-Line Control: Override configurations with CLI arguments (e.g., dry run, log level, extensions).

    Dry Run Mode: Simulate the entire process without making any actual file changes or deletions.

    Granular Logging: Adjustable log levels (DEBUG, INFO, WARNING, ERROR) with detailed conversion records.

    Temporary File Usage: Conversions are performed on temporary files for increased safety before final file operations.

    Signal Handling: Attempts to clean up temporary files if the script is interrupted.

    Alphabetical Processing: Files and folders are processed in a sorted order.

⚠️ WARNING: Automatic File Deletion

This script includes an automatic file deletion feature based on the size comparison between the original H.264 and the converted H.265 file.

    If H.265 is smaller -> ORIGINAL H.264 IS DELETED.

    If H.265 is NOT smaller -> NEW H.265 IS DELETED.

Ensure you have backups of your media or fully understand this behavior before running the script on important data. You will be prompted for a final confirmation before any destructive operations begin (unless in dry-run mode).
Prerequisites

Before running the script, ensure the following dependencies are installed:

    ffmpeg: The core utility for video and audio conversion. For NVIDIA GPU encoding (if contributed), ffmpeg must be compiled with NVENC support.

    ffprobe: Part of the FFmpeg suite, used for media stream analysis.

    vainfo (Recommended for GPU encoding with VAAPI): Utility to check VAAPI status and available codecs. Part of libva-utils or similar packages.

Installation Examples

For Debian/Ubuntu-based systems:

sudo apt update
sudo apt install ffmpeg libva-utils

For Arch Linux-based systems:

sudo pacman -Syu ffmpeg libva-utils

For Fedora:

sudo dnf install ffmpeg libva-utils

Note: You might need to enable RPM Fusion repositories for ffmpeg on Fedora.
Configuration

The script can be configured in three ways (in order of precedence: CLI > Config File > Script Defaults):

    Command-Line Arguments: See Usage section below.

    Configuration File: Create a file named convert_h265.conf in the same directory as the script, or specify a custom path using the -c option. Example convert_h265.conf:

    # Log file path
    LOG_FILE="my_conversion_log.txt"

    # Quality value (CRF for CPU, QP for GPU)
    QUALITY_VALUE=27

    # Default CPU preset if CPU encoding is chosen
    DEFAULT_CPU_PRESET_VALUE="medium"

    # VAAPI device for GPU encoding (AMD/Intel)
    VAAPI_DEVICE="/dev/dri/renderD128" 

    # Comma-separated list of video extensions
    VIDEO_EXTENSIONS_STRING="mkv,mp4,mov"

    # Logging level: DEBUG, INFO, WARNING, ERROR
    CURRENT_LOG_LEVEL_NAME_CONFIG="INFO"

    Script Defaults: Hardcoded values within the script if no CLI or config file settings are provided.

Usage

./h265_converter_script.sh [OPTIONS]

Available Options:

    -c, --config FILE: Path to a custom configuration file.

    -d, --dry-run: Simulate conversions and deletions without making any actual changes. Highly recommended for first-time use or testing new configurations.

    -e, --extensions "ext1,ext2": Comma-separated list of video extensions to process (e.g., "mp4,mkv,avi"). Overrides config file and script defaults.

    -l, --log-level LEVEL: Set the logging verbosity. Options: DEBUG, INFO, WARNING, ERROR (default: INFO).

    -h, --help: Display the help message and exit.

The script will interactively ask for:

    Encoder choice (CPU or GPU).

    CPU preset (if CPU is chosen).

    The root directory to scan for videos.

    Final confirmation before starting (if not in dry-run mode).

Example Workflow

    Install Dependencies: (See Prerequisites)

    Download Script: Place h265_converter_script.sh in your desired location.

    Make Executable: chmod +x h265_converter_script.sh

    (Optional) Create Config File: Create convert_h265.conf to customize defaults.

    Dry Run (Recommended):

    ./h265_converter_script.sh -d -l DEBUG

    Review the conversion_log.txt (or your custom log file) to see what actions would be taken.

    Actual Conversion:

    ./h265_converter_script.sh

    Follow the prompts. Monitor the console output and the log file.

Performance & User Experience

This script was developed to efficiently manage large video libraries.

    Real-World Test Case:

        Input Data: Over 600GB of H.264 videos.

        Hardware: AMD Ryzen 7 5700G with integrated Vega 8 graphics (used for VAAPI GPU encoding).

        Result: Achieved approximately from 1TB SSD 95% full disk down to 65% free space reduction in total file size.

        Duration: The process took about half a week of continuous operation.

GPU encoding (VAAPI for AMD/Intel) can significantly speed up the conversion process compared to CPU-only encoding, especially on supported hardware. The choice of CPU preset (fast, medium, slow) also impacts speed vs. compression efficiency.
Disclaimer

This script modifies and deletes files. The author(s) are not responsible for any data loss. Use at your own risk and always back up important data before running automated file processing tools.
Contributing

Suggestions, bug reports, and pull requests are welcome. Please open an issue to discuss any major changes.

    NVIDIA GPU Support: Contributions to add and test support for NVIDIA GPUs (e.g., using NVENC via ffmpeg) would be particularly appreciated.
