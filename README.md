# nixmon

A system monitor for the terminal, written in pure Nix.

## Features

- CPU usage with per-core breakdown
- Memory and swap monitoring
- Disk usage for mounted filesystems
- Network throughput with historical graphs
- Process list sorted by resource usage
- Temperature sensors
- Battery status
- Multiple color themes

## Requirements

- Nix with flakes enabled
- macOS or Linux

## Usage

Run directly with Nix:

```bash
nix run github:yourusername/nixmon
```

Or clone and run locally:

```bash
git clone https://github.com/yourusername/nixmon.git
cd nixmon
nix run .
```

## Configuration

Environment variables:

- `NIXMON_THEME`: Color theme (default, nord, gruvbox, dracula, monokai, solarized)
- `NIXMON_REFRESH`: Refresh interval in seconds (default: 2)

Example:

```bash
NIXMON_THEME=nord nix run .
```

## Implementation

nixmon is implemented entirely in the Nix language, demonstrating advanced Nix programming techniques including:

- Pure functional data processing
- ANSI terminal rendering
- System metrics collection via `/proc` (Linux) and system commands (macOS)
- State management for delta calculations

## License

MIT

