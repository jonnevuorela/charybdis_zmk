# ZMK Charybdis Firmware Build Guide

## Quick Start

Run the interactive build script:

```bash
./build.sh
```

The script will guide you through:
1. **PMW3610 Driver Selection** - Choose between badjeff (default) or inorichi driver
2. **Build Format Selection** - Choose bt/dongle/reset/all
3. **Automatic Build** - Docker will handle everything automatically

## Build Formats

### 1. Bluetooth/USB (bt)
- Left and right keyboard halves
- Right side is central (connects to computer)
- Can connect via Bluetooth or USB
- Use this for most setups

### 2. Dongle (dongle)
- Left half, right half, and dongle
- Better battery life for central side
- Requires extra MCU for dongle
- Only connects through dongle

### 3. Reset (reset)
- Settings reset firmware only
- Use when switching between bt/dongle
- Use for troubleshooting connection issues

### 4. All (all)
- Builds all variants (QWERTY, Colemak, BT, Dongle, Reset)
- Takes longer but gives you all options
- Includes commented-out variants in build.yaml

## Output

Firmware files are saved in `firmware/` directory with timestamps:

```
firmware/
├── charybdis_qwerty_left-20260325-143052.uf2
├── charybdis_qwerty_right-20260325-143052.uf2
└── firmware_reset_nano_v2-20260325-143052.uf2
```

## Flashing Instructions

1. **Double-press** the reset button on your keyboard
2. The keyboard will mount as **NICENANO** drive
3. **Copy** the `.uf2` file to the NICENANO drive
4. The keyboard will **restart automatically**

**Tip:** If keyboard halves don't connect, press reset on both simultaneously.

## PMW3610 Drivers

### badjeff (Default, Recommended)
- https://github.com/badjeff/zmk-pmw3610-driver
- More features and active development
- Better power management

### inorichi (Alternative)
- https://github.com/inorichi/zmk-pmw3610-driver
- Simpler implementation
- Good compatibility

## What Happens During Build

1. **Requirements Check** - Verifies Docker, Python, PyYAML
2. **West Workspace Init** - Downloads ZMK and modules
3. **Keymap Conversion** - Generates layout-specific keymaps
4. **Matrix Build** - Builds each target from build.yaml
5. **Output** - Copies .uf2 files to firmware/ with timestamps
6. **Cleanup** - Removes temporary workspace files

## Workspace Cleanup

The script automatically cleans up these directories after build:
- `zmk/` - ZMK source code (~500MB)
- `modules/` - External modules (~100MB)
- `zephyr/` - Zephyr RTOS (~1GB)
- `bootloader/` - Bootloader code
- `tools/` - Build tools
- `.west/` - West metadata

This saves ~2GB of disk space but means next build will re-download.

## Troubleshooting

### Docker daemon not running
```bash
sudo systemctl start docker  # Linux
# or start Docker Desktop on macOS/Windows
```

### PyYAML not installed
```bash
pip install pyyaml
# or
python3 -m pip install pyyaml
```

### Build fails with PMW3610 errors
- Try the alternative driver (inorichi)
- Check that config/west.yml is properly configured
- Ensure you have internet connection for module downloads

### Permission denied on build.sh
```bash
chmod +x build.sh
```

## Recommended .gitignore Additions

Add these to your `.gitignore`:

```
firmware/*.uf2
zmk/
modules/
zephyr/
bootloader/
tools/
.west/
build/
config/*.keymap.backup
```

## Manual Build (Advanced)

If you need to build manually without the interactive script:

```bash
# Convert keymap
python3 scripts/convert_keymap.py -c q2c --in-path "$PWD/config/charybdis.keymap"

# Run build in Docker
docker run --rm -v "$PWD:/workspace" -w /workspace \
  zmkfirmware/zmk-build-arm:stable \
  bash -c "west init -l config && west update && west zephyr-export && \
           west build --pristine -s zmk/app -b nice_nano_v2 -d /tmp/build \
           -- -DZMK_CONFIG=/workspace/config -DSHIELD=charybdis_left \
           -DZMK_EXTRA_MODULES=/workspace && \
           cp /tmp/build/zephyr/zmk.uf2 /workspace/charybdis_left.uf2"
```

## Support

- **ZMK Documentation**: https://zmk.dev/docs
- **Charybdis Build Guide**: https://github.com/280Zo/charybdis-wireless-mini-3x6-build-guide
- **ZMK Discord**: https://zmk.dev/community/discord/invite

## Credits

Based on the excellent work of:
- [280Zo](https://github.com/280Zo) - Original Charybdis ZMK config
- [badjeff](https://github.com/badjeff) - PMW3610 driver and modules
- [eigatech](https://github.com/eigatech) - Driver configuration
- [Pete Johanson](https://github.com/petejohanson) - ZMK pointers feature
