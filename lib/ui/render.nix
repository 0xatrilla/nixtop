# Main rendering engine for nixmon
# Composes all UI components into the final dashboard
{ pkgs, utils, ui }:

let
  ansi = ui.ansi;
  colors = ui.colors;
  themes = ui.themes;
  graphs = ui.graphs;
  boxes = ui.boxes;

in rec {
  # ============================================================================
  # CPU Box
  # ============================================================================
  
  renderCpuBox = { cpuMetrics, width, theme }:
    let
      themeColors = themes.getTheme theme;
      
      overall = cpuMetrics.overall or 0;
      cores = cpuMetrics.cores or [];
      history = cpuMetrics.history or [];
      info = cpuMetrics.formatted or {};
      
      # Header with overall usage and frequency
      freqStr = info.frequency or "";
      headerLine = "${graphs.sparkline { values = history; width = 20; }} ${toString (builtins.floor overall)}%${if freqStr != "" then " @ ${freqStr}" else ""}";
      
      # Per-core bars (2 columns)
      numCores = builtins.length cores;
      coreRows = (numCores + 1) / 2;  # Ceiling division
      
      renderCore = idx:
        if idx >= numCores then ""
        else let
          core = builtins.elemAt cores idx;
          pct = core.pct or 0;
          color = colors.getCpuColor pct;
          label = "Core ${utils.padLeft 2 (toString idx)}";
          barWidth = (width - 4 - 24) / 2;  # Account for borders and spacing
          bar = graphs.horizontalBar { 
            inherit pct; 
            width = barWidth; 
            showPct = false;
            fillColor = color;
          };
          pctStr = utils.padLeft 3 (toString (builtins.floor pct));
        in "${label} ${bar} ${pctStr}%";
      
      makeCoreRow = rowIdx:
        let
          leftIdx = rowIdx * 2;
          rightIdx = leftIdx + 1;
          left = renderCore leftIdx;
          right = renderCore rightIdx;
          spacing = "  ";
        in if right == "" then left
           else "${utils.padRight ((width - 4) / 2) left}${spacing}${right}";
      
      coreLines = builtins.genList makeCoreRow coreRows;
      
      content = [headerLine] ++ coreLines;
      
    in boxes.box {
      inherit content width;
      title = "CPU";
      chars = boxes.rounded;
      titleColor = themeColors.colors.cpu;
      borderColor = themeColors.colors.border;
    };

  # ============================================================================
  # Memory Box (with Swap subsection)
  # ============================================================================
  
  renderMemoryBox = { memMetrics, width, theme }:
    let
      themeColors = themes.getTheme theme;
      
      memory = memMetrics.memory or {};
      swap = memMetrics.swap or {};
      history = memMetrics.history or [];
      
      usedPct = memory.usedPercent or 0;
      swapPct = swap.usedPercent or 0;
      
      # Memory content
      memLine1 = "Used:  ${memory.summary or "0 B / 0 B"}";
      memBar = graphs.percentageBar { 
        pct = usedPct; 
        width = width - 4;
        gradient = colors.memoryGradient;
      };
      memLine3 = "Cached: ${memory.cachedStr or "0 B"}  Avail: ${memory.availableStr or "0 B"}";
      
      mainContent = [memLine1 memBar memLine3];
      
      # Swap content
      swapLine = "Used:   ${swap.summary or "0 B / 0 B"}";
      swapContent = [swapLine];
      
    in boxes.boxWithSubsection {
      inherit mainContent width;
      subContent = swapContent;
      mainTitle = "Memory";
      subTitle = "Swap";
      chars = boxes.rounded;
      titleColor = themeColors.colors.memory;
    };

  # ============================================================================
  # Network Box
  # ============================================================================
  
  renderNetworkBox = { netMetrics, width, theme }:
    let
      themeColors = themes.getTheme theme;
      innerWidth = width - 2;  # Account for box borders
      
      primary = netMetrics.primary or {};
      history = netMetrics.history or { rx = []; tx = []; };
      
      ifName = primary.name or "none";
      rxRate = primary.rxRateStr or "0 B/s";
      txRate = primary.txRateStr or "0 B/s";
      
      # Interface line with rates - pad to innerWidth
      rateContent = "${utils.padRight 6 ifName} ↓ ${utils.padLeft 10 rxRate}  ↑ ${utils.padLeft 10 txRate}";
      rateVisibleLen = 6 + 3 + 10 + 3 + 10;  # visible chars in rateLine
      ratePadding = if innerWidth > rateVisibleLen then innerWidth - rateVisibleLen else 0;
      rateLine = rateContent + utils.repeat ratePadding " ";
      
      # Sparklines for history - calculate exact graph widths
      # Format: ↓<rxGraph> ↑<txGraph>
      # Each arrow+space = 1 char visible, total overhead = 3 (↓ + space + ↑)
      graphWidth = (innerWidth - 3) / 2;
      rxGraph = graphs.sparkline { values = history.rx; width = graphWidth; };
      txGraph = graphs.sparkline { values = history.tx; width = graphWidth; };
      
      # Graph line visible length = 1 + graphWidth + 1 + 1 + graphWidth = 3 + 2*graphWidth
      graphVisibleLen = 3 + (2 * graphWidth);
      graphPadding = if innerWidth > graphVisibleLen then innerWidth - graphVisibleLen else 0;
      graphLine = "${ansi.fgGreen}↓${ansi.resetAll}${rxGraph} ${ansi.fgMagenta}↑${ansi.resetAll}${txGraph}${utils.repeat graphPadding " "}";
      
      content = [rateLine graphLine];
      
    in boxes.box {
      inherit content width;
      title = "Network";
      chars = boxes.rounded;
      titleColor = themeColors.colors.network;
      borderColor = themeColors.colors.border;
    };

  # ============================================================================
  # Disk Box
  # ============================================================================
  
  renderDiskBox = { diskMetrics, width, theme }:
    let
      themeColors = themes.getTheme theme;
      
      innerWidth = width - 2;  # Account for box borders
      mounts = diskMetrics.mounts or [];
      
      # Render each mount point - ensure exact width for proper alignment
      renderMount = mount:
        let
          point = utils.truncate 10 (mount.mountPoint or "/");
          paddedPoint = utils.padRight 10 point;
          pct = mount.usedPercent or 0;
          sizeStr = "${mount.usedStr or "0"} / ${mount.totalStr or "0"}";
          
          # Calculate bar width: innerWidth - mountpoint(10) - spaces(3) - sizeStr
          barWidth = innerWidth - 10 - 3 - builtins.stringLength sizeStr;
          safeBarWidth = if barWidth > 0 then barWidth else 1;
          
          bar = graphs.percentageBar { 
            inherit pct; 
            width = safeBarWidth;
            showPct = false;
            gradient = colors.diskGradient;
          };
          
          # Calculate visible content width (bar display width = safeBarWidth)
          visibleWidth = 10 + 1 + safeBarWidth + 1 + builtins.stringLength sizeStr;
          trailingPad = if innerWidth > visibleWidth then innerWidth - visibleWidth else 0;
          
        in "${paddedPoint} ${bar} ${sizeStr}${utils.repeat trailingPad " "}";
      
      content = map renderMount (utils.take 4 mounts);  # Max 4 disks
      
    in boxes.box {
      inherit content width;
      title = "Disk";
      chars = boxes.rounded;
      titleColor = themeColors.colors.disk;
      borderColor = themeColors.colors.border;
    };

  # ============================================================================
  # Process Box
  # ============================================================================
  
  renderProcessBox = { procMetrics, width, height ? 10, theme }:
    let
      themeColors = themes.getTheme theme;
      
      processes = procMetrics.processes or [];
      header = procMetrics.header or "PID     USER     CPU%  MEM%  NAME";
      
      # Format header with colors
      coloredHeader = "${ansi.fgHex themeColors.colors.headerFg}${ansi.bold}${header}${ansi.resetAll}";
      
      # Separator
      separator = utils.repeat (width - 4) "─";
      
      # Format process lines
      formatProc = proc:
        let
          f = procMetrics.formatted or [];
          matching = utils.find (x: x.pid == utils.padLeft 7 (toString proc.pid)) f;
        in if matching != null then matching.line
           else "${utils.padLeft 7 (toString proc.pid)} ${utils.padRight 8 (proc.user or "?")} ${utils.padLeft 5 (toString (utils.round 1 (proc.cpuPercent or 0)))} ${utils.padLeft 5 (toString (utils.round 1 (proc.memPercent or 0)))}  ${utils.truncate 30 (proc.name or "?")}";
      
      maxProcs = height - 4;  # Account for header, separator, borders
      procLines = map formatProc (utils.take maxProcs processes);
      
      content = [coloredHeader separator] ++ procLines;
      
    in boxes.box {
      inherit content width;
      title = "Processes";
      chars = boxes.rounded;
      titleColor = themeColors.colors.process;
      borderColor = themeColors.colors.border;
    };

  # ============================================================================
  # Temperature/Battery Info Bar
  # ============================================================================
  
  renderInfoBar = { tempMetrics, batteryMetrics, width, theme }:
    let
      themeColors = themes.getTheme theme;
      
      # Temperature
      cpuTemp = tempMetrics.cpu or { temp = 0; formatted = "N/A"; };
      tempStr = "CPU: ${cpuTemp.formatted}";
      tempColor = colors.getTempColor cpuTemp.temp;
      coloredTemp = "${ansi.fgHex tempColor}${tempStr}${ansi.resetAll}";
      
      # Battery
      hasBattery = batteryMetrics.present or false;
      batteryStr = if hasBattery then batteryMetrics.summary or "No battery" else "";
      
      # Load average
      loadStr = "";  # TODO: Add load average
      
      # Combine
      parts = builtins.filter (s: s != "") [coloredTemp batteryStr];
      
    in builtins.concatStringsSep "  │  " parts;

  # ============================================================================
  # Main Frame Renderer
  # ============================================================================
  
  # Render the complete dashboard frame
  renderFrame = { 
    cpuMetrics, 
    memMetrics, 
    netMetrics, 
    diskMetrics, 
    procMetrics,
    tempMetrics,
    batteryMetrics,
    width, 
    height, 
    theme ? "default" 
  }:
    let
      themeColors = themes.getTheme theme;
      
      # Calculate layout dimensions
      # Top row: CPU (60%) + Memory (40%)
      cpuWidth = (width * 60) / 100;
      memWidth = width - cpuWidth;
      
      # Middle row: Network (60%) + Disk (40%)
      netWidth = cpuWidth;
      diskWidth = memWidth;
      
      # Bottom: Processes (full width)
      procWidth = width;
      
      # Calculate heights
      topRowHeight = 8;
      midRowHeight = 5;
      procHeight = height - topRowHeight - midRowHeight - 2;
      
      # Render individual boxes
      cpuBox = renderCpuBox { 
        inherit cpuMetrics theme; 
        width = cpuWidth - 1; 
      };
      
      memBox = renderMemoryBox { 
        inherit memMetrics theme; 
        width = memWidth; 
      };
      
      netBox = renderNetworkBox { 
        inherit netMetrics theme; 
        width = netWidth - 1; 
      };
      
      diskBox = renderDiskBox { 
        inherit diskMetrics theme; 
        width = diskWidth; 
      };
      
      procBox = renderProcessBox { 
        inherit procMetrics theme;
        width = procWidth;
        height = procHeight;
      };
      
      # Info bar at bottom
      infoBar = renderInfoBar { 
        inherit tempMetrics batteryMetrics theme;
        inherit width;
      };
      
      # Combine rows
      topRow = boxes.splitHorizontal {
        leftContent = cpuBox;
        rightContent = memBox;
        leftWidth = cpuWidth - 1;
        rightWidth = memWidth;
        gap = 0;
      };
      
      midRow = boxes.splitHorizontal {
        leftContent = netBox;
        rightContent = diskBox;
        leftWidth = netWidth - 1;
        rightWidth = diskWidth;
        gap = 0;
      };
      
      # Combine all rows
      allLines = topRow ++ midRow ++ procBox ++ [infoBar];
      
      # Apply background color (via ANSI codes at start of each line)
      bgCode = ansi.bgHex themeColors.colors.background;
      fgCode = ansi.fgHex themeColors.colors.foreground;
      
    in builtins.concatStringsSep "\n" allLines;

  # ============================================================================
  # Simple/Compact Renderer (for small terminals)
  # ============================================================================
  
  renderCompact = {
    cpuMetrics,
    memMetrics,
    netMetrics,
    width,
    theme ? "default"
  }:
    let
      themeColors = themes.getTheme theme;
      
      cpuPct = cpuMetrics.overall or 0;
      memPct = memMetrics.usedPercent or 0;
      
      primary = netMetrics.primary or {};
      rxRate = primary.rxRateStr or "0 B/s";
      txRate = primary.txRateStr or "0 B/s";
      
      barWidth = (width - 30) / 2;
      
      cpuBar = graphs.percentageBar { pct = cpuPct; width = barWidth; gradient = colors.cpuGradient; };
      memBar = graphs.percentageBar { pct = memPct; width = barWidth; gradient = colors.memoryGradient; };
      
      line1 = "CPU ${cpuBar}  MEM ${memBar}";
      line2 = "NET ↓${utils.padLeft 10 rxRate} ↑${utils.padLeft 10 txRate}";
      
    in "${line1}\n${line2}";

  # ============================================================================
  # Header/Title Bar
  # ============================================================================
  
  renderHeader = { width, theme ? "default", uptime ? null }:
    let
      themeColors = themes.getTheme theme;
      
      title = "nixmon";
      uptimeStr = if uptime != null then "up ${uptime.formatted or "?"}" else "";
      
      titleColored = "${ansi.bold}${ansi.fgHex themeColors.colors.title}${title}${ansi.resetAll}";
      
      spacing = width - builtins.stringLength title - builtins.stringLength uptimeStr - 2;
      
    in "${titleColored}${utils.repeat spacing " "}${uptimeStr}";
}


