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
      interfaces = netMetrics.interfaces or [];
      
      ifName = primary.name or "none";
      rxRate = primary.rxRateStr or "0 B/s";
      txRate = primary.txRateStr or "0 B/s";
      rxTotal = primary.rxTotalStr or "0 B";
      txTotal = primary.txTotalStr or "0 B";
      
      # Interface line with rates - ensure consistent column alignment
      # Format: [ifName(6)] [↓] [rxRate(10)] [↑] [txRate(10)]
      # All values right-aligned in their columns for vertical alignment
      ifNamePadded = utils.padRight 6 ifName;
      rxRatePadded = utils.padLeft 10 rxRate;
      txRatePadded = utils.padLeft 10 txRate;
      rateContent = "${ifNamePadded} ↓ ${rxRatePadded}  ↑ ${txRatePadded}";
      rateVisibleLen = 6 + 1 + 1 + 10 + 2 + 1 + 10;  # 6 + space + ↓ + space + 10 + 2 spaces + ↑ + space + 10
      ratePadding = if innerWidth > rateVisibleLen then innerWidth - rateVisibleLen else 0;
      rateLine = rateContent + utils.repeat ratePadding " ";
      
      # Total bytes line (if space allows) - align columns with rate line
      # Format: [Total:(6)] [↓] [rxTotal(10)] [↑] [txTotal(10)]
      totalLine = if innerWidth > 40 then
        let
          totalLabel = "Total:";
          totalLabelPadded = utils.padRight 6 totalLabel;  # Match ifName width
          rxTotalPadded = utils.padLeft 10 rxTotal;  # Match rxRate column
          txTotalPadded = utils.padLeft 10 txTotal;  # Match txRate column
          totalContent = "${totalLabelPadded} ↓ ${rxTotalPadded}  ↑ ${txTotalPadded}";
          totalVisibleLen = 6 + 1 + 1 + 10 + 2 + 1 + 10;  # Same as rateVisibleLen
          totalPadding = if innerWidth > totalVisibleLen then innerWidth - totalVisibleLen else 0;
        in totalContent + utils.repeat totalPadding " "
      else "";
      
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
      
      # Show interface count if multiple interfaces
      interfaceCount = builtins.length interfaces;
      countLine = if interfaceCount > 1 then "Interfaces: ${toString interfaceCount}" else "";
      
      content = builtins.filter (l: l != "") [rateLine totalLine graphLine countLine];
      
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
      
      # Render each mount point - optimized layout for narrow boxes
      # First, calculate consistent widths for all mounts
      # Find the longest size string to ensure consistent padding
      allSizeStrs = map (m: "${m.usedStr or "0"} / ${m.totalStr or "0"}") mounts;
      maxSizeStrLen = if allSizeStrs == [] then 15 
                      else utils.max (map builtins.stringLength allSizeStrs);
      targetSizeStrLen = utils.max [maxSizeStrLen 15];  # Minimum 15 chars for "XXX GB / XXX GB"
      
      # Calculate fixed widths for all mounts (use the same for all)
      targetBarWidth = 15;  # Target bar width for better visibility
      spaces = 2;  # One space before bar, one after
      neededSpace = targetBarWidth + targetSizeStrLen + spaces;
      maxPointWidth = utils.max [8 (innerWidth - neededSpace)];
      barVisualWidth = innerWidth - maxPointWidth - spaces - targetSizeStrLen;
      safeBarWidth = if barVisualWidth > 0 then barVisualWidth else 10;  # Minimum 10 chars
      
      renderMount = mount:
        let
          pct = mount.usedPercent or 0;
          sizeStr = "${mount.usedStr or "0"} / ${mount.totalStr or "0"}";
          # Right-align size string so all size strings end at the same position
          paddedSizeStr = utils.padLeft targetSizeStrLen sizeStr;
          
          # Truncate and pad mount point to fixed width (left-aligned)
          point = utils.truncate maxPointWidth (mount.mountPoint or "/");
          paddedPoint = utils.padRight maxPointWidth point;
          
          # Generate bar with fixed visual width
          # Visual width = safeBarWidth
          # String length = safeBarWidth + ~25 (ANSI codes: fgHex ~20-22 + resetAll ~4)
          bar = graphs.percentageBar { 
            inherit pct; 
            width = safeBarWidth;
            showPct = false;
            gradient = colors.diskGradient;
          };
          
          # Build the line: mountpoint + space + bar + space + size
          # Visual width: maxPointWidth + 1 + safeBarWidth + 1 + targetSizeStrLen = innerWidth
          # All components have fixed visual widths, so visual width is consistent
          # String length varies due to ANSI codes, but formatLine will handle padding
          line = "${paddedPoint} ${bar} ${paddedSizeStr}";
          
        in line;
      
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
  
  renderProcessBox = { procMetrics, width, height ? 10, theme, selectedPid ? null }:
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
          isSelected = selectedPid != null && proc.pid == selectedPid;
          highlight = if isSelected then "${ansi.reverseVideo}" else "";
          reset = if isSelected then "${ansi.resetAll}" else "";
        in if matching != null 
           then "${highlight}${matching.line}${reset}"
           else "${highlight}${utils.padLeft 7 (toString proc.pid)} ${utils.padRight 8 (proc.user or "?")} ${utils.padLeft 5 (toString (utils.round 1 (proc.cpuPercent or 0)))} ${utils.padLeft 5 (toString (utils.round 1 (proc.memPercent or 0)))}  ${utils.truncate 30 (proc.name or "?")}${reset}";
      
      maxProcs = height - 4;  # Account for header, separator, borders
      procLines = map formatProc (utils.take maxProcs processes);
      
      # Add filter indicator if filtering
      filterIndicator = if procMetrics.filtered or false then " (filtered)" else "";
      
      content = [coloredHeader separator] ++ procLines;
      
    in boxes.box {
      inherit content width;
      title = "Processes${filterIndicator}";
      chars = boxes.rounded;
      titleColor = themeColors.colors.process;
      borderColor = themeColors.colors.border;
    };
  
  # Render process details overlay
  renderProcessDetails = { process, width, height, theme }:
    let
      themeColors = themes.getTheme theme;
      details = [
        "Process Details:"
        ""
        "PID:     ${toString (process.pid or 0)}"
        "Name:    ${process.name or "unknown"}"
        "User:    ${process.user or "unknown"}"
        "CPU%:    ${toString (utils.round 2 (process.cpuPercent or 0))}%"
        "MEM%:    ${toString (utils.round 2 (process.memPercent or 0))}%"
        "CPU Time: ${toString (process.cpuTime or 0)}"
      ];
      
      boxWidth = 40;
      boxHeight = builtins.length details + 2;
      leftPad = (width - boxWidth) / 2;
      topPad = (height - boxHeight) / 2;
      
      detailBox = boxes.box {
        content = details;
        width = boxWidth;
        title = "Process Info";
        chars = boxes.rounded;
        titleColor = themeColors.colors.title;
        borderColor = themeColors.colors.border;
      };
      
      emptyLine = utils.repeat width " ";
      topPadding = builtins.genList (_: emptyLine) topPad;
      leftPadding = utils.repeat leftPad " ";
      paddedLines = map (line: leftPadding + line) detailBox;
      
    in builtins.concatStringsSep "\n" (topPadding ++ paddedLines);

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
    theme ? "default",
    selectedPid ? null
  }:
    let
      themeColors = themes.getTheme theme;
      
      # Calculate layout dimensions
      # Top row: CPU (60%) + Memory (40%)
      cpuWidth = (width * 60) / 100;
      memWidth = width - cpuWidth;
      
      # Middle row: Network (55%) + Disk (45%) - give disk more space for better bars
      netWidth = (width * 55) / 100;
      diskWidth = width - netWidth;
      
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
        selectedPid = null;  # TODO: Pass from render function
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
  
  # ============================================================================
  # Help Overlay
  # ============================================================================
  
  renderHelp = { width, height, theme ? "default" }:
    let
      themeColors = themes.getTheme theme;
      helpLines = [
        "Keyboard Shortcuts:"
        ""
        "  q, Esc    - Quit"
        "  +, =      - Increase refresh rate"
        "  -, _      - Decrease refresh rate"
        "  t         - Cycle themes"
        "  s         - Cycle sort (CPU/MEM/PID/NAME)"
        "  f         - Clear process filter"
        "  k         - Kill selected process"
        "  h, ?      - Toggle this help"
        ""
        "Process Filtering:"
        "  Type process name to filter (case-insensitive)"
        ""
        "Themes: default, nord, gruvbox, dracula, monokai, solarized"
      ];
      
      # Center the help box
      boxWidth = 50;
      boxHeight = builtins.length helpLines + 2;
      leftPad = (width - boxWidth) / 2;
      topPad = (height - boxHeight) / 2;
      
      # Create box
      helpBox = boxes.box {
        content = helpLines;
        width = boxWidth;
        title = "Help";
        chars = boxes.rounded;
        titleColor = themeColors.colors.title;
        borderColor = themeColors.colors.border;
      };
      
      # Add padding
      emptyLine = utils.repeat width " ";
      topPadding = builtins.genList (_: emptyLine) topPad;
      leftPadding = utils.repeat leftPad " ";
      
      paddedLines = map (line: leftPadding + line) helpBox;
      
    in builtins.concatStringsSep "\n" (topPadding ++ paddedLines);
}


