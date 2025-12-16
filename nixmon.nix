# nixmon - Main application entry point
# A btop clone written in 100% Nix
{ pkgs, lib }:

let
  inherit (lib) utils ui platform metrics;

in rec {
  # ============================================================================
  # State Management
  # ============================================================================
  
  # Read previous state from JSON file
  readState = stateFile:
    if builtins.pathExists stateFile
    then let
      content = builtins.readFile stateFile;
      # Only try to parse if content looks like valid JSON (starts with {)
      isValidJson = builtins.stringLength content > 1 && 
                    builtins.substring 0 1 (utils.trim content) == "{";
      parsed = if isValidJson 
               then builtins.tryEval (builtins.fromJSON content)
               else { success = false; value = {}; };
    in if parsed.success then parsed else { success = false; value = {}; }
    else { success = false; value = {}; };

  # Serialize state to JSON string
  serializeState = state:
    builtins.toJSON state;

  # ============================================================================
  # Main Render Function
  # ============================================================================
  
  # Render a single frame of the dashboard
  # This is called by the shell wrapper on each refresh
  render = { width ? 80, height ? 24, theme ? "default", stateFile ? "/tmp/nixmon-state.json" }:
    let
      # Read previous state
      prevStateResult = readState stateFile;
      prevState = if prevStateResult.success then prevStateResult.value else {};
      
      # Collect all metrics
      cpuMetrics = metrics.cpu.getMetrics { inherit prevState; };
      memMetrics = metrics.memory.getMetrics { inherit prevState; };
      diskMetrics = metrics.disk.getMetrics { inherit prevState; interval = 2; };
      netMetrics = metrics.network.getMetrics { inherit prevState; interval = 2; };
      procMetrics = metrics.processes.getMetrics { 
        inherit prevState; 
        sortKey = "cpu"; 
        maxProcesses = 15; 
        interval = 2; 
      };
      tempMetrics = metrics.temperature.getMetrics { inherit prevState; };
      batteryMetrics = metrics.battery.getMetrics { inherit prevState; };
      
      # Get system info
      uptime = platform.getUptime;
      loadAvg = platform.getLoadAverage;
      
      # Combine state data for persistence
      newState = 
        cpuMetrics.stateData //
        memMetrics.stateData //
        diskMetrics.stateData //
        netMetrics.stateData //
        procMetrics.stateData //
        tempMetrics.stateData //
        batteryMetrics.stateData;
      
      # Serialize state for persistence
      stateJson = serializeState newState;
      
      # Render the frame
      frame = ui.render.renderFrame {
        inherit cpuMetrics memMetrics netMetrics diskMetrics procMetrics tempMetrics batteryMetrics;
        inherit width height theme;
      };
      
      # Add header
      header = ui.render.renderHeader { inherit width theme uptime; };
      
      # Special marker to separate frame from state JSON
      # The shell script will split on this marker
    in ''
      ${header}
      ${frame}
      __NIXMON_STATE_JSON__
      ${stateJson}'';

  # ============================================================================
  # Compact Mode (for small terminals)
  # ============================================================================
  
  renderCompact = { width ? 80, theme ? "default", stateFile ? "/tmp/nixmon-state.json" }:
    let
      prevStateResult = readState stateFile;
      prevState = if prevStateResult.success then prevStateResult.value else {};
      
      cpuMetrics = metrics.cpu.getMetrics { inherit prevState; };
      memMetrics = metrics.memory.getMetrics { inherit prevState; };
      netMetrics = metrics.network.getMetrics { inherit prevState; interval = 2; };
      
    in ui.render.renderCompact {
      inherit cpuMetrics memMetrics netMetrics width theme;
    };

  # ============================================================================
  # Theme Preview
  # ============================================================================
  
  # Show available themes
  listThemes = ui.themes.themeNames;

  # Preview a theme's colors
  previewTheme = name:
    let
      theme = ui.themes.getTheme name;
      ansi = ui.ansi;
      
      showColor = colorName: colorValue:
        "${ansi.fgHex colorValue}██${ansi.resetAll} ${colorName}: ${colorValue}";
      
      colorPairs = builtins.attrNames theme.colors;
      
    in ''
      Theme: ${theme.name}
      ${builtins.concatStringsSep "\n" (map (c: showColor c theme.colors.${c}) colorPairs)}
    '';

  # ============================================================================
  # Debug/Info Functions
  # ============================================================================
  
  # Get system info summary
  systemInfo = {
    platform = utils.platformName;
    isLinux = utils.isLinux;
    isDarwin = utils.isDarwin;
    currentSystem = utils.currentSystem;
  };

  # Test data collection
  testDataCollection = {
    cpu = platform.getCpuInfo;
    memory = platform.getMemoryInfo;
    network = platform.getNetworkInfo;
    temperature = platform.getTemperature;
    battery = platform.getBatteryInfo;
    uptime = platform.getUptime;
    loadAvg = platform.getLoadAverage;
  };

  # ============================================================================
  # Version Info
  # ============================================================================
  
  version = "0.1.0";
  
  about = ''
    nixmon v${version}
    A btop clone written in 100% Nix
    
    Platform: ${utils.platformName}
    Themes: ${builtins.concatStringsSep ", " listThemes}
    
    Environment Variables:
      NIXMON_THEME    - Theme name (default: default)
      NIXMON_REFRESH  - Refresh rate in seconds (default: 2)
  '';
}

