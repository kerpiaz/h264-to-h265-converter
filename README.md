# H.264 to H.265 Batch Video Converter

This Bash script automates the process of recursively finding H.264 video files within a specified directory and converting them to the H.265 (HEVC) codec. It aims to reduce file sizes while preserving audio and subtitle streams. The script offers options for CPU (libx265) and GPU (VAAPI for AMD/Intel) encoding and includes an automatic file management system based on size reduction.
## Key Features

-   **Recursive Conversion:** Scans a directory and all its subdirectories.
- **H.265 (HEVC) Encoding:** Utilizes `ffmpeg` for efficient video compression.
- **CPU & GPU Encoding:**
    
    - CPU: `libx265` with selectable presets (`fast`, `medium`, `slow`).
        
    - GPU: VAAPI-based `hevc_vaapi` for hardware-accelerated encoding (primarily for AMD and Intel GPUs on Linux). _Note:_ NVIDIA GPU support (e.g., via NVENC) is not currently implemented in this script due to a lack of testing hardware; contributions are _welcome._
        
- **Stream Preservation:** Copies audio and subtitle tracks without re-encoding by default.
    
- **Automatic File Management (Size-Based):**
    
    - If the H.265 converted file is smaller, the original H.264 file is **deleted**.
        
    - If the H.265 file is not smaller, the newly created H.265 file is **deleted**.
        
- **External Configuration:** Settings like quality, default paths, and extensions can be managed via a `convert_h265.conf` file.
    
- **Command-Line Control:** Override configurations with CLI arguments (e.g., dry run, log level, extensions).
    
- **Dry Run Mode:** Simulate the entire process without making any actual file changes or deletions.
    
- **Granular Logging:** Adjustable log levels (DEBUG, INFO, WARNING, ERROR) with detailed conversion records.
    
- **Temporary File Usage:** Conversions are performed on temporary files for increased safety before final file operations.
    
- **Signal Handling:** Attempts to clean up temporary files if the script is interrupted.
    
- **Alphabetical Processing:** Files and folders are processed in a sorted order.
    

## ⚠️ WARNING: Automatic File Deletion

This script **automatically deletes files**.
-   If the new H.265 file is **smaller**, the **original H.264 file is deleted**.
-   If the new H.265 file is **larger or the same size**, the **newly created H.265 file is deleted**.

**Please back up your files or use the `--dry-run` mode first if you are unsure.**

**Ensure you have backups of your media or fully understand this behavior before running the script on important data.** You will be prompted for a final confirmation before any destructive operations begin (unless in dry-run mode).

## Installation & Dependencies

You must install the necessary command-line tools for your operating system before running the script.

### macOS (Homebrew)

First, make sure you have [Homebrew](https://brew.sh/) installed. Then, run the following command in your terminal to install all dependencies:

```shell
brew install ffmpeg mediainfo libva-utils
```

### Linux (Arch)

Use `pacman` to install all dependencies:

```shell
sudo pacman -S ffmpeg mediainfo libva-utils
```

### Linux (Debian / Ubuntu)

Use `apt` to install all dependencies:

```shell
sudo apt-get update
sudo apt-get install ffmpeg mediainfo vainfo
```

## Usage

1.  Make the script executable:
    ```shell
    chmod +x convert_videos.sh
    ```
2.  Run the script:
    ```shell
    ./convert_videos.sh
    ```
3.  Follow the on-screen prompts to select your encoder and target directory.

### Command-Line Options

```
Usage: ./convert_videos.sh [OPTIONS]

Options:
  -c, --config FILE     Path to configuration file (default: ./convert_h265.conf).
  -d, --dry-run         Simulate conversions without actual changes.
  -e, --extensions EXT  Comma-separated list of extensions (e.g., "mp4,mkv").
  -l, --log-level LEVEL Log level: DEBUG, INFO, WARNING, ERROR.
  -h, --help            Display the help message.
```

**For Fedora:**

```
sudo dnf install ffmpeg libva-utils
```

_Note: You might need to enable RPM Fusion repositories for `ffmpeg` on Fedora._

## Configuration

The script can be configured in three ways (in order of precedence: CLI > Config File > Script Defaults):

1. **Command-Line Arguments:** See `Usage` section below.
    
2. **Configuration File:** Create a file named `convert_h265.conf` in the same directory as the script, or specify a custom path using the `-c` option. Example `convert_h265.conf`:
    
    ```
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
    ```
    
3. **Script Defaults:** Hardcoded values within the script if no CLI or config file settings are provided.
    

## Usage

```
./h265_converter_script.sh [OPTIONS]
```

**Available Options:**

- `-c, --config FILE`: Path to a custom configuration file.
    
- `-d, --dry-run`: Simulate conversions and deletions without making any actual changes. Highly recommended for first-time use or testing new configurations.
    
- `-e, --extensions "ext1,ext2"`: Comma-separated list of video extensions to process (e.g., `"mp4,mkv,avi"`). Overrides config file and script defaults.
    
- `-l, --log-level LEVEL`: Set the logging verbosity. Options: `DEBUG`, `INFO`, `WARNING`, `ERROR` (default: `INFO`).
    
- `-h, --help`: Display the help message and exit.
    

The script will interactively ask for:

1. Encoder choice (CPU or GPU).
    
2. CPU preset (if CPU is chosen).
    
3. The root directory to scan for videos.
    
4. Final confirmation before starting (if not in dry-run mode).
    

## Example Workflow

1. **Install Dependencies:** (See Prerequisites)
    
2. **Download Script:** Place `h265_converter_script.sh` in your desired location.
    
3. **Make Executable:** `chmod +x h265_converter_script.sh`
    
4. **(Optional) Create Config File:** Create `convert_h265.conf` to customize defaults.
    
5. **Dry Run (Recommended):**
    
    ```
    ./h265_converter_script.sh -d -l DEBUG
    ```
    
    Review the `conversion_log.txt` (or your custom log file) to see what actions _would_ be taken.
    
6. **Actual Conversion:**
    
    ```
    ./h265_converter_script.sh
    ```
    
    Follow the prompts. Monitor the console output and the log file.
    

## Performance & User Experience

This script was developed to efficiently manage large video libraries.

- **Real-World Test Case:**
    
    - **Input Data:** Over 600GB of H.264 videos.
        
    - **Hardware:** AMD Ryzen 7 5700G with integrated Vega 8 graphics (used for VAAPI GPU encoding).
        
    - **Result:** Achieved approximately **33% reduction** in total file size.
        
    - **Duration:** The process took about half a week of continuous operation.
        

GPU encoding (VAAPI for AMD/Intel) can significantly speed up the conversion process compared to CPU-only encoding, especially on supported hardware. The choice of CPU preset (`fast`, `medium`, `slow`) also impacts speed vs. compression efficiency.

## Disclaimer

This script modifies and deletes files. The author(s) are not responsible for any data loss. **Use at your own risk and always back up important data before running automated file processing tools.**

## Contributing

Suggestions, bug reports, and pull requests are welcome. Please open an issue to discuss any major changes.

- **NVIDIA GPU Support:** Contributions to add and test support for NVIDIA GPUs (e.g., using NVENC via `ffmpeg`) would be particularly appreciated.
