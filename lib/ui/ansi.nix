# ANSI escape code helpers for terminal UI
{ pkgs, utils }:

rec {
  # ============================================================================
  # Escape sequences
  # ============================================================================
  
  # The escape character
  esc = "\\x1b";
  escReal = builtins.fromJSON ''"\u001b"'';
  
  # Control Sequence Introducer
  csi = "${escReal}[";

  # ============================================================================
  # Cursor control
  # ============================================================================
  
  # Move cursor to position (1-indexed)
  moveTo = row: col: "${csi}${toString row};${toString col}H";
  
  # Move cursor up/down/left/right
  moveUp = n: "${csi}${toString n}A";
  moveDown = n: "${csi}${toString n}B";
  moveRight = n: "${csi}${toString n}C";
  moveLeft = n: "${csi}${toString n}D";
  
  # Move to start of line
  moveToCol = col: "${csi}${toString col}G";
  
  # Save and restore cursor position
  saveCursor = "${csi}s";
  restoreCursor = "${csi}u";
  
  # Hide/show cursor
  hideCursor = "${csi}?25l";
  showCursor = "${csi}?25h";

  # ============================================================================
  # Screen control
  # ============================================================================
  
  # Clear screen
  clearScreen = "${csi}2J";
  
  # Clear from cursor to end of screen
  clearToEnd = "${csi}0J";
  
  # Clear from cursor to start of screen
  clearToStart = "${csi}1J";
  
  # Clear current line
  clearLine = "${csi}2K";
  
  # Clear from cursor to end of line
  clearLineToEnd = "${csi}0K";
  
  # Reset terminal to initial state
  reset = "${csi}0m${csi}H${csi}2J";

  # ============================================================================
  # Text formatting
  # ============================================================================
  
  # Reset all attributes
  resetAll = "${csi}0m";
  
  # Text styles
  bold = "${csi}1m";
  dim = "${csi}2m";
  italic = "${csi}3m";
  underline = "${csi}4m";
  blink = "${csi}5m";
  reverse = "${csi}7m";
  hidden = "${csi}8m";
  strikethrough = "${csi}9m";
  
  # Reset specific styles
  resetBold = "${csi}22m";
  resetDim = "${csi}22m";
  resetItalic = "${csi}23m";
  resetUnderline = "${csi}24m";
  resetBlink = "${csi}25m";
  resetReverse = "${csi}27m";
  resetHidden = "${csi}28m";
  resetStrikethrough = "${csi}29m";

  # ============================================================================
  # Basic colors (8-color)
  # ============================================================================
  
  # Foreground colors
  fgBlack = "${csi}30m";
  fgRed = "${csi}31m";
  fgGreen = "${csi}32m";
  fgYellow = "${csi}33m";
  fgBlue = "${csi}34m";
  fgMagenta = "${csi}35m";
  fgCyan = "${csi}36m";
  fgWhite = "${csi}37m";
  fgDefault = "${csi}39m";
  
  # Background colors
  bgBlack = "${csi}40m";
  bgRed = "${csi}41m";
  bgGreen = "${csi}42m";
  bgYellow = "${csi}43m";
  bgBlue = "${csi}44m";
  bgMagenta = "${csi}45m";
  bgCyan = "${csi}46m";
  bgWhite = "${csi}47m";
  bgDefault = "${csi}49m";
  
  # Bright foreground colors
  fgBrightBlack = "${csi}90m";
  fgBrightRed = "${csi}91m";
  fgBrightGreen = "${csi}92m";
  fgBrightYellow = "${csi}93m";
  fgBrightBlue = "${csi}94m";
  fgBrightMagenta = "${csi}95m";
  fgBrightCyan = "${csi}96m";
  fgBrightWhite = "${csi}97m";
  
  # Bright background colors
  bgBrightBlack = "${csi}100m";
  bgBrightRed = "${csi}101m";
  bgBrightGreen = "${csi}102m";
  bgBrightYellow = "${csi}103m";
  bgBrightBlue = "${csi}104m";
  bgBrightMagenta = "${csi}105m";
  bgBrightCyan = "${csi}106m";
  bgBrightWhite = "${csi}107m";

  # ============================================================================
  # 256 color support
  # ============================================================================
  
  # Set foreground to 256-color palette
  fg256 = n: "${csi}38;5;${toString n}m";
  
  # Set background to 256-color palette
  bg256 = n: "${csi}48;5;${toString n}m";

  # ============================================================================
  # True color (24-bit) support
  # ============================================================================
  
  # Set foreground to RGB color
  fgRGB = r: g: b: "${csi}38;2;${toString r};${toString g};${toString b}m";
  
  # Set background to RGB color
  bgRGB = r: g: b: "${csi}48;2;${toString r};${toString g};${toString b}m";
  
  # Parse hex color to RGB
  hexToRGB = hex:
    let
      # Remove # if present
      clean = if builtins.substring 0 1 hex == "#" 
              then builtins.substring 1 6 hex 
              else hex;
      # Parse hex digits
      hexDigit = c:
        let chars = {
          "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4;
          "5" = 5; "6" = 6; "7" = 7; "8" = 8; "9" = 9;
          "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
          "A" = 10; "B" = 11; "C" = 12; "D" = 13; "E" = 14; "F" = 15;
        };
        in chars.${c} or 0;
      parseHex = s: hexDigit (builtins.substring 0 1 s) * 16 + hexDigit (builtins.substring 1 1 s);
    in {
      r = parseHex (builtins.substring 0 2 clean);
      g = parseHex (builtins.substring 2 2 clean);
      b = parseHex (builtins.substring 4 2 clean);
    };
  
  # Set foreground from hex color
  fgHex = hex:
    let rgb = hexToRGB hex;
    in fgRGB rgb.r rgb.g rgb.b;
  
  # Set background from hex color
  bgHex = hex:
    let rgb = hexToRGB hex;
    in bgRGB rgb.r rgb.g rgb.b;

  # ============================================================================
  # Helper functions
  # ============================================================================
  
  # Apply style and reset after text
  styled = style: text: "${style}${text}${resetAll}";
  
  # Combine multiple styles
  styles = styleList: builtins.concatStringsSep "" styleList;
  
  # Apply foreground color to text
  colored = color: text: "${color}${text}${fgDefault}";
  
  # Apply foreground and background to text
  coloredBg = fg: bg: text: "${fg}${bg}${text}${fgDefault}${bgDefault}";
  
  # Make text bold and colored
  boldColored = color: text: "${bold}${color}${text}${resetAll}";
}

