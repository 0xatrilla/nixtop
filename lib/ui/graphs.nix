# Graph and visualization components for nixmon
{ pkgs, utils }:

rec {
  # ============================================================================
  # Character sets for graphs
  # ============================================================================
  
  # Braille characters for high-resolution sparklines (8 levels)
  # Each character represents 2 columns x 4 rows of dots
  brailleChars = [
    " "   # 0 - empty
    "⡀"  # 1 - bottom dot
    "⡄"  # 2
    "⡆"  # 3
    "⡇"  # 4
    "⣇"  # 5
    "⣧"  # 6
    "⣷"  # 7
    "⣿"  # 8 - full
  ];

  # Block characters for progress bars (8 levels of fill)
  blockChars = [
    " "   # 0 - empty
    "▏"  # 1 - 1/8
    "▎"  # 2 - 2/8
    "▍"  # 3 - 3/8
    "▌"  # 4 - 4/8
    "▋"  # 5 - 5/8
    "▊"  # 6 - 6/8
    "▉"  # 7 - 7/8
    "█"  # 8 - full
  ];

  # Vertical bar characters (8 levels)
  verticalChars = [
    " "   # 0
    "▁"  # 1
    "▂"  # 2
    "▃"  # 3
    "▄"  # 4
    "▅"  # 5
    "▆"  # 6
    "▇"  # 7
    "█"  # 8
  ];

  # Horizontal bar fill characters
  fillChar = "█";
  emptyChar = "░";
  halfChars = ["░" "▒" "▓" "█"];

  # ============================================================================
  # Sparkline - mini graph using braille or block characters
  # ============================================================================
  
  # Render a sparkline from a list of values
  # values: list of numbers (0-100 or arbitrary range)
  # width: number of characters
  # maxVal: optional maximum value (auto-detected if not provided)
  sparkline = { values, width ? 20, maxVal ? null, chars ? verticalChars }:
    let
      # Handle empty input
      safeValues = if values == [] then [0] else values;
      
      # Auto-detect max if not provided
      actualMax = if maxVal != null then maxVal 
                  else let m = utils.max safeValues; in if m == 0 then 1 else m;
      
      numChars = builtins.length chars - 1;  # -1 because first char is empty
      
      # Normalize value to character index
      normalize = val:
        let
          clamped = utils.clamp 0 actualMax val;
          idx = builtins.floor ((clamped * numChars) / actualMax);
        in utils.clamp 0 numChars idx;
      
      # Sample or pad values to match width
      numValues = builtins.length safeValues;
      sampledValues = 
        if numValues >= width 
        then # Sample: take evenly spaced values
          let step = numValues / width;
          in builtins.genList (i: 
            builtins.elemAt safeValues (builtins.floor (i * step))
          ) width
        else # Pad: repeat last values or fill with zeros
          let
            padding = builtins.genList (_: 0) (width - numValues);
          in padding ++ safeValues;
      
      # Convert to characters
      charList = map (v: builtins.elemAt chars (normalize v)) sampledValues;
      
    in builtins.concatStringsSep "" charList;

  # ============================================================================
  # Horizontal Progress Bar
  # ============================================================================
  
  # Basic horizontal bar with percentage
  # pct: 0-100
  # width: total width including percentage text
  # showPct: whether to show percentage number
  horizontalBar = { pct, width ? 20, showPct ? true, fillColor ? null, emptyColor ? null }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      
      # Calculate bar width (leave room for percentage if shown)
      pctText = if showPct then " ${utils.padLeft 3 (toString (builtins.floor pct))}%" else "";
      pctWidth = builtins.stringLength pctText;
      barWidth = width - pctWidth;
      
      # Calculate filled portion
      clampedPct = utils.clamp 0 100 pct;
      filledWidth = builtins.floor ((clampedPct * barWidth) / 100);
      emptyWidth = barWidth - filledWidth;
      
      # Build bar
      filled = utils.repeat filledWidth fillChar;
      empty = utils.repeat emptyWidth emptyChar;
      
      # Apply colors if provided
      coloredFilled = if fillColor != null 
                      then "${ansi.fgHex fillColor}${filled}${ansi.resetAll}"
                      else filled;
      coloredEmpty = if emptyColor != null
                     then "${ansi.fgHex emptyColor}${empty}${ansi.resetAll}"
                     else empty;
      
    in coloredFilled + coloredEmpty + pctText;

  # Smooth horizontal bar with sub-character precision
  horizontalBarSmooth = { pct, width ? 20, showPct ? true }:
    let
      pctText = if showPct then " ${utils.padLeft 3 (toString (builtins.floor pct))}%" else "";
      pctWidth = builtins.stringLength pctText;
      barWidth = width - pctWidth;
      
      clampedPct = utils.clamp 0 100 pct;
      
      # Calculate with sub-character precision (8 levels per char)
      totalUnits = barWidth * 8;
      filledUnits = builtins.floor ((clampedPct * totalUnits) / 100);
      
      fullChars = filledUnits / 8;
      partialUnits = filledUnits - (fullChars * 8);
      emptyChars = barWidth - fullChars - (if partialUnits > 0 then 1 else 0);
      
      filled = utils.repeat fullChars fillChar;
      partial = if partialUnits > 0 then builtins.elemAt blockChars partialUnits else "";
      empty = utils.repeat emptyChars " ";
      
    in filled + partial + empty + pctText;

  # ============================================================================
  # Colored Progress Bar (color changes based on value)
  # ============================================================================
  
  # Progress bar that changes color based on percentage
  percentageBar = { pct, width ? 20, showPct ? true, gradient ? null }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      colors = import ./colors.nix { inherit pkgs utils; };
      
      # Default to CPU gradient if not specified
      actualGradient = if gradient != null then gradient else colors.cpuGradient;
      
      # Get color based on percentage
      color = colors.getGradientColor actualGradient pct;
      
      pctText = if showPct then " ${utils.padLeft 3 (toString (builtins.floor pct))}%" else "";
      pctWidth = builtins.stringLength pctText;
      barWidth = width - pctWidth;
      
      clampedPct = utils.clamp 0 100 pct;
      filledWidth = builtins.floor ((clampedPct * barWidth) / 100);
      emptyWidth = barWidth - filledWidth;
      
      filled = utils.repeat filledWidth fillChar;
      empty = utils.repeat emptyWidth emptyChar;
      
    in "${ansi.fgHex color}${filled}${ansi.resetAll}${empty}${pctText}";

  # ============================================================================
  # Dual Bar (e.g., for upload/download)
  # ============================================================================
  
  dualBar = { val1, val2, maxVal, width ? 20, color1 ? "#50fa7b", color2 ? "#ff79c6" }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      
      safeMax = if maxVal == 0 then 1 else maxVal;
      
      pct1 = utils.clamp 0 100 ((val1 * 100) / safeMax);
      pct2 = utils.clamp 0 100 ((val2 * 100) / safeMax);
      
      width1 = builtins.floor ((pct1 * width) / 100);
      width2 = builtins.floor ((pct2 * width) / 100);
      emptyWidth = width - width1 - width2;
      
      bar1 = utils.repeat width1 "▓";
      bar2 = utils.repeat width2 "░";
      empty = utils.repeat (if emptyWidth > 0 then emptyWidth else 0) " ";
      
    in "${ansi.fgHex color1}${bar1}${ansi.resetAll}${ansi.fgHex color2}${bar2}${ansi.resetAll}${empty}";

  # ============================================================================
  # Vertical Bar Chart
  # ============================================================================
  
  # Render a single vertical bar (returns list of strings, one per row from top to bottom)
  verticalBar = { pct, height ? 5 }:
    let
      clampedPct = utils.clamp 0 100 pct;
      totalUnits = height * 8;
      filledUnits = builtins.floor ((clampedPct * totalUnits) / 100);
      
      # Generate rows from top to bottom
      makeRow = rowIdx:
        let
          # How many units in this row (row 0 is top)
          rowStart = (height - 1 - rowIdx) * 8;
          rowEnd = rowStart + 8;
          unitsInRow = utils.clamp 0 8 (filledUnits - rowStart);
        in
          if unitsInRow <= 0 then " "
          else if unitsInRow >= 8 then "█"
          else builtins.elemAt verticalChars unitsInRow;
      
    in builtins.genList makeRow height;

  # Render multiple vertical bars side by side
  verticalBarChart = { values, height ? 5, spacing ? 1, maxVal ? null }:
    let
      safeValues = if values == [] then [0] else values;
      actualMax = if maxVal != null then maxVal 
                  else let m = utils.max safeValues; in if m == 0 then 1 else m;
      
      # Convert values to percentages
      pcts = map (v: (v * 100) / actualMax) safeValues;
      
      # Generate bars
      bars = map (p: verticalBar { pct = p; inherit height; }) pcts;
      spacer = utils.repeat spacing " ";
      
      # Combine rows
      makeRow = rowIdx:
        builtins.concatStringsSep spacer (map (bar: builtins.elemAt bar rowIdx) bars);
      
    in builtins.genList makeRow height;

  # ============================================================================
  # Mini Graph (for inline display)
  # ============================================================================
  
  # Tiny inline graph for headers
  miniGraph = { values, width ? 10 }:
    sparkline { inherit values width; chars = verticalChars; };

  # ============================================================================
  # CPU Core Display
  # ============================================================================
  
  # Render CPU cores in a compact grid format
  cpuCoreGrid = { cores, cols ? 2, barWidth ? 12 }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      colors = import ./colors.nix { inherit pkgs utils; };
      
      numCores = builtins.length cores;
      rows = (numCores + cols - 1) / cols;  # Ceiling division
      
      # Render single core
      renderCore = idx: core:
        let
          pct = core.pct or 0;
          color = colors.getCpuColor pct;
          label = "Core ${utils.padLeft 2 (toString idx)}";
          bar = horizontalBar { inherit pct; width = barWidth; showPct = false; fillColor = color; };
          pctStr = utils.padLeft 3 (toString (builtins.floor pct));
        in "${label} ${bar} ${pctStr}%";
      
      # Generate row with two cores side by side
      makeRow = rowIdx:
        let
          leftIdx = rowIdx * cols;
          rightIdx = leftIdx + 1;
          leftCore = if leftIdx < numCores then renderCore leftIdx (builtins.elemAt cores leftIdx) else "";
          rightCore = if rightIdx < numCores then renderCore rightIdx (builtins.elemAt cores rightIdx) else "";
          spacing = utils.repeat 2 " ";
        in leftCore + spacing + rightCore;
      
    in builtins.genList makeRow rows;

  # ============================================================================
  # Network Graph
  # ============================================================================
  
  # Sparkline with up/down arrows
  networkGraph = { rxHistory, txHistory, width ? 20 }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      
      rxGraph = sparkline { values = rxHistory; inherit width; };
      txGraph = sparkline { values = txHistory; inherit width; };
      
    in {
      rx = "${ansi.fgGreen}↓${ansi.resetAll} ${rxGraph}";
      tx = "${ansi.fgMagenta}↑${ansi.resetAll} ${txGraph}";
    };

  # ============================================================================
  # Disk Usage Bar with Label
  # ============================================================================
  
  diskUsageBar = { mountPoint, used, total, width ? 30 }:
    let
      colors = import ./colors.nix { inherit pkgs utils; };
      
      pct = if total == 0 then 0 else (used * 100) / total;
      color = colors.getDiskColor pct;
      
      # Truncate mount point if needed
      maxLabelWidth = 10;
      label = utils.padRight maxLabelWidth (utils.truncate maxLabelWidth mountPoint);
      
      # Format sizes
      usedStr = utils.formatBytes used;
      totalStr = utils.formatBytes total;
      sizeStr = "${usedStr}/${totalStr}";
      
      barWidth = width - maxLabelWidth - builtins.stringLength sizeStr - 3;
      bar = percentageBar { inherit pct; width = barWidth; showPct = false; gradient = colors.diskGradient; };
      
    in "${label} ${bar} ${sizeStr}";

  # ============================================================================
  # Battery indicator
  # ============================================================================
  
  batteryIndicator = { pct, charging ? false, width ? 10 }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      colors = import ./colors.nix { inherit pkgs utils; };
      
      color = colors.getBatteryColor pct;
      icon = if charging then "⚡" else "🔋";
      
      bar = horizontalBar { inherit pct; width = width - 2; showPct = false; fillColor = color; };
      
    in "${icon} ${bar}";
}



