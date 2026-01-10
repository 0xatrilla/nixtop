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
  render = { width ? 80, height ? 24, theme ? "default", stateFile ? "/tmp/nixmon-state.json", processFilter ? "", sortKey ? "cpu", sortReversed ? false, showHelp ? false, showProcessDetails ? false, selectedPid ? null, processScrollOffset ? 0, processSelectionIndex ? 0, preferredNetInterface ? "auto", diskFilter ? "" }:
    let
      # Read previous state
      prevStateResult = readState stateFile;
      prevState = if prevStateResult.success then prevStateResult.value else {};
      
      # Collect all metrics
      cpuMetrics = metrics.cpu.getMetrics { inherit prevState; };
      memMetrics = metrics.memory.getMetrics { inherit prevState; };
      diskMetrics = metrics.disk.getMetrics { inherit prevState; interval = 2; mountFilter = diskFilter; };
      netMetrics = metrics.network.getMetrics { inherit prevState; interval = 2; preferredInterface = preferredNetInterface; };
      procMetrics = metrics.processes.getMetrics { 
        inherit prevState; 
        inherit sortKey sortReversed;
        processFilter = processFilter;
        interval = 2; 
      };
      tempMetrics = metrics.temperature.getMetrics { inherit prevState; };
      batteryMetrics = metrics.battery.getMetrics { inherit prevState; };
      
      # Get system info
      uptime = platform.getUptime;
      loadAvg = platform.getLoadAverage;

      # Layout-derived process viewport sizing
      layout = ui.render.layout;
      topRowHeight = layout.topRowHeight;
      midRowHeight = layout.midRowHeight;
      procHeight = height - topRowHeight - midRowHeight - layout.headerHeight - layout.infoBarHeight;
      maxProcessRows = if procHeight > 4 then procHeight - 4 else 0;
      maxProcessScroll = utils.max [0 ((procMetrics.count or 0) - maxProcessRows)];
      clampedScrollOffset = utils.clamp 0 maxProcessScroll processScrollOffset;

      formattedProcesses = procMetrics.formatted or [];
      visibleProcesses = utils.take maxProcessRows (utils.drop clampedScrollOffset formattedProcesses);
      visibleCount = builtins.length visibleProcesses;
      maxSelectionIndex = if visibleCount > 0 then visibleCount - 1 else 0;
      clampedSelectionIndex = if visibleCount > 0
        then utils.clamp 0 maxSelectionIndex processSelectionIndex
        else 0;
      selectionEntry = if visibleCount > 0 then builtins.elemAt visibleProcesses clampedSelectionIndex else null;
      resolvedSelectedPid = if selectionEntry != null then selectionEntry.pidValue else null;

      # Compute actual top/mid row lengths for click mapping
      cpuWidth = (width * 60) / 100;
      memWidth = width - cpuWidth;
      netWidth = (width * 55) / 100;
      diskWidth = width - netWidth;

      cpuBox = ui.render.renderCpuBox {
        inherit cpuMetrics theme;
        width = cpuWidth - 1;
      };

      memBox = ui.render.renderMemoryBox {
        inherit memMetrics theme;
        width = memWidth;
      };

      netBox = ui.render.renderNetworkBox {
        inherit netMetrics theme;
        width = netWidth - 1;
      };

      diskBox = ui.render.renderDiskBox {
        inherit diskMetrics theme;
        width = diskWidth;
      };

      topRowLines = ui.boxes.splitHorizontal {
        leftContent = cpuBox;
        rightContent = memBox;
        leftWidth = cpuWidth - 1;
        rightWidth = memWidth;
        gap = 0;
      };

      midRowLines = ui.boxes.splitHorizontal {
        leftContent = netBox;
        rightContent = diskBox;
        leftWidth = netWidth - 1;
        rightWidth = diskWidth;
        gap = 0;
      };

      processListStart = layout.headerHeight + builtins.length topRowLines + builtins.length midRowLines + 4;
      
      # Combine state data for persistence
      newState = 
        cpuMetrics.stateData //
        memMetrics.stateData //
        diskMetrics.stateData //
        netMetrics.stateData //
        procMetrics.stateData //
        tempMetrics.stateData //
        batteryMetrics.stateData //
        {
          processCount = procMetrics.count or 0;
          processMaxRows = maxProcessRows;
          processListStart = processListStart;
          processMaxScroll = maxProcessScroll;
          processScrollOffset = clampedScrollOffset;
          processSelectedIndex = clampedSelectionIndex;
          processSelectedPid = if resolvedSelectedPid == null then 0 else resolvedSelectedPid;
        };
      
      # Serialize state for persistence
      stateJson = serializeState newState;
      
      # Render the frame
      frame = ui.render.renderFrame {
        inherit cpuMetrics memMetrics netMetrics diskMetrics procMetrics tempMetrics batteryMetrics;
        inherit width height theme;
        selectedPid = resolvedSelectedPid;
        processScrollOffset = clampedScrollOffset;
      };
      
      # Add header
      header = ui.render.renderHeader { inherit width theme uptime; };
      
      # Help overlay if requested
      helpOverlay = if showHelp then ui.render.renderHelp { inherit width height theme; } else "";
      
      # Process details overlay if process selected
      selectedProcess = if resolvedSelectedPid != null 
        then utils.find (p: p.pid == resolvedSelectedPid) (procMetrics.processes or [])
        else null;
      processDetailsOverlay = if selectedProcess != null && showProcessDetails && !showHelp
        then ui.render.renderProcessDetails { 
          process = selectedProcess; 
          inherit width height theme; 
        }
        else "";
      
      # Special marker to separate frame from state JSON
      # The shell script will split on this marker
    in ''
      ${header}
      ${if showHelp then helpOverlay else if processDetailsOverlay != "" then processDetailsOverlay else frame}
      __NIXMON_STATE_JSON__
      ${stateJson}'';

  # ============================================================================
  # Export Functions
  # ============================================================================
  
  # Export current metrics to JSON
  exportJSON = { stateFile ? "/tmp/nixmon-state.json" }:
    let
      prevStateResult = readState stateFile;
      prevState = if prevStateResult.success then prevStateResult.value else {};
      
      cpuMetrics = metrics.cpu.getMetrics { inherit prevState; };
      memMetrics = metrics.memory.getMetrics { inherit prevState; };
      diskMetrics = metrics.disk.getMetrics { inherit prevState; interval = 2; };
      netMetrics = metrics.network.getMetrics { inherit prevState; interval = 2; };
      procMetrics = metrics.processes.getMetrics { 
        inherit prevState; 
        sortKey = "cpu"; 
        maxProcesses = 50; 
        interval = 2; 
      };
      tempMetrics = metrics.temperature.getMetrics { inherit prevState; };
      batteryMetrics = metrics.battery.getMetrics { inherit prevState; };
      
      exportData = {
        timestamp = builtins.currentTime;
        cpu = {
          overall = cpuMetrics.overall or 0;
          cores = cpuMetrics.cores or [];
          history = cpuMetrics.history or [];
        };
        memory = {
          used = memMetrics.used or 0;
          total = memMetrics.total or 0;
          usedPercent = memMetrics.usedPercent or 0;
        };
        network = {
          primary = netMetrics.primary or {};
          totalRxRate = netMetrics.total.rxRate or 0;
          totalTxRate = netMetrics.total.txRate or 0;
        };
        disk = {
          mounts = diskMetrics.mounts or [];
        };
        processes = {
          count = procMetrics.count or 0;
          top = map (p: {
            pid = p.pid;
            name = p.name;
            cpuPercent = p.cpuPercent or 0;
            memPercent = p.memPercent or 0;
          }) (procMetrics.processes or []);
        };
        temperature = {
          cpu = tempMetrics.cpu.temp or 0;
        };
        battery = batteryMetrics;
      };
      
    in builtins.toJSON exportData;
  
  # Export to CSV format
  exportCSV = { stateFile ? "/tmp/nixmon-state.json" }:
    let
      prevStateResult = readState stateFile;
      prevState = if prevStateResult.success then prevStateResult.value else {};
      
      cpuMetrics = metrics.cpu.getMetrics { inherit prevState; };
      memMetrics = metrics.memory.getMetrics { inherit prevState; };
      procMetrics = metrics.processes.getMetrics { 
        inherit prevState; 
        sortKey = "cpu"; 
        maxProcesses = 50; 
        interval = 2; 
      };
      
      timestamp = builtins.currentTime;
      header = "timestamp,cpu_percent,mem_percent,process_count";
      dataLine = "${toString timestamp},${toString (cpuMetrics.overall or 0)},${toString (memMetrics.usedPercent or 0)},${toString (procMetrics.count or 0)}";
      
    in "${header}\n${dataLine}";
  
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

