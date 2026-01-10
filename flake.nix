{
  description = "nixmon - A btop clone written in 100% Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Import the nixmon library
        lib = import ./lib { inherit pkgs; };
        
        # Detect platform
        isDarwin = builtins.match ".*-darwin" system != null;
        
        # Shell script that runs the monitor with refresh loop
        nixmonScript = pkgs.writeShellScriptBin "nixmon" ''
          set -uo pipefail
          # Don't use -e (exit on error) as it causes issues with signal handlers and resize events
          
          # Configuration
          REFRESH_RATE=''${NIXMON_REFRESH:-2}
          THEME=''${NIXMON_THEME:-default}
          STATE_FILE="/tmp/nixmon-state-$$.json"
          RUNNING=true
          
          # Interactivity state
          PROCESS_FILTER=""
          SORT_KEY="cpu"
          PROCESS_SORT_REVERSED=false
          SELECTED_PID=""
          PROCESS_SELECTION_INDEX=0
          SHOW_HELP=false
          SHOW_DETAILS=false
          PROCESS_SCROLL_OFFSET=0
          MAX_PROCESS_SCROLL=0
          PREFERRED_NET_IFACE="auto"
          DISK_FILTER=""

          HEADER_HEIGHT=1
          TOP_ROW_HEIGHT=8
          MID_ROW_HEIGHT=7
          INFO_BAR_HEIGHT=1
          PROCESS_MAX_ROWS=0
          PROCESS_LIST_START=0
          INPUT_PENDING=false
          INPUT_PENDING=false
          
          # Configuration file handling
          CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/nixmon"
          CONFIG_FILE="$CONFIG_DIR/nixmon.conf"

          ensure_config() {
            if [ ! -d "$CONFIG_DIR" ]; then
              mkdir -p "$CONFIG_DIR" 2>/dev/null || true
            fi
            if [ ! -f "$CONFIG_FILE" ]; then
              cat > "$CONFIG_FILE" <<'EOF'
          # btop-compatible config keys
          color_theme = "default"
          update_ms = 2000
          proc_sorting = "cpu"
          proc_reversed = false
          net_iface = "auto"
          disk_filter = ""
          EOF
            fi
          }

          parse_bool() {
            case "$1" in
              true|True|TRUE|1|yes|on) echo "true" ;;
              *) echo "false" ;;
            esac
          }

          load_config() {
            if [ -f "$CONFIG_FILE" ]; then
              while IFS= read -r line; do
                line=$(printf '%s' "$line" | sed 's/#.*$//')
                [ -z "$line" ] && continue
                IFS='=' read -r key value <<EOF
          $line
          EOF
                key=$(printf '%s' "$key" | sed 's/[[:space:]]//g')
                value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                value=$(printf '%s' "$value" | sed 's/^"//;s/"$//')
                case "$key" in
                  "") continue ;;
                  color_theme) THEME="$value" ;;
                  update_ms)
                    if [ -n "$value" ]; then
                      REFRESH_RATE=$(echo "$value" | awk '{ms=$1; if(ms<100) ms=100; printf "%.1f", ms/1000}')
                    fi
                    ;;
                  proc_sorting)
                    case "$value" in
                      cpu) SORT_KEY="cpu" ;;
                      memory|mem) SORT_KEY="mem" ;;
                      pid) SORT_KEY="pid" ;;
                      name|command) SORT_KEY="name" ;;
                    esac
                    ;;
                  proc_reversed) PROCESS_SORT_REVERSED=$(parse_bool "$value") ;;
                  net_iface) PREFERRED_NET_IFACE="$value" ;;
                  disk_filter) DISK_FILTER="$value" ;;
                esac
              done < "$CONFIG_FILE" 2>/dev/null || true
            fi
          }

          ensure_config
          load_config
          
          # Save terminal state
          save_terminal() {
            # Save cursor position and stty state
            printf '\e[s'
            STTY_STATE=$(stty -g < /dev/tty 2>/dev/null || echo "")
            # Note: We'll enable alternate screen buffer separately after setup
          }
          
          # Restore terminal state
          restore_terminal() {
            # Restore stty state
            if [ -n "$STTY_STATE" ]; then
              stty "$STTY_STATE" < /dev/tty 2>/dev/null || true
            fi
            # Disable mouse tracking
            printf '\e[?1000l' 2>/dev/null || true
            printf '\e[?1003l' 2>/dev/null || true
            printf '\e[?1006l' 2>/dev/null || true
            # Restore screen contents (exit alternate buffer)
            printf '\e[?1049l' 2>/dev/null || true
            # Restore cursor position
            printf '\e[u' 2>/dev/null || true
            # Show cursor
            printf '\e[?25h'
            # Reset colors
            printf '\e[0m'
          }

          setup_terminal() {
            # Enable alternate screen buffer
            printf '\e[?1049h' 2>/dev/null || true

            # Enable mouse support (if terminal supports it)
            # ?1000h = X10 mouse mode (basic)
            # ?1002h = button-event mouse mode (better)
            # ?1003h = any-event mouse mode (best, includes mouse move)
            # ?1006h = SGR mouse mode (extended coordinates)
            printf '\e[?1006h' 2>/dev/null || true  # Enable SGR mouse mode (best)
            printf '\e[?1003h' 2>/dev/null || true  # Enable any-event mouse mode
            printf '\e[?1000h' 2>/dev/null || true  # Enable basic mouse tracking (fallback)

            # Raw input mode for single key reads
            stty raw -echo -ixon < /dev/tty 2>/dev/null || true

            printf '\e[?25l'  # Hide cursor
            printf '\e[2J\e[H'    # Clear screen and move to top-left
          }

          edit_config() {
            ensure_config
            restore_terminal

            local editor=""
            if [ -n "''${EDITOR:-}" ] && command -v "$EDITOR" >/dev/null 2>&1; then
              editor="$EDITOR"
            elif [ -n "''${VISUAL:-}" ] && command -v "$VISUAL" >/dev/null 2>&1; then
              editor="$VISUAL"
            elif command -v nano >/dev/null 2>&1; then
              editor="nano"
            elif command -v vi >/dev/null 2>&1; then
              editor="vi"
            fi

            if [ -n "$editor" ]; then
              "$editor" "$CONFIG_FILE"
            fi

            setup_terminal
            load_config
          }
          
          # Cleanup on exit
          cleanup() {
            RUNNING=false
            restore_terminal
            rm -f "$STATE_FILE"
            rm -f "$STATIC_DATA_CACHE"
            rm -f /tmp/nixmon-*.txt
            rm -f "/tmp/nixmon-lines-$$.txt"
            rm -f "$RESIZE_FLAG"
            clear
          }
          trap cleanup EXIT INT TERM
          
          # Handle terminal resize
          RESIZE_FLAG="/tmp/nixmon-resize-$$.flag"
          handle_resize() {
            # Signal handlers must be very careful - use minimal code
            # Just set a flag and let the main loop handle the actual work
            touch "$RESIZE_FLAG" 2>/dev/null || true
          }
          trap handle_resize WINCH
          
          # Setup terminal
          save_terminal
          setup_terminal
          
          # Get terminal dimensions
          get_dimensions() {
            # Always use full terminal width
            # Use set +e to prevent exit if tput fails during resize
            set +e
            COLS=$(tput cols 2>/dev/null || echo 80)
            LINES=$(tput lines 2>/dev/null || echo 24)
            set -e
            
            # Ensure we have valid numbers (handle cases where tput returns empty)
            if [ -z "$COLS" ] || ! [ "$COLS" -eq "$COLS" ] 2>/dev/null; then
              COLS=80
            fi
            if [ -z "$LINES" ] || ! [ "$LINES" -eq "$LINES" ] 2>/dev/null; then
              LINES=24
            fi
            
            # Ensure minimum dimensions
            if [ "$COLS" -lt 80 ]; then
              COLS=80
            fi
            if [ "$LINES" -lt 24 ]; then
              LINES=24
            fi
          }

          calculate_layout() {
            local rows
            rows=$((LINES - TOP_ROW_HEIGHT - MID_ROW_HEIGHT - HEADER_HEIGHT - INFO_BAR_HEIGHT - 4))
            if [ "$rows" -lt 0 ]; then
              rows=0
            fi
            PROCESS_MAX_ROWS=$rows
            PROCESS_LIST_START=$((HEADER_HEIGHT + 1 + TOP_ROW_HEIGHT + MID_ROW_HEIGHT + 3))
          }
          
          # Initialize dimensions before starting
          get_dimensions
          calculate_layout
          
          # Initialize state file
          echo '{}' > "$STATE_FILE"
          
          # Cache static data (refreshed only on startup or manual refresh)
          STATIC_DATA_CACHE="/tmp/nixmon-static-$$.json"
          CACHE_TIMESTAMP=0
          CACHE_TTL=300  # 5 minutes
          
          # Collect static data (CPU info, disk mounts) - cached
          collect_static_data() {
            CURRENT_TIME=$(date +%s)
            if [ $((CURRENT_TIME - CACHE_TIMESTAMP)) -lt $CACHE_TTL ] && [ -f "$STATIC_DATA_CACHE" ]; then
              return 0  # Use cached data
            fi
            
            # Collect static info
            ${if isDarwin then ''
              sysctl hw.ncpu hw.memsize machdep.cpu.brand_string hw.cpufrequency 2>/dev/null > /tmp/nixmon-sysctl-static.txt || true
            '' else ''
              # Linux static data is read directly from /proc
              true
            ''}
            
            CACHE_TIMESTAMP=$CURRENT_TIME
          }
          
          # Parse mouse event
          # Supports both SGR format (\e[<button;x;yM) and legacy format (\e[M<button;x;y)
          parse_mouse_event() {
            local seq="$1"
            local button x y action_type

            # SGR format: \e[<button;x;yM or \e[<button;x;ym
            if [[ "$seq" == *$'\e[<'* ]]; then
              local rest="''${seq#*$'\e[<'}"
              local payload="''${rest%%[mM]*}"
              local terminator="''${rest#''${payload}}"
              terminator="''${terminator:0:1}"
              if [ -z "$payload" ] || [ -z "$terminator" ]; then
                return 1
              fi
              button="''${payload%%;*}"
              local remainder="''${payload#*;}"
              x="''${remainder%%;*}"
              y="''${remainder#*;}"
              action_type=$button

            # Legacy format: \e[M button+x+y (encoded)
            elif [[ "$seq" == *$'\e[M'* ]]; then
              # Extract encoded values
              local tail="''${seq#*$'\e[M'}"
              local button_char="''${tail:0:1}"
              local x_char="''${tail:1:1}"
              local y_char="''${tail:2:1}"
              button=$(printf '%d' "'$button_char")
              x=$(printf '%d' "'$x_char")
              y=$(printf '%d' "'$y_char")
              # Legacy encoding: subtract 32 from button and coordinates
              action_type=$((button - 32))
              x=$((x - 32))
              y=$((y - 32))
            else
              return 1
            fi
            
            # Button encoding for SGR:
            # 0=mouse1 press, 1=mouse2 press, 2=mouse3 press
            # 32=mouse1 drag, 33=mouse2 drag, 34=mouse3 drag
            # 64=scroll up, 65=scroll down
            # 96=scroll left, 97=scroll right
            # m suffix = release (we check for M vs m in the sequence)
            
            # Handle scroll (64-65 for up/down, 96-97 for left/right)
            if [ "$action_type" -ge 64 ] && [ "$action_type" -le 97 ]; then
              if [ "$action_type" -eq 64 ] || [ "$action_type" -eq 96 ]; then
                # Scroll up/left - scroll process list up
                if [ "$PROCESS_SCROLL_OFFSET" -gt 0 ]; then
                  PROCESS_SCROLL_OFFSET=$((PROCESS_SCROLL_OFFSET - 1))
                fi
              elif [ "$action_type" -eq 65 ] || [ "$action_type" -eq 97 ]; then
                # Scroll down/right - scroll process list down
                if [ "$PROCESS_SCROLL_OFFSET" -lt "$MAX_PROCESS_SCROLL" ]; then
                  PROCESS_SCROLL_OFFSET=$((PROCESS_SCROLL_OFFSET + 1))
                fi
              fi
              return 0
            fi
            
            # Handle clicks in process list area
            if [ "$action_type" -lt 64 ]; then
              if [ "$SHOW_HELP" = "false" ] && [ "$SHOW_DETAILS" = "false" ] && [ -n "$y" ] && [ "$y" -ge "$PROCESS_LIST_START" ]; then
                local row=$((y - PROCESS_LIST_START))
                if [ "$row" -ge 0 ] && [ "$row" -lt "$PROCESS_MAX_ROWS" ]; then
                  PROCESS_SELECTION_INDEX="$row"
                fi
              fi
            fi
            
            return 0
          }
          
          move_selection_up() {
            if [ "$PROCESS_MAX_ROWS" -le 0 ]; then
              return
            fi
            if [ "$PROCESS_SELECTION_INDEX" -gt 0 ]; then
              PROCESS_SELECTION_INDEX=$((PROCESS_SELECTION_INDEX - 1))
            elif [ "$PROCESS_SCROLL_OFFSET" -gt 0 ]; then
              PROCESS_SCROLL_OFFSET=$((PROCESS_SCROLL_OFFSET - 1))
            fi
          }

          move_selection_down() {
            if [ "$PROCESS_MAX_ROWS" -le 0 ]; then
              return
            fi
            local max_index=$((PROCESS_MAX_ROWS - 1))
            if [ "$PROCESS_SELECTION_INDEX" -lt "$max_index" ]; then
              PROCESS_SELECTION_INDEX=$((PROCESS_SELECTION_INDEX + 1))
            elif [ "$PROCESS_SCROLL_OFFSET" -lt "$MAX_PROCESS_SCROLL" ]; then
              PROCESS_SCROLL_OFFSET=$((PROCESS_SCROLL_OFFSET + 1))
            fi
          }

          move_selection_page() {
            local direction="$1"
            local step=5
            local i
            for i in $(seq 1 "$step"); do
              if [ "$direction" = "up" ]; then
                move_selection_up
              else
                move_selection_down
              fi
            done
          }

          # Check for keyboard and mouse input (non-blocking)
          # Returns: 0 if input available, 1 if not
          check_input() {
            if [ -r /dev/tty ]; then
              # Read first byte with tiny timeout
              local input=""
              IFS= read -t 0.05 -r -n 1 -s input < /dev/tty 2>/dev/null || return 1
              
              if [ -z "$input" ]; then
                return 1
              fi

              # Read any queued bytes without blocking
              local extra=""
              while IFS= read -t 0.005 -r -n 1 -s extra < /dev/tty 2>/dev/null; do
                input="$input$extra"
              done
              
              # Check for escape sequence (mouse events start with \e[)
              if [[ "$input" == *$'\e['* ]]; then
                # Check if it's a mouse event
                # SGR format: \e[<button;x;yM
                if [[ "$input" == *$'\e[<'* ]] || [[ "$input" == *$'\e[M'* ]]; then
                  INPUT_PENDING=true
                  parse_mouse_event "$input" && return 0
                elif [ "$input" = $'\e[A' ]; then
                  INPUT_PENDING=true
                  move_selection_up
                  return 0
                elif [ "$input" = $'\e[B' ]; then
                  INPUT_PENDING=true
                  move_selection_down
                  return 0
                elif [ "$input" = $'\e[5~' ]; then
                  INPUT_PENDING=true
                  move_selection_page up
                  return 0
                elif [ "$input" = $'\e[6~' ]; then
                  INPUT_PENDING=true
                  move_selection_page down
                  return 0
                elif [ "$input" = $'\e' ] || [ "$input" = $'\e[' ]; then
                  INPUT_PENDING=true
                  RUNNING=false
                  return 0
                fi
                # Other escape sequences - ignore for now
                return 0
              fi
              
              # Regular keyboard input
              case "$input" in
                q|Q)
                  # Quit
                  INPUT_PENDING=true
                  RUNNING=false
                  return 0
                  ;;
                +|=)
                  # Increase refresh rate
                  INPUT_PENDING=true
                  REFRESH_RATE=$(echo "$REFRESH_RATE" | awk '{new=$1-0.1; if(new<0.1) new=0.1; printf "%.1f", new}')
                  return 0
                  ;;
                -|_)
                  # Decrease refresh rate
                  INPUT_PENDING=true
                  REFRESH_RATE=$(echo "$REFRESH_RATE" | awk '{new=$1+0.1; if(new>10) new=10; printf "%.1f", new}')
                  return 0
                  ;;
                t|T) 
                  # Cycle themes
                  INPUT_PENDING=true
                  case "$THEME" in
                    default) THEME=nord ;;
                    nord) THEME=gruvbox ;;
                    gruvbox) THEME=dracula ;;
                    dracula) THEME=monokai ;;
                    monokai) THEME=solarized ;;
                    *) THEME=default ;;
                  esac
                  return 0
                  ;;
                e|E)
                  # Edit config file
                  INPUT_PENDING=true
                  edit_config
                  return 0
                  ;;
                f|F)
                  # Toggle filter mode - clear filter
                  INPUT_PENDING=true
                  if [ -n "$PROCESS_FILTER" ]; then
                    PROCESS_FILTER=""
                  else
                    # Enter filter mode (will be handled by next input)
                    PROCESS_FILTER=""
                  fi
                  return 0
                  ;;
                s|S)
                  # Cycle sort keys
                  INPUT_PENDING=true
                  case "$SORT_KEY" in
                    cpu) SORT_KEY=mem ;;
                    mem) SORT_KEY=pid ;;
                    pid) SORT_KEY=name ;;
                    *) SORT_KEY=cpu ;;
                  esac
                  return 0
                  ;;
                r|R)
                  # Toggle sort direction
                  INPUT_PENDING=true
                  PROCESS_SORT_REVERSED=$([ "$PROCESS_SORT_REVERSED" = true ] && echo false || echo true)
                  return 0
                  ;;
                $'\n'|$'\r')
                  # Toggle process details overlay
                  INPUT_PENDING=true
                  SHOW_DETAILS=$([ "$SHOW_DETAILS" = true ] && echo false || echo true)
                  return 0
                  ;;
                i|I)
                  INPUT_PENDING=true
                  SHOW_DETAILS=$([ "$SHOW_DETAILS" = true ] && echo false || echo true)
                  return 0
                  ;;
                k|K)
                  # Kill selected process
                  INPUT_PENDING=true
                  if [ -n "$SELECTED_PID" ]; then
                    kill -TERM "$SELECTED_PID" 2>/dev/null || true
                    SELECTED_PID=""
                  fi
                  return 0
                  ;;
                h|H|?)
                  # Toggle help
                  INPUT_PENDING=true
                  SHOW_HELP=$([ "$SHOW_HELP" = true ] && echo false || echo true)
                  return 0
                  ;;
                [0-9])
                  # Process selection by number (if implemented)
                  INPUT_PENDING=true
                  return 0
                  ;;
                *)
                  # If not a control key, treat as filter input
                  # Append to filter and return
                  INPUT_PENDING=true
                  PROCESS_FILTER="${PROCESS_FILTER}${input}"
                  return 0
                  ;;
              esac
                  return 0
                  ;;
                e|E)
                  # Edit config file
                  edit_config
                  return 0
                  ;;
                f|F)
                  # Toggle filter mode - clear filter
                  if [ -n "$PROCESS_FILTER" ]; then
                    PROCESS_FILTER=""
                  else
                    # Enter filter mode (will be handled by next input)
                    PROCESS_FILTER=""
                  fi
                  return 0
                  ;;
                s|S)
                  # Cycle sort keys
                  case "$SORT_KEY" in
                    cpu) SORT_KEY=mem ;;
                    mem) SORT_KEY=pid ;;
                    pid) SORT_KEY=name ;;
                    *) SORT_KEY=cpu ;;
                  esac
                  return 0
                  ;;
                r|R)
                  # Toggle sort direction
                  PROCESS_SORT_REVERSED=$([ "$PROCESS_SORT_REVERSED" = true ] && echo false || echo true)
                  return 0
                  ;;
                $'\n'|$'\r')
                  # Toggle process details overlay
                  SHOW_DETAILS=$([ "$SHOW_DETAILS" = true ] && echo false || echo true)
                  return 0
                  ;;
                i|I)
                  SHOW_DETAILS=$([ "$SHOW_DETAILS" = true ] && echo false || echo true)
                  return 0
                  ;;
                k|K)
                  # Kill selected process
                  if [ -n "$SELECTED_PID" ]; then
                    kill -TERM "$SELECTED_PID" 2>/dev/null || true
                    SELECTED_PID=""
                  fi
                  return 0
                  ;;
                h|H|?)
                  # Toggle help
                  SHOW_HELP=$([ "$SHOW_HELP" = true ] && echo false || echo true)
                  return 0
                  ;;
                [0-9])
                  # Process selection by number (if implemented)
                  # For now, just return
                  return 0
                  ;;
              esac
            fi
            return 1
          }

          extract_state_number() {
            local key="$1"
            local json="$2"
            local value=""
            value=$(printf '%s' "$json" | sed -n "s/.*\"$key\":\([0-9]*\).*/\1/p" | head -n 1)
            if [ -n "$value" ]; then
              printf '%s' "$value"
            fi
          }

          escape_nix_string() {
            printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
          }
          
          # Platform-specific data collection functions
          ${if isDarwin then ''
          collect_darwin_data() {
            # Use cached static data if available, otherwise collect
            if [ -f /tmp/nixmon-sysctl-static.txt ]; then
              cp /tmp/nixmon-sysctl-static.txt /tmp/nixmon-sysctl.txt 2>/dev/null || true
            else
              sysctl hw.ncpu hw.memsize machdep.cpu.brand_string hw.cpufrequency 2>/dev/null > /tmp/nixmon-sysctl.txt || true
            fi
            
            # Batch dynamic data collection (run in parallel where possible)
            {
              # Collect vm_stat data
              vm_stat 2>/dev/null > /tmp/nixmon-vmstat.txt || true
              
              # Collect CPU usage (top -l 1 gives us one sample)
              top -l 1 -n 0 2>/dev/null | /usr/bin/grep "CPU usage" | sed 's/.*: //' | \
                awk -F'[%, ]+' '{print $1, $3, $5}' > /tmp/nixmon-cpu-stats.txt || echo "10 5 85" > /tmp/nixmon-cpu-stats.txt
              
              # Collect disk info
              df -k 2>/dev/null > /tmp/nixmon-df.txt || true
              
              # Collect network stats
              netstat -ib 2>/dev/null > /tmp/nixmon-netstat.txt || true
              
              # Collect process info
              ps aux 2>/dev/null > /tmp/nixmon-ps.txt || true
              
              # Collect load average
              sysctl vm.loadavg 2>/dev/null | sed 's/.*: //' > /tmp/nixmon-load.txt || echo "{ 0.0 0.0 0.0 }" > /tmp/nixmon-load.txt
            } &
            
            # Collect temperature (slower, run separately)
            if command -v osx-cpu-temp &> /dev/null; then
              osx-cpu-temp 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 > /tmp/nixmon-temp.txt || echo "50" > /tmp/nixmon-temp.txt
            else
              echo "50" > /tmp/nixmon-temp.txt
            fi
            
            # Collect battery info
            {
              pmset -g batt 2>/dev/null | grep -E 'InternalBattery|AC Power' > /tmp/nixmon-battery.txt || true
              ioreg -l 2>/dev/null | grep -E "CurrentCapacity|MaxCapacity|IsCharging|ExternalConnected" | \
                sed 's/.*"\(.*\)" = \(.*\)/\1=\2/' >> /tmp/nixmon-battery.txt || true
            } &
            
            # Collect uptime (seconds since boot) - cached, only update if needed
            if [ ! -f /tmp/nixmon-uptime.txt ] || [ $(( $(date +%s) - $(stat -f %m /tmp/nixmon-uptime.txt 2>/dev/null || echo 0) )) -gt 60 ]; then
              BOOT_TIME=$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')
              CURRENT_TIME=$(date +%s)
              if [ -n "$BOOT_TIME" ] && [ "$BOOT_TIME" -gt 0 ] 2>/dev/null; then
                echo "$((CURRENT_TIME - BOOT_TIME))" > /tmp/nixmon-uptime.txt
              else
                echo "0" > /tmp/nixmon-uptime.txt
              fi
            fi
            
            # Wait for background jobs
            wait
          }
          '' else ''
          collect_linux_data() {
            # Linux data is read directly from /proc and /sys
            # No need to collect - it's always available
            true
          }
          ''}
          
          # Main loop
          while [ "$RUNNING" = true ]; do
            INPUT_PENDING=false
            # Always refresh dimensions at start of loop (catches resize events)
            # Use set +e to prevent exit on error (tput might fail in some cases)
            set +e
            get_dimensions
            set -e
            calculate_layout
            
            # Check for keyboard input (non-blocking)
            check_input || true

            SKIP_COLLECTION=$INPUT_PENDING
            
            # Collect static data (cached)
            if [ "$SKIP_COLLECTION" = false ]; then
              collect_static_data
              
              # Collect platform-specific dynamic data
              ${if isDarwin then "collect_darwin_data" else "collect_linux_data"}
            fi
            
            # Find flake reference - try multiple methods
            # IMPORTANT: Must check for both flake.nix AND nixmon.nix to ensure it's the right project
            FLAKE_REF=""
            BUILD_TIME_PATH="${self}"
            
            # Method 1: Check if we have a NIXMON_FLAKE_PATH env var (highest priority)
            if [ -n "''${NIXMON_FLAKE_PATH:-}" ] && [ -f "$NIXMON_FLAKE_PATH/flake.nix" ] && [ -f "$NIXMON_FLAKE_PATH/nixmon.nix" ]; then
              FLAKE_REF="$NIXMON_FLAKE_PATH"
            # Method 2: If we're in a git repo with both files, use current directory
            elif [ -f flake.nix ] && [ -f nixmon.nix ] && git rev-parse --git-dir >/dev/null 2>&1; then
              FLAKE_REF="$(pwd)"
            # Method 3: Try to find flake.nix with nixmon.nix in parent directories
            else
              CURRENT_DIR="$(pwd)"
              while [ "$CURRENT_DIR" != "/" ]; do
                if [ -f "$CURRENT_DIR/flake.nix" ] && [ -f "$CURRENT_DIR/nixmon.nix" ]; then
                  FLAKE_REF="$CURRENT_DIR"
                  break
                fi
                CURRENT_DIR="$(dirname "$CURRENT_DIR")"
              done
            fi
            
            # If still no flake ref, use the store path from build time (for installed version)
            # This is the most reliable method for globally installed nixmon
            if [ -z "$FLAKE_REF" ] || [ ! -f "$FLAKE_REF/nixmon.nix" ]; then
              # Check if the build-time path is accessible and has required files
              if [ -d "$BUILD_TIME_PATH/lib" ] && [ -f "$BUILD_TIME_PATH/nixmon.nix" ]; then
                FLAKE_REF="$BUILD_TIME_PATH"
              else
                # Last resort: use build-time path anyway (will show error if invalid)
                FLAKE_REF="$BUILD_TIME_PATH"
              fi
            fi
            
            # Run nix eval to generate the frame and state
            # Using a more efficient expression structure
            # Capture stderr for debugging (only show on first error)
            ERR_FILE="/tmp/nixmon-error-$$.txt"
            OUTPUT=""
            ESCAPED_PROCESS_FILTER=$(escape_nix_string "$PROCESS_FILTER")
            ESCAPED_SORT_KEY=$(escape_nix_string "$SORT_KEY")
            ESCAPED_PREFERRED_NET_IFACE=$(escape_nix_string "$PREFERRED_NET_IFACE")
            ESCAPED_DISK_FILTER=$(escape_nix_string "$DISK_FILTER")
            if OUTPUT=$(${pkgs.nix}/bin/nix eval --raw --impure \
              --expr "let
                pkgs = import ${nixpkgs} { system = \"${system}\"; };
                lib = import \"$FLAKE_REF/lib\" { inherit pkgs; };
                nixmon = import \"$FLAKE_REF/nixmon.nix\" { inherit pkgs lib; };
              in nixmon.render {
                width = $COLS;
                height = $LINES;
                theme = \"$THEME\";
                stateFile = \"$STATE_FILE\";
                processFilter = \"$ESCAPED_PROCESS_FILTER\";
                sortKey = \"$ESCAPED_SORT_KEY\";
                sortReversed = $(if [ "$PROCESS_SORT_REVERSED" = "true" ]; then echo "true"; else echo "false"; fi);
                processScrollOffset = $PROCESS_SCROLL_OFFSET;
                processSelectionIndex = $PROCESS_SELECTION_INDEX;
                showHelp = $(if [ "$SHOW_HELP" = "true" ]; then echo "true"; else echo "false"; fi);
                showProcessDetails = $(if [ "$SHOW_DETAILS" = "true" ]; then echo "true"; else echo "false"; fi);
                selectedPid = $(if [ -n "$SELECTED_PID" ]; then echo "$SELECTED_PID"; else echo "null"; fi);
                preferredNetInterface = \"$ESCAPED_PREFERRED_NET_IFACE\";
                diskFilter = \"$ESCAPED_DISK_FILTER\";
              }" \
              2>"$ERR_FILE" 2>&1); then
              # Success - clear error file
              rm -f "$ERR_FILE" "/tmp/nixmon-error-shown-$$"
            else
              # Error occurred - handle gracefully
              if [ ! -f "/tmp/nixmon-error-shown-$$" ]; then
                echo "Error rendering frame. Details:" >&2
                [ -f "$ERR_FILE" ] && cat "$ERR_FILE" >&2 || true
                echo "FLAKE_REF: $FLAKE_REF" >&2
                touch "/tmp/nixmon-error-shown-$$"
              fi
              rm -f "$ERR_FILE"
              sleep "$REFRESH_RATE"
              continue
            fi
            
            # Split output using awk: everything before marker is frame, after is state
            FRAME=$(printf '%s' "$OUTPUT" | awk '/^__NIXMON_STATE_JSON__$/{exit}1')
            STATE_JSON=$(printf '%s' "$OUTPUT" | awk 'p{print} /^__NIXMON_STATE_JSON__$/{p=1}')
            
            # Render frame line-by-line to eliminate flicker
            # Check if this is a resize - if so, clear screen first
            if [ -f "$RESIZE_FLAG" ]; then
              # Resize occurred - update dimensions and clear screen for fresh render
              get_dimensions || true
              # Ensure alternate screen buffer is active (some terminals disable it on resize)
              printf '\e[?1049h' 2>/dev/null || true
              # Clear screen completely for fresh render
              printf '\e[2J\e[H'
              # Reset previous frame line count to force full redraw
              rm -f "$PREV_FRAME_LINES_FILE"
              # Clear the flag now that we're handling it
              rm -f "$RESIZE_FLAG"
            else
              # Normal render - move cursor to top-left without clearing screen
              printf '\e[H'
            fi
            
            # Count lines in new frame (add 1 if frame doesn't end with newline)
            FRAME_LINES=$(printf '%s\n' "$FRAME" | wc -l | tr -d ' ')
            PREV_FRAME_LINES_FILE="/tmp/nixmon-lines-$$.txt"
            
            # Read previous frame line count (default to screen height)
            if [ -f "$PREV_FRAME_LINES_FILE" ]; then
              PREV_FRAME_LINES=$(cat "$PREV_FRAME_LINES_FILE")
            else
              PREV_FRAME_LINES=$LINES
            fi
            
            # Output each line, overwriting the previous content
            # Use a more efficient method: split into array and iterate
            LINE_NUM=1
            printf '%s\n' "$FRAME" | while IFS= read -r line; do
              # Move to line, clear to end of line, then print new content (no trailing newline)
              printf '\e[%d;1H\e[K%s' "$LINE_NUM" "$line"
              LINE_NUM=$((LINE_NUM + 1))
            done
            # Move cursor to end of last line (don't leave it hanging)
            printf '\e[%d;1H' "$FRAME_LINES"
            
            # Clear any remaining lines from previous frame if new frame is shorter
            if [ "$FRAME_LINES" -lt "$PREV_FRAME_LINES" ]; then
              CLEAR_START=$((FRAME_LINES + 1))
              CLEAR_END=$PREV_FRAME_LINES
              for i in $(seq $CLEAR_START $CLEAR_END); do
                printf '\e[%d;1H\e[K' "$i"
              done
            fi
            
            # Save current frame line count
            echo "$FRAME_LINES" > "$PREV_FRAME_LINES_FILE"
            
            # Save state for next iteration (only if we got valid JSON starting with {)
            if [ -n "$STATE_JSON" ]; then
              FIRST_CHAR=$(printf '%s' "$STATE_JSON" | head -c 1)
              if [ "$FIRST_CHAR" = "{" ]; then
                printf '%s' "$STATE_JSON" > "$STATE_FILE"
              fi
            fi

            if [ -n "$STATE_JSON" ]; then
              NEW_MAX_ROWS=$(extract_state_number "processMaxRows" "$STATE_JSON")
              if [ -n "$NEW_MAX_ROWS" ]; then
                PROCESS_MAX_ROWS="$NEW_MAX_ROWS"
              fi
              NEW_LIST_START=$(extract_state_number "processListStart" "$STATE_JSON")
              if [ -n "$NEW_LIST_START" ]; then
                PROCESS_LIST_START="$NEW_LIST_START"
              fi
              NEW_MAX_SCROLL=$(extract_state_number "processMaxScroll" "$STATE_JSON")
              if [ -n "$NEW_MAX_SCROLL" ]; then
                MAX_PROCESS_SCROLL="$NEW_MAX_SCROLL"
              fi
              NEW_SCROLL=$(extract_state_number "processScrollOffset" "$STATE_JSON")
              if [ -n "$NEW_SCROLL" ]; then
                PROCESS_SCROLL_OFFSET="$NEW_SCROLL"
              fi
              NEW_SELECTED_INDEX=$(extract_state_number "processSelectedIndex" "$STATE_JSON")
              if [ -n "$NEW_SELECTED_INDEX" ]; then
                PROCESS_SELECTION_INDEX="$NEW_SELECTED_INDEX"
              fi
              NEW_SELECTED_PID=$(extract_state_number "processSelectedPid" "$STATE_JSON")
              if [ -n "$NEW_SELECTED_PID" ] && [ "$NEW_SELECTED_PID" -gt 0 ]; then
                SELECTED_PID="$NEW_SELECTED_PID"
              else
                SELECTED_PID=""
              fi
            fi
            
            # Sleep with input checking (allows responsive quit and resize)
            # If resize flag is set during sleep, break early for immediate redraw
            REFRESH_CENTIS=$(echo "$REFRESH_RATE" | awk '{printf "%.0f", $1 * 100}')
        SLEPT=0
        while [ "$SLEPT" -lt "$REFRESH_CENTIS" ] && [ "$RUNNING" = true ]; do
          [ -f "$RESIZE_FLAG" ] && break
          [ "$INPUT_PENDING" = true ] && break
          sleep 0.1
          SLEPT=$((SLEPT + 10))
          check_input || true
        done
          done
        '';

        # Helper function to find flake reference (same logic as main script)
        findFlakeRef = ''
          FLAKE_REF=""
          if [ -f flake.nix ] && git rev-parse --git-dir >/dev/null 2>&1; then
            FLAKE_REF="$(pwd)"
          elif [ -n "''${NIXMON_FLAKE_PATH:-}" ] && [ -f "$NIXMON_FLAKE_PATH/flake.nix" ]; then
            FLAKE_REF="$NIXMON_FLAKE_PATH"
          else
            CURRENT_DIR="$(pwd)"
            while [ "$CURRENT_DIR" != "/" ]; do
              if [ -f "$CURRENT_DIR/flake.nix" ]; then
                FLAKE_REF="$CURRENT_DIR"
                break
              fi
              CURRENT_DIR="$(dirname "$CURRENT_DIR")"
            done
          fi
          if [ -z "$FLAKE_REF" ]; then
            BUILD_TIME_PATH="${self}"
            if [ -d "$BUILD_TIME_PATH/lib" ]; then
              FLAKE_REF="$BUILD_TIME_PATH"
            else
              SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
              if [ -f "$SCRIPT_DIR/../flake.nix" ]; then
                FLAKE_REF="$(readlink -f "$SCRIPT_DIR/..")"
              else
                FLAKE_REF="$BUILD_TIME_PATH"
              fi
            fi
          fi
        '';
        
        # Simple test script to check data collection
        testScript = pkgs.writeShellScriptBin "nixmon-test" ''
          ${findFlakeRef}
          
          echo "Testing nixmon data collection..."
          echo ""
          
          ${pkgs.nix}/bin/nix eval --impure --json \
            --expr "let nixmon = import \"$FLAKE_REF/nixmon.nix\" { pkgs = import ${nixpkgs} { system = \"${system}\"; }; lib = import \"$FLAKE_REF/lib\" { pkgs = import ${nixpkgs} { system = \"${system}\"; }; }; }; in nixmon.testDataCollection" \
            2>/dev/null | ${pkgs.jq}/bin/jq .
          
          echo ""
          echo "System info:"
          ${pkgs.nix}/bin/nix eval --impure --json \
            --expr "let nixmon = import \"$FLAKE_REF/nixmon.nix\" { pkgs = import ${nixpkgs} { system = \"${system}\"; }; lib = import \"$FLAKE_REF/lib\" { pkgs = import ${nixpkgs} { system = \"${system}\"; }; }; }; in nixmon.systemInfo" \
            2>/dev/null | ${pkgs.jq}/bin/jq .
        '';
        
        # Theme preview script
        themeScript = pkgs.writeShellScriptBin "nixmon-themes" ''
          ${findFlakeRef}
          THEME=''${1:-default}
          ${pkgs.nix}/bin/nix eval --raw --impure \
            --expr "let nixmon = import \"$FLAKE_REF/nixmon.nix\" { pkgs = import ${nixpkgs} { system = \"${system}\"; }; lib = import \"$FLAKE_REF/lib\" { pkgs = import ${nixpkgs} { system = \"${system}\"; }; }; }; in nixmon.previewTheme \"$THEME\"" \
            2>/dev/null
        '';
        
        # Export JSON script
        exportJsonScript = pkgs.writeShellScriptBin "nixmon-export-json" ''
          ${findFlakeRef}
          OUTPUT=''${1:-nixmon-export.json}
          ${pkgs.nix}/bin/nix eval --impure --json \
            --expr "let nixmon = import \"$FLAKE_REF/nixmon.nix\" { pkgs = import ${nixpkgs} { system = \"${system}\"; }; lib = import \"$FLAKE_REF/lib\" { pkgs = import ${nixpkgs} { system = \"${system}\"; }; }; }; in nixmon.exportJSON {}" \
            2>/dev/null | ${pkgs.jq}/bin/jq . > "$OUTPUT"
          echo "Exported to $OUTPUT"
        '';
        
        # Export CSV script
        exportCsvScript = pkgs.writeShellScriptBin "nixmon-export-csv" ''
          ${findFlakeRef}
          OUTPUT=''${1:-nixmon-export.csv}
          ${pkgs.nix}/bin/nix eval --raw --impure \
            --expr "let nixmon = import \"$FLAKE_REF/nixmon.nix\" { pkgs = import ${nixpkgs} { system = \"${system}\"; }; lib = import \"$FLAKE_REF/lib\" { pkgs = import ${nixpkgs} { system = \"${system}\"; }; }; }; in nixmon.exportCSV {}" \
            2>/dev/null > "$OUTPUT"
          echo "Exported to $OUTPUT"
        '';

      in {
        packages = {
          default = nixmonScript;
          nixmon = nixmonScript;
          test = testScript;
          themes = themeScript;
          export-json = exportJsonScript;
          export-csv = exportCsvScript;
        };

        apps = {
          default = {
            type = "app";
            program = "${nixmonScript}/bin/nixmon";
          };
          nixmon = {
            type = "app";
            program = "${nixmonScript}/bin/nixmon";
          };
          test = {
            type = "app";
            program = "${testScript}/bin/nixmon-test";
          };
          themes = {
            type = "app";
            program = "${themeScript}/bin/nixmon-themes";
          };
          export-json = {
            type = "app";
            program = "${exportJsonScript}/bin/nixmon-export-json";
          };
          export-csv = {
            type = "app";
            program = "${exportCsvScript}/bin/nixmon-export-csv";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixmonScript
            testScript
            themeScript
            exportJsonScript
            exportCsvScript
            jq
          ];
          
          shellHook = ''
            echo "nixmon development shell"
            echo "  nix run .              - Run nixmon"
            echo "  nix run .#test         - Test data collection"
            echo "  nix run .#themes       - Preview themes"
            echo "  nix run .#export-json  - Export to JSON"
            echo "  nix run .#export-csv   - Export to CSV"
            echo ""
            echo "Environment variables:"
            echo "  NIXMON_THEME=<name>   - Set theme (default, nord, monokai, gruvbox, etc.)"
            echo "  NIXMON_REFRESH=<sec>  - Set refresh rate (default: 2)"
            echo ""
            echo "Configuration: ~/.config/nixmon/nixmon.conf (or $XDG_CONFIG_HOME/nixmon/nixmon.conf)"
          '';
        };
      }
    );
}
