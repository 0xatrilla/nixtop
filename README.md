
<img width="500" height="500" alt="Screenshot 2025-12-16 at 02 15 40" src="https://github.com/user-attachments/assets/6cdb8460-41db-4ad5-9e09-d1d69ae5cd4c" />

# nixmon

A system monitor for the terminal, written in pure Nix. A btop clone that demonstrates advanced Nix programming techniques.

## Features

- CPU usage with per-core breakdown and sparklines
- Memory and swap monitoring with visual progress bars
- Disk usage for mounted filesystems with usage percentages
- Network throughput with historical graphs and interface statistics
- Process list sorted by resource usage with filtering and selection
- Temperature sensors
- Battery status (macOS)
- Multiple color themes (default, nord, gruvbox, dracula, monokai, solarized)
- Auto-resize to fill terminal window
- Mouse support for scrolling and interaction
- Keyboard shortcuts for navigation and control

## Requirements

- Nix with flakes enabled
- macOS or Linux

## Installation

### Quick Install (Recommended)

Install globally so you can run `nixmon` from anywhere, just like `btop`:

```bash
# From the nixmon directory
./install.sh

# Or from anywhere, pointing to the flake
./install.sh /path/to/nixmon

# Or install directly from GitHub (once published)
nix profile install github:yourusername/nixmon#nixmon
```

After installation, simply run:

```bash
nixmon
```

The `nixmon` command will be available in your PATH, just like any other system command.

### Alternative: Run Without Installation

Run directly with Nix (no installation needed):

```bash
# From GitHub (once published)
nix run github:yourusername/nixmon

# Or from local directory
nix run .
```

### Update

```bash
nix profile upgrade nixmon
```

### Uninstall

```bash
nix profile remove nixmon
```

## Configuration

### Environment Variables

- `NIXMON_THEME`: Color theme (default, nord, gruvbox, dracula, monokai, solarized)
- `NIXMON_REFRESH`: Refresh interval in seconds (default: 2)

Example:

```bash
NIXMON_THEME=nord nixmon
```

### Configuration File

Create `~/.config/nixmon/nixmon.conf` (or `$XDG_CONFIG_HOME/nixmon/nixmon.conf`) with btop-style keys:

```
color_theme = "nord"
update_ms = 1500
proc_sorting = "cpu"
proc_reversed = false
net_iface = "auto"
disk_filter = ""
```

`disk_filter` accepts a regex; prefix with `!` to exclude matches.

## Keyboard Shortcuts

- `q`, `Esc` - Quit
- `+`, `=` - Increase refresh rate
- `-`, `_` - Decrease refresh rate
- `t` - Cycle themes
- `e` - Edit config
- `s` - Cycle sort key (CPU/MEM/PID/NAME)
- `r` - Toggle sort order
- `f` - Clear process filter
- `↑`/`↓` - Move process selection
- `Enter`, `i` - Toggle process details
- `k` - Kill selected process
- `h`, `?` - Toggle help overlay

## Mouse Support

- Scroll wheel - Scroll process list
- Click - Select process

## Additional Commands

After installation, several commands are available:

- `nixmon` - Run the system monitor
- `nixmon-themes` - Preview available themes
- `nixmon-export-json` - Export current metrics to JSON
- `nixmon-export-csv` - Export current metrics to CSV

## Implementation

nixmon is implemented entirely in the Nix language, demonstrating advanced Nix programming techniques including:

- Pure functional data processing
- ANSI terminal rendering with Unicode box-drawing characters
- System metrics collection via `/proc` (Linux) and system commands (macOS)
- State management for delta calculations (CPU usage, network speed, etc.)
- Real-time terminal UI with flicker reduction
- Signal handling for terminal resize events
- Mouse event parsing and handling
- Modular architecture with separate modules for UI, metrics, and platform-specific code

## License

MIT

