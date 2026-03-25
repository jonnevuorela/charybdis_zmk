#!/bin/bash
#
# build-simple.sh - Simplified ZMK Charybdis Firmware Builder
# 
# A streamlined build script that focuses on reliability and speed.
# Features:
#   - No driver switching (uses badjeff driver only)
#   - Simplified build matrix (BT mode only by default)
#   - Better error handling
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_IMAGE="zmkfirmware/zmk-build-arm:stable"
OUTPUT_DIR="${SCRIPT_DIR}/firmware"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Build failed with exit code $exit_code"
    fi
    exit $exit_code
}
trap cleanup EXIT

check_requirements() {
    log "Checking requirements..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker not found. Please install Docker."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker daemon not running. Please start Docker."
        exit 1
    fi
    
    success "Docker available"
}

setup_workspace() {
    log "Setting up workspace..."
    
    cd "${SCRIPT_DIR}"
    mkdir -p "${OUTPUT_DIR}"
    
    success "Workspace ready"
}

run_docker_build() {
    local board="$1"
    local shield="$2"
    local artifact_name="$3"
    
    log "Building ${artifact_name}..."
    
    docker run --rm \
        -v "${SCRIPT_DIR}:/workspace" \
        -w /workspace \
        "${DOCKER_IMAGE}" \
        bash -c "
            set -e
            
            # Setup environment variables for Zephyr
            export ZEPHYR_BASE=/workspace/zephyr
            export Zephyr_DIR=/workspace/zephyr/share/zephyr-package/cmake
            
            # Initialize west if not already done
            if [ ! -f .west/config ]; then
                echo 'Initializing west workspace...'
                west init -l config
            fi
            
            # Run west update if modules are missing
            if [ ! -d 'modules/lib' ] || [ ! -f 'zephyr/kernel/CMakeLists.txt' ]; then
                echo 'Updating west modules...'
                west update
                west zephyr-export
            fi
            
            # Copy our custom shields to zmk
            echo 'Setting up shields...'
            mkdir -p zmk/app/boards/shields
            cp -r boards/shields/charybdis-bt zmk/app/boards/shields/ 2>/dev/null || true
            
            # Clean build directory
            rm -rf build
            
            # Run the build
            echo 'Starting build...'
            west build --pristine \\
                -s zmk/app \\
                -b ${board} \\
                -d build \\
                -- -DSHIELD=${shield} -DZMK_CONFIG=/workspace/config
            
            # Copy output (use relative path inside Docker)
            if [ -f build/zephyr/zmk.uf2 ]; then
                mkdir -p /workspace/firmware
                cp build/zephyr/zmk.uf2 /workspace/firmware/${artifact_name}-${TIMESTAMP}.uf2
                echo '[OK] Build successful'
            else
                echo '[ERROR] Build output not found'
                exit 1
            fi
        "
    
    if [ $? -eq 0 ]; then
        success "Built ${artifact_name}"
    else
        error "Failed to build ${artifact_name}"
        return 1
    fi
}

build_all() {
    log "Starting builds..."
    local start_time=$(date +%s)
    
    # Pull Docker image
    log "Pulling Docker image..."
    docker pull "${DOCKER_IMAGE}" > /dev/null 2>&1
    success "Docker image ready"
    
    # Build left half
    run_docker_build "nice_nano_v2" "charybdis_left" "charybdis_left"
    
    # Build right half
    run_docker_build "nice_nano_v2" "charybdis_right" "charybdis_right"
    
    # Build settings reset
    run_docker_build "nice_nano_v2" "settings_reset" "settings_reset"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    success "All builds completed in ${duration}s"
}

show_summary() {
    echo ""
    echo "========================================"
    echo "Build Summary"
    echo "========================================"
    echo ""
    
    if ls "${OUTPUT_DIR}"/*-${TIMESTAMP}.uf2 1> /dev/null 2>&1; then
        echo "Generated firmware files:"
        for file in "${OUTPUT_DIR}"/*-${TIMESTAMP}.uf2; do
            local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
            local size_kb=$((size / 1024))
            echo "  - $(basename "$file") (${size_kb}KB)"
        done
    else
        warn "No firmware files found"
    fi
    
    echo ""
    echo "Output directory: ${OUTPUT_DIR}"
    echo ""
    echo "To flash:"
    echo "  1. Double-press reset on your Nice!Nano"
    echo "  2. Copy the .uf2 file to the NICENANO drive"
    echo ""
}

main() {
    cd "${SCRIPT_DIR}"
    
    echo ""
    echo "ZMK Charybdis Simple Builder"
    echo "============================"
    echo ""
    
    check_requirements
    setup_workspace
    build_all
    show_summary
}

main "$@"
