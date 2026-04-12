#!/bin/bash
#
# build.sh - ZMK Charybdis Firmware Builder
# 
# Interactive build script for Charybdis wireless keyboard firmware
# Features:
#   - PMW3610 driver selection (badjeff/inorichi)
#   - Build format selection (bt/dongle/reset/all)
#   - Timestamped firmware output
#   - Automatic workspace cleanup
#

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

DOCKER_IMAGE="zmkfirmware/zmk-build-arm:stable"
OUTPUT_DIR="firmware"
WEST_YML="config/west.yml"
WEST_YML_BACKUP="${WEST_YML}.backup"
BUILD_YAML="build.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
SELECTED_DRIVER=""
SELECTED_FORMAT=""
BUILD_START_TIME=""

# ============================================================================
# Utility Functions
# ============================================================================

show_banner() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║        ZMK Charybdis Wireless Firmware Builder            ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_step() {
    echo ""
    echo -e "${CYAN}▶${NC} $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# Cleanup Functions
# ============================================================================

cleanup_on_exit() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo ""
        log_error "Build interrupted or failed!"
    fi
    
    # Always restore original west.yml
    if [ -f "$WEST_YML_BACKUP" ]; then
        log_info "Restoring original west.yml..."
        mv "$WEST_YML_BACKUP" "$WEST_YML"
    fi
    
# Clean up workspace directories (including west-managed external modules)
    log_info "Cleaning up workspace..."
    rm -rf zmk modules zephyr bootloader tools .west zmk-pmw3610-driver zmk-split-peripheral-input-relay zmk-input-behavior-listener 2>/dev/null
    
    # If directories still exist (permission issues from Docker), use Docker to clean
    if [ -d ".west" ] || [ -d "zmk" ] || [ -d "modules" ] || [ -d "zephyr" ] || [ -d "bootloader" ] || [ -d "tools" ] || [ -d "zmk-pmw3610-driver" ] || [ -d "zmk-split-peripheral-input-relay" ] || [ -d "zmk-input-behavior-listener" ]; then
        log_info "Using Docker to clean workspace (files created by Docker)..."
        docker run --rm -v "$SCRIPT_DIR:/workspace" -w /workspace \
            "$DOCKER_IMAGE" \
            sh -c "rm -rf zmk modules zephyr bootloader tools .west zmk-pmw3610-driver zmk-split-peripheral-input-relay zmk-input-behavior-listener" 2>/dev/null || true
    fi
    
    if [ $exit_code -eq 0 ]; then
        echo ""
        log_success "Cleanup complete!"
    fi
    
    exit $exit_code
}

# Set trap for cleanup
trap cleanup_on_exit EXIT INT TERM

# ============================================================================
# Requirement Checks
# ============================================================================

check_requirements() {
    log_step "Checking Requirements"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        log_info "Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    log_success "Docker found"
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        log_info "Please start Docker and try again"
        exit 1
    fi
    log_success "Docker daemon is running"
    
    # Check Python3
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 is not installed"
        exit 1
    fi
    log_success "Python3 found"
    
    # Check PyYAML
    if ! python3 -c "import yaml" 2>/dev/null; then
        log_error "PyYAML is not installed"
        log_info "Install with: pip install pyyaml"
        exit 1
    fi
    log_success "PyYAML found"
    
    # Check required files
    if [ ! -f "$BUILD_YAML" ]; then
        log_error "build.yaml not found in current directory"
        exit 1
    fi
    log_success "build.yaml found"
    
    if [ ! -f "$WEST_YML" ]; then
        log_error "config/west.yml not found"
        exit 1
    fi
    log_success "config/west.yml found"
    
    # Check keymap conversion script
    if [ ! -f "scripts/convert_keymap.py" ]; then
        log_error "scripts/convert_keymap.py not found"
        exit 1
    fi
    log_success "Keymap conversion script found"
}

# ============================================================================
# Interactive Prompts
# ============================================================================

prompt_driver() {
    log_step "PMW3610 Driver Selection"
    
    echo "Select the PMW3610 trackball driver to use:"
    echo ""
    echo "  [1] badjeff (default, recommended)"
    echo "      https://github.com/badjeff/zmk-pmw3610-driver"
    echo ""
    echo "  [2] inorichi (alternative)"
    echo "      https://github.com/inorichi/zmk-pmw3610-driver"
    echo ""
    
    while true; do
        read -p "Enter choice [1-2] (default: 1): " choice
        choice=${choice:-1}
        
        case $choice in
            1)
                SELECTED_DRIVER="badjeff"
                log_success "Selected: badjeff driver"
                break
                ;;
            2)
                SELECTED_DRIVER="inorichi"
                log_success "Selected: inorichi driver"
                break
                ;;
            *)
                log_error "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done
}

prompt_format() {
    log_step "Build Format Selection"
    
    echo "Select which firmware format to build:"
    echo ""
    echo "  [1] bt - Bluetooth/USB (left + right halves)"
    echo "      For wireless connection or USB, right side is central"
    echo ""
    echo "  [2] dongle - Dongle mode (left + right + dongle)"
    echo "      Requires extra MCU, better battery life for central"
    echo ""
    echo "  [3] reset - Settings reset only"
    echo "      Factory reset firmware for troubleshooting"
    echo ""
    echo "  [4] all - Build everything"
    echo "      All variants (QWERTY, Colemak, BT, Dongle, Reset)"
    echo ""
    
    while true; do
        read -p "Enter choice [1-4] (default: 1): " choice
        choice=${choice:-1}
        
        case $choice in
            1)
                SELECTED_FORMAT="bt"
                log_success "Selected: Bluetooth/USB mode"
                break
                ;;
            2)
                SELECTED_FORMAT="dongle"
                log_success "Selected: Dongle mode"
                break
                ;;
            3)
                SELECTED_FORMAT="reset"
                log_success "Selected: Settings reset"
                break
                ;;
            4)
                SELECTED_FORMAT="all"
                log_success "Selected: Build all variants"
                break
                ;;
            *)
                log_error "Invalid choice. Please enter 1-4."
                ;;
        esac
    done
}

show_build_plan() {
    log_step "Build Plan Summary"
    
    echo "Driver:      ${SELECTED_DRIVER}"
    echo "Format:      ${SELECTED_FORMAT}"
    echo "Output:      ${OUTPUT_DIR}/"
    echo "Timestamp:   ${TIMESTAMP}"
    echo ""
    
    # Parse and show what will be built
    local targets=$(python3 - <<EOF
import yaml
import sys

with open('${BUILD_YAML}', 'r') as f:
    data = yaml.safe_load(f)

entries = data.get('include', [])
selected_format = '${SELECTED_FORMAT}'

count = 0
for entry in entries:
    fmt = entry.get('format', '')
    artifact = entry.get('artifact-name', 'unknown')
    
    if selected_format == 'all' or fmt == selected_format:
        print(f"  - {artifact}")
        count += 1

print(f"\nTotal targets: {count}", file=sys.stderr)
EOF
)
    
    echo "Targets to build:"
    echo "$targets"
    echo ""
}

confirm_build() {
    while true; do
        read -p "Proceed with build? [Y/n]: " confirm
        confirm=${confirm:-Y}
        
        case $confirm in
            [Yy]*)
                return 0
                ;;
            [Nn]*)
                log_info "Build cancelled by user"
                exit 0
                ;;
            *)
                log_error "Please answer Y or N"
                ;;
        esac
    done
}

# ============================================================================
# West.yml Manipulation
# ============================================================================

backup_west_yml() {
    log_info "Backing up west.yml..."
    cp "$WEST_YML" "$WEST_YML_BACKUP"
}

update_driver_in_west_yml() {
    if [ "$SELECTED_DRIVER" = "inorichi" ]; then
        log_info "Updating west.yml to use inorichi driver..."
        
        python3 - <<EOF
import yaml

# Read west.yml
with open('${WEST_YML}', 'r') as f:
    data = yaml.safe_load(f)

# Update remote for zmk-pmw3610-driver
manifest = data.get('manifest', {})

# Add inorichi remote if not exists
remotes = manifest.get('remotes', [])
has_inorichi = any(r.get('name') == 'inorichi' for r in remotes)
if not has_inorichi:
    remotes.append({
        'name': 'inorichi',
        'url-base': 'https://github.com/inorichi'
    })

# Update zmk-pmw3610-driver project to use inorichi remote
projects = manifest.get('projects', [])
for project in projects:
    if project.get('name') == 'zmk-pmw3610-driver':
        project['remote'] = 'inorichi'

# Write back
with open('${WEST_YML}', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False)

print("Updated west.yml to use inorichi driver")
EOF
        
        log_success "Driver updated in west.yml"
    fi
}

# ============================================================================
# Keymap Conversion
# ============================================================================

convert_keymaps() {
    log_step "Converting Keymaps"
    
    # Always generate QWERTY (from base charybdis.keymap)
    log_info "Generating QWERTY keymap..."
    python3 scripts/convert_keymap.py -c q2c --in-path "$SCRIPT_DIR/config/charybdis.keymap"
    log_success "QWERTY keymap generated"
    
    # Generate Colemak if building all or dongle (which has colemak variants)
    if [ "$SELECTED_FORMAT" = "all" ]; then
        log_info "Generating Colemak DH keymap..."
        python3 scripts/convert_keymap.py -c c2q --in-path "$SCRIPT_DIR/config/charybdis.keymap"
        log_success "Colemak DH keymap generated"
    fi
}

# ============================================================================
# Build Matrix Parsing
# ============================================================================

get_build_targets() {
    python3 - <<EOF
import yaml
import json

with open('${BUILD_YAML}', 'r') as f:
    data = yaml.safe_load(f)

entries = data.get('include', [])
selected_format = '${SELECTED_FORMAT}'

targets = []
for entry in entries:
    fmt = entry.get('format', '')
    
    # Filter based on selected format
    if selected_format == 'all' or fmt == selected_format:
        targets.append(entry)

# Output as JSON for bash to parse
print(json.dumps(targets))
EOF
}

# ============================================================================
# Workspace Cleanup (Pre-Build)
# ============================================================================

cleanup_workspace() {
    log_info "Cleaning workspace before build..."
    
    # List of directories to clean (including west-managed external modules)
    local dirs="zmk modules zephyr bootloader tools .west zmk-pmw3610-driver zmk-split-peripheral-input-relay zmk-input-behavior-listener"
    
    # Check if any workspace directories exist
    local needs_cleanup=false
    for dir in $dirs; do
        if [ -d "$dir" ]; then
            needs_cleanup=true
            break
        fi
    done
    
    if [ "$needs_cleanup" = true ]; then
        # Try to remove normally first
        rm -rf $dirs 2>/dev/null || true
        
        # If directories still exist (permission issues from Docker), use Docker to clean
        local still_exists=false
        for dir in $dirs; do
            if [ -d "$dir" ]; then
                still_exists=true
                break
            fi
        done
        
        if [ "$still_exists" = true ]; then
            log_info "Using Docker to clean workspace (files created by Docker)..."
            docker run --rm -v "$SCRIPT_DIR:/workspace" -w /workspace \
                "$DOCKER_IMAGE" \
                sh -c "rm -rf $dirs" 2>/dev/null || true
        fi
    fi
    
    log_success "Workspace cleaned"
}

# ============================================================================
# Docker Build Execution
# ============================================================================

run_docker_build() {
    log_step "Starting Docker Build Process"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Pull Docker image
    log_info "Pulling Docker image (this may take a few minutes first time)..."
    docker pull "$DOCKER_IMAGE" > /dev/null 2>&1
    log_success "Docker image ready"
    
    # Get build targets as JSON
    local targets_json=$(get_build_targets)
    local target_count=$(echo "$targets_json" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
    
    if [ "$target_count" -eq 0 ]; then
        log_error "No targets to build!"
        exit 1
    fi
    
    log_info "Building $target_count target(s)..."
    echo ""
    
    # Record start time
    BUILD_START_TIME=$(date +%s)
    
    # Run Docker container with all build steps
    docker run --rm -v "$SCRIPT_DIR:/workspace" -w /workspace \
        -e "TARGETS_JSON=$targets_json" \
        -e "TIMESTAMP=$TIMESTAMP" \
        -e "SELECTED_FORMAT=$SELECTED_FORMAT" \
        "$DOCKER_IMAGE" \
        bash -c '
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Preparing build environment..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Shield setup: replicate GitHub Actions workflow
if [ "$SELECTED_FORMAT" = "bt" ]; then
    echo "Setting up shields for bt format..."
    find /workspace/boards/shields -mindepth 1 -maxdepth 1 ! -name "charybdis-bt" -exec rm -rf {} +
    cp /workspace/config/charybdis-layouts.dtsi /workspace/boards/shields/charybdis-bt/ 2>/dev/null || true
    mkdir -p /workspace/zmk/app/boards/shields
    cp -r /workspace/boards/shields/charybdis-bt /workspace/zmk/app/boards/shields/
fi

if [ "$SELECTED_FORMAT" = "dongle" ]; then
    echo "Setting up shields for dongle format..."
    find /workspace/boards/shields -mindepth 1 -maxdepth 1 ! -name "charybdis-dongle" -exec rm -rf {} +
    cp /workspace/config/charybdis-layouts.dtsi /workspace/boards/shields/charybdis-dongle/ 2>/dev/null || true
    mkdir -p /workspace/zmk/app/boards/shields
    cp -r /workspace/boards/shields/charybdis-dongle /workspace/zmk/app/boards/shields/
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Initializing West workspace..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

west init -l config
echo "[OK] West initialized"

echo ""
echo "Downloading ZMK and modules (this may take several minutes)..."
west update
echo "[OK] Modules downloaded"

echo ""
echo "Fixing PMW3610 driver devicetree bindings..."
# Add missing properties to PMW3610 driver YAML bindings
if [ -f "zmk-pmw3610-driver/dts/bindings/pixart,pmw3610.yml" ]; then
    cat >> zmk-pmw3610-driver/dts/bindings/pixart,pmw3610.yml << 'YAMLEOF'
  cpi:
    type: int
    default: 1000
  evt-type:
    type: int
    default: 2
  x-input-code:
    type: int
    default: 0
  y-input-code:
    type: int
    default: 1
YAMLEOF
    echo "[OK] PMW3610 bindings fixed"
fi

echo ""
echo "Exporting Zephyr..."
west zephyr-export
echo "[OK] Zephyr exported"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Building firmware targets..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Parse targets JSON
targets=$(echo "$TARGETS_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
current=0

echo "$TARGETS_JSON" | python3 -c "
import sys, json, subprocess, os

targets = json.load(sys.stdin)
total = len(targets)
timestamp = os.environ.get('"'"'TIMESTAMP'"'"', '"'"'unknown'"'"')

for idx, entry in enumerate(targets, 1):
    board = entry.get('"'"'board'"'"', '"'"'nice_nano_v2'"'"')
    shield = entry.get('"'"'shield'"'"', '"'"''"'"')
    keymap = entry.get('"'"'keymap'"'"', '"'"''"'"')
    fmt = entry.get('"'"'format'"'"', '"'"''"'"')
    snippet = entry.get('"'"'snippet'"'"', '"'"''"'"')
    artifact = entry.get('"'"'artifact-name'"'"', '"'"'unknown'"'"')
    
    print(f'"'"'[{idx}/{total}] Building {artifact}...'"'"')
    print(f'"'"'  Board: {board}'"'"')
    print(f'"'"'  Shield: {shield}'"'"')
    if keymap:
        print(f'"'"'  Keymap: {keymap}'"'"')
    if fmt:
        print(f'"'"'  Format: {fmt}'"'"')
    if snippet:
        print(f'"'"'  Snippet: {snippet}'"'"')
    print()
    
    # Prepare build directory
    build_dir = f'"'"'/tmp/build-{artifact}'"'"'
    
    # Build west command
    cmd = [
        '"'"'west'"'"', '"'"'build'"'"', '"'"'--pristine'"'"',
        '"'"'-s'"'"', '"'"'zmk/app'"'"',
        '"'"'-d'"'"', build_dir,
        '"'"'-b'"'"', board
    ]
    
    # Add snippet if present
    if snippet:
        cmd.extend(['"'"'-S'"'"', snippet])
    
    # Add CMake args
    cmd.append('"'"'--'"'"')
    cmd.append('"'"'-DZMK_CONFIG=/workspace/config'"'"')
    
    if shield:
        cmd.append(f'"'"'-DSHIELD={shield}'"'"')
    
    # Run build
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print('"'"'[OK] Build successful'"'"')
    except subprocess.CalledProcessError as e:
        print(f'"'"'✗ Build failed!'"'"')
        print(e.stderr)
        sys.exit(1)
    
    # Copy output file
    uf2_src = f'"'"'{build_dir}/zephyr/zmk.uf2'"'"'
    uf2_dst = f'"'"'/workspace/firmware/{artifact}-{timestamp}.uf2'"'"'
    
    if os.path.exists(uf2_src):
        subprocess.run(['"'"'cp'"'"', uf2_src, uf2_dst], check=True)
        size_kb = os.path.getsize(uf2_dst) // 1024
        print(f'"'"'[OK] Saved: firmware/{artifact}-{timestamp}.uf2 ({size_kb} KB)'"'"')
    else:
        print(f'"'"'✗ Warning: Output file not found: {uf2_src}'"'"')
    
    print()
"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All builds complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
'
    
    local build_exit_code=$?
    
    if [ $build_exit_code -ne 0 ]; then
        log_error "Docker build failed!"
        exit 1
    fi
}

# ============================================================================
# Build Summary
# ============================================================================

show_summary() {
    log_step "Build Summary"
    
    # Calculate build time
    local build_end_time=$(date +%s)
    local build_duration=$((build_end_time - BUILD_START_TIME))
    local minutes=$((build_duration / 60))
    local seconds=$((build_duration % 60))
    
    echo ""
    echo "Generated Firmware Files:"
    echo ""
    
    # List all generated .uf2 files
    if ls "$OUTPUT_DIR"/*-${TIMESTAMP}.uf2 1> /dev/null 2>&1; then
        for file in "$OUTPUT_DIR"/*-${TIMESTAMP}.uf2; do
            local filename=$(basename "$file")
            local size_kb=$(($(stat -f%z "$file" 2>/dev/null || stat -c%s "$file") / 1024))
            echo "  📦 $filename (${size_kb} KB)"
        done
    else
        log_warning "No firmware files found!"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Configuration:"
    echo "  Driver:      ${SELECTED_DRIVER}"
    echo "  Format:      ${SELECTED_FORMAT}"
    echo "  Build Time:  ${minutes}m ${seconds}s"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Next Steps:"
    echo "  1. Double-press the reset button on your keyboard"
    echo "  2. The keyboard will mount as NICENANO drive"
    echo "  3. Copy the .uf2 file to the NICENANO drive"
    echo "  4. The keyboard will restart automatically"
    echo ""
    echo "  💡 Tip: If halves don't connect, press reset on both simultaneously"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Consider adding these to .gitignore:"
    echo "     firmware/*.uf2"
    echo "     zmk/"
    echo "     modules/"
    echo "     zephyr/"
    echo "     bootloader/"
    echo "     tools/"
    echo "     .west/"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    # Show banner
    show_banner
    
    # Check requirements
    check_requirements
    
    # Interactive prompts
    prompt_driver
    prompt_format
    
    # Show build plan
    show_build_plan
    
    # Confirm
    confirm_build
    
    # Backup west.yml
    backup_west_yml
    
    # Update driver if needed
    update_driver_in_west_yml
    
    # Convert keymaps
    convert_keymaps
    
    # Clean workspace before build
    cleanup_workspace
    
    # Run Docker build
    run_docker_build
    
    # Show summary
    show_summary
    
    log_success "Build process complete!"
}

# Run main function
main "$@"
