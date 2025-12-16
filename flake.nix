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
          set -euo pipefail
          
          # Configuration
          REFRESH_RATE=''${NIXMON_REFRESH:-2}
          THEME=''${NIXMON_THEME:-default}
          STATE_FILE="/tmp/nixmon-state-$$.json"
          
          # Cleanup on exit
          cleanup() {
            rm -f "$STATE_FILE"
            rm -f /tmp/nixmon-*.txt
            # Show cursor and reset terminal
            printf '\e[?25h\e[0m'
            clear
          }
          trap cleanup EXIT INT TERM
          
          # Hide cursor
          printf '\e[?25l'
          
          # Get terminal dimensions
          get_dimensions() {
            COLS=$(tput cols 2>/dev/null || echo 80)
            LINES=$(tput lines 2>/dev/null || echo 24)
          }
          
          # Initialize state file
          echo '{}' > "$STATE_FILE"
          
          # Platform-specific data collection functions
          ${if isDarwin then ''
          collect_darwin_data() {
            # Collect sysctl data
            sysctl hw.ncpu hw.memsize machdep.cpu.brand_string hw.cpufrequency 2>/dev/null > /tmp/nixmon-sysctl.txt || true
            
            # Collect vm_stat data
            vm_stat 2>/dev/null > /tmp/nixmon-vmstat.txt || true
            
            # Collect CPU usage (top -l 1 gives us one sample)
            # Format: cpu_user cpu_sys cpu_idle
            top -l 1 -n 0 2>/dev/null | /usr/bin/grep "CPU usage" | sed 's/.*: //' | \
              awk -F'[%, ]+' '{print $1, $3, $5}' > /tmp/nixmon-cpu-stats.txt || echo "10 5 85" > /tmp/nixmon-cpu-stats.txt
            
            # Collect disk info
            df -k 2>/dev/null > /tmp/nixmon-df.txt || true
            
            # Collect network stats
            netstat -ib 2>/dev/null > /tmp/nixmon-netstat.txt || true
            
            # Collect process info
            ps aux 2>/dev/null > /tmp/nixmon-ps.txt || true
            
            # Collect temperature (requires osx-cpu-temp or similar)
            # Fall back to a reasonable default if not available
            if command -v osx-cpu-temp &> /dev/null; then
              osx-cpu-temp 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 > /tmp/nixmon-temp.txt
            else
              echo "50" > /tmp/nixmon-temp.txt
            fi
            
            # Collect battery info
            pmset -g batt 2>/dev/null | grep -E 'InternalBattery|AC Power' > /tmp/nixmon-battery.txt || true
            ioreg -l 2>/dev/null | grep -E "CurrentCapacity|MaxCapacity|IsCharging|ExternalConnected" | \
              sed 's/.*"\(.*\)" = \(.*\)/\1=\2/' >> /tmp/nixmon-battery.txt || true
            
            # Collect load average
            sysctl vm.loadavg 2>/dev/null | sed 's/.*: //' > /tmp/nixmon-load.txt || echo "{ 0.0 0.0 0.0 }" > /tmp/nixmon-load.txt
            
            # Collect uptime (seconds since boot)
            BOOT_TIME=$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')
            CURRENT_TIME=$(date +%s)
            if [ -n "$BOOT_TIME" ] && [ "$BOOT_TIME" -gt 0 ] 2>/dev/null; then
              echo "$((CURRENT_TIME - BOOT_TIME))" > /tmp/nixmon-uptime.txt
            else
              echo "0" > /tmp/nixmon-uptime.txt
            fi
          }
          '' else ''
          collect_linux_data() {
            # Linux data is read directly from /proc and /sys
            # No need to collect - it's always available
            true
          }
          ''}
          
          # Main loop
          while true; do
            get_dimensions
            
            # Collect platform-specific data
            ${if isDarwin then "collect_darwin_data" else "collect_linux_data"}
            
            # Clear screen and move cursor to top-left
            printf '\e[H\e[2J'
            
            # Run nix eval to generate the frame and state
            OUTPUT=$(${pkgs.nix}/bin/nix eval --raw --impure \
              --expr "let nixmon = import ${self}/nixmon.nix { pkgs = import ${nixpkgs} { system = \"${system}\"; }; lib = import ${self}/lib { pkgs = import ${nixpkgs} { system = \"${system}\"; }; }; }; in nixmon.render { width = $COLS; height = $LINES; theme = \"$THEME\"; stateFile = \"$STATE_FILE\"; }" \
              2>/dev/null) || { echo "Error rendering frame"; sleep "$REFRESH_RATE"; continue; }
            
            # Split output using awk: everything before marker is frame, after is state
            FRAME=$(printf '%s' "$OUTPUT" | awk '/^__NIXMON_STATE_JSON__$/{exit}1')
            STATE_JSON=$(printf '%s' "$OUTPUT" | awk 'p{print} /^__NIXMON_STATE_JSON__$/{p=1}')
            
            # Display the frame
            printf '%s\n' "$FRAME"
            
            # Save state for next iteration (only if we got valid JSON starting with {)
            if [ -n "$STATE_JSON" ]; then
              FIRST_CHAR=$(printf '%s' "$STATE_JSON" | head -c 1)
              if [ "$FIRST_CHAR" = "{" ]; then
                printf '%s' "$STATE_JSON" > "$STATE_FILE"
              fi
            fi
            
            sleep "$REFRESH_RATE"
          done
        '';

        # Simple test script to check data collection
        testScript = pkgs.writeShellScriptBin "nixmon-test" ''
          echo "Testing nixmon data collection..."
          echo ""
          
          ${pkgs.nix}/bin/nix eval --impure --json \
            --expr "let nixmon = import ${self}/nixmon.nix { pkgs = import ${nixpkgs} { system = \"${system}\"; }; lib = import ${self}/lib { pkgs = import ${nixpkgs} { system = \"${system}\"; }; }; }; in nixmon.testDataCollection" \
            2>/dev/null | ${pkgs.jq}/bin/jq .
          
          echo ""
          echo "System info:"
          ${pkgs.nix}/bin/nix eval --impure --json \
            --expr "let nixmon = import ${self}/nixmon.nix { pkgs = import ${nixpkgs} { system = \"${system}\"; }; lib = import ${self}/lib { pkgs = import ${nixpkgs} { system = \"${system}\"; }; }; }; in nixmon.systemInfo" \
            2>/dev/null | ${pkgs.jq}/bin/jq .
        '';

        # Theme preview script
        themeScript = pkgs.writeShellScriptBin "nixmon-themes" ''
          THEME=''${1:-default}
          ${pkgs.nix}/bin/nix eval --raw --impure \
            --expr "let nixmon = import ${self}/nixmon.nix { pkgs = import ${nixpkgs} { system = \"${system}\"; }; lib = import ${self}/lib { pkgs = import ${nixpkgs} { system = \"${system}\"; }; }; }; in nixmon.previewTheme \"$THEME\"" \
            2>/dev/null
        '';

      in {
        packages = {
          default = nixmonScript;
          nixmon = nixmonScript;
          test = testScript;
          themes = themeScript;
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
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixmonScript
            testScript
            themeScript
            jq
          ];
          
          shellHook = ''
            echo "nixmon development shell"
            echo "  nix run .        - Run nixmon"
            echo "  nix run .#test   - Test data collection"
            echo "  nix run .#themes - Preview themes"
            echo ""
            echo "Environment variables:"
            echo "  NIXMON_THEME=<name>   - Set theme (default, nord, monokai, gruvbox, etc.)"
            echo "  NIXMON_REFRESH=<sec>  - Set refresh rate (default: 2)"
          '';
        };
      }
    );
}
