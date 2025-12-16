# Color definitions and palettes
{ pkgs, utils }:

rec {
  # ============================================================================
  # Named color values (hex)
  # ============================================================================
  
  palette = {
    # Grayscale
    black = "#000000";
    darkGray = "#404040";
    gray = "#808080";
    lightGray = "#c0c0c0";
    white = "#ffffff";
    
    # Primary colors
    red = "#ff0000";
    green = "#00ff00";
    blue = "#0000ff";
    
    # Secondary colors
    cyan = "#00ffff";
    magenta = "#ff00ff";
    yellow = "#ffff00";
    
    # Extended palette
    orange = "#ff8000";
    pink = "#ff80c0";
    purple = "#8000ff";
    teal = "#008080";
    olive = "#808000";
    navy = "#000080";
    maroon = "#800000";
    
    # Soft colors for UI
    softRed = "#e06c75";
    softGreen = "#98c379";
    softBlue = "#61afef";
    softYellow = "#e5c07b";
    softCyan = "#56b6c2";
    softMagenta = "#c678dd";
    softOrange = "#d19a66";
    
    # System status colors
    success = "#50fa7b";
    warning = "#f1fa8c";
    error = "#ff5555";
    info = "#8be9fd";
  };

  # ============================================================================
  # Gradient helpers
  # ============================================================================
  
  # Interpolate between two colors based on percentage (0-100)
  interpolate = color1: color2: pct:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      rgb1 = ansi.hexToRGB color1;
      rgb2 = ansi.hexToRGB color2;
      t = pct / 100.0;
      lerp = a: b: builtins.floor (a + (b - a) * t);
    in {
      r = lerp rgb1.r rgb2.r;
      g = lerp rgb1.g rgb2.g;
      b = lerp rgb1.b rgb2.b;
    };

  # Create a gradient list of colors
  gradient = color1: color2: steps:
    builtins.genList (i:
      let pct = if steps <= 1 then 0 else (i * 100) / (steps - 1);
      in interpolate color1 color2 pct
    ) steps;

  # ============================================================================
  # Semantic color mappings
  # ============================================================================
  
  # CPU usage colors (green -> yellow -> red)
  cpuGradient = [
    "#50fa7b"  # 0-10%   - green
    "#69ff94"  # 10-20%
    "#98c379"  # 20-30%
    "#b5e853"  # 30-40%
    "#e5c07b"  # 40-50%  - yellow
    "#f1fa8c"  # 50-60%
    "#ffb86c"  # 60-70%
    "#ff9966"  # 70-80%  - orange
    "#ff6666"  # 80-90%  - light red
    "#ff5555"  # 90-100% - red
  ];

  # Memory usage colors
  memoryGradient = [
    "#8be9fd"  # 0-25%   - cyan
    "#61afef"  # 25-50%  - blue
    "#c678dd"  # 50-75%  - magenta
    "#ff5555"  # 75-100% - red
  ];

  # Temperature colors (cool -> hot)
  tempGradient = [
    "#61afef"  # Cool - blue
    "#56b6c2"  # Normal - cyan
    "#98c379"  # Warm - green
    "#e5c07b"  # Getting hot - yellow
    "#ffb86c"  # Hot - orange
    "#ff5555"  # Critical - red
  ];

  # Network activity colors
  networkColors = {
    download = "#50fa7b";  # Green
    upload = "#ff79c6";    # Pink
    idle = "#6272a4";      # Gray-blue
  };

  # Disk usage colors
  diskGradient = [
    "#50fa7b"  # 0-50%   - green
    "#e5c07b"  # 50-75%  - yellow
    "#ffb86c"  # 75-90%  - orange
    "#ff5555"  # 90-100% - red
  ];

  # Battery colors
  batteryGradient = [
    "#ff5555"  # 0-10%   - red (critical)
    "#ffb86c"  # 10-25%  - orange (low)
    "#e5c07b"  # 25-50%  - yellow
    "#98c379"  # 50-75%  - light green
    "#50fa7b"  # 75-100% - green (full)
  ];

  # ============================================================================
  # Helper functions
  # ============================================================================
  
  # Get color from gradient based on percentage
  getGradientColor = gradient: pct:
    let
      len = builtins.length gradient;
      clampedPct = utils.clamp 0 99 pct;
      idx = builtins.floor ((clampedPct * len) / 100);
    in builtins.elemAt gradient idx;

  # Get CPU color based on usage percentage
  getCpuColor = pct: getGradientColor cpuGradient pct;

  # Get memory color based on usage percentage
  getMemoryColor = pct:
    let
      len = builtins.length memoryGradient;
      idx = builtins.floor ((utils.clamp 0 99 pct) * len / 100);
    in builtins.elemAt memoryGradient idx;

  # Get temperature color based on celsius (assumes 30-100 range)
  getTempColor = celsius:
    let
      pct = utils.clamp 0 100 ((celsius - 30) * 100 / 70);
    in getGradientColor tempGradient pct;

  # Get disk color based on usage percentage
  getDiskColor = pct: getGradientColor diskGradient pct;

  # Get battery color based on percentage
  getBatteryColor = pct: getGradientColor batteryGradient pct;
}

