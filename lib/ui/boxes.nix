# Box drawing and layout components for nixmon
{ pkgs, utils }:

rec {
  # ============================================================================
  # Box drawing characters (Unicode)
  # ============================================================================
  
  # Single line box characters
  single = {
    horizontal = "─";
    vertical = "│";
    topLeft = "┌";
    topRight = "┐";
    bottomLeft = "└";
    bottomRight = "┘";
    leftT = "├";
    rightT = "┤";
    topT = "┬";
    bottomT = "┴";
    cross = "┼";
  };

  # Double line box characters
  double = {
    horizontal = "═";
    vertical = "║";
    topLeft = "╔";
    topRight = "╗";
    bottomLeft = "╚";
    bottomRight = "╝";
    leftT = "╠";
    rightT = "╣";
    topT = "╦";
    bottomT = "╩";
    cross = "╬";
  };

  # Rounded box characters
  rounded = {
    horizontal = "─";
    vertical = "│";
    topLeft = "╭";
    topRight = "╮";
    bottomLeft = "╰";
    bottomRight = "╯";
    leftT = "├";
    rightT = "┤";
    topT = "┬";
    bottomT = "┴";
    cross = "┼";
  };

  # Heavy box characters
  heavy = {
    horizontal = "━";
    vertical = "┃";
    topLeft = "┏";
    topRight = "┓";
    bottomLeft = "┗";
    bottomRight = "┛";
    leftT = "┣";
    rightT = "┫";
    topT = "┳";
    bottomT = "┻";
    cross = "╋";
  };

  # Default character set
  defaultChars = single;

  # ============================================================================
  # Basic Box Drawing
  # ============================================================================
  
  # Draw a horizontal line
  horizontalLine = width: chars:
    utils.repeat width chars.horizontal;

  # Draw a box border (returns list of strings - top, middle rows, bottom)
  # width: total width including borders
  # height: total height including borders
  # title: optional title for top border
  boxBorder = { width, height, title ? null, chars ? defaultChars, titleColor ? null }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      
      innerWidth = width - 2;  # Subtract left and right borders
      
      # Title handling
      titleStr = if title == null then ""
                 else " ${title} ";
      titleLen = builtins.stringLength titleStr;
      
      # Top border with optional title
      topLineWidth = innerWidth - titleLen;
      leftPadding = if title == null then innerWidth else 1;
      rightPadding = if title == null then 0 else topLineWidth - 1;
      
      coloredTitle = if title == null then ""
                     else if titleColor != null 
                     then "${ansi.fgHex titleColor}${titleStr}${ansi.resetAll}"
                     else titleStr;
      
      topLine = chars.topLeft 
                + (if title == null 
                   then horizontalLine innerWidth chars
                   else chars.horizontal + coloredTitle + horizontalLine rightPadding chars)
                + chars.topRight;
      
      # Middle (empty) rows
      emptyRow = chars.vertical + utils.repeat innerWidth " " + chars.vertical;
      middleRows = builtins.genList (_: emptyRow) (height - 2);
      
      # Bottom border
      bottomLine = chars.bottomLeft + horizontalLine innerWidth chars + chars.bottomRight;
      
    in [topLine] ++ middleRows ++ [bottomLine];

  # ============================================================================
  # Box with Content
  # ============================================================================
  
  # Draw a box with content inside
  # content: list of strings (one per line)
  # width: total width (content will be padded/truncated)
  # title: optional title
  # NOTE: Content should be pre-padded to innerWidth if it contains ANSI codes
  box = { content, width, title ? null, chars ? defaultChars, titleColor ? null, borderColor ? null }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      
      innerWidth = width - 2;
      height = builtins.length content + 2;  # +2 for top and bottom borders
      
      # Format content lines
      # Lines may contain ANSI escape codes, making string length > visual width
      # Use ANSI-aware length to pad correctly.
      formatLine = line:
        let
          visualLen = utils.visualLength line;
          paddingNeeded = if visualLen < innerWidth
                          then innerWidth - visualLen
                          else 0;
          padded = line + utils.repeat paddingNeeded " ";
        in chars.vertical + padded + chars.vertical;


      
      # Title handling
      titleStr = if title == null then ""
                 else " ${title} ";
      titleLen = builtins.stringLength titleStr;
      rightPadding = innerWidth - titleLen - 1;
      
      coloredTitle = if title == null then ""
                     else if titleColor != null 
                     then "${ansi.fgHex titleColor}${titleStr}${ansi.resetAll}"
                     else titleStr;
      
      # Build the box
      topLine = chars.topLeft 
                + (if title == null 
                   then horizontalLine innerWidth chars
                   else chars.horizontal + coloredTitle + horizontalLine (if rightPadding > 0 then rightPadding else 0) chars)
                + chars.topRight;
      
      bottomLine = chars.bottomLeft + horizontalLine innerWidth chars + chars.bottomRight;
      
      # Apply border color if specified
      applyBorderColor = line:
        if borderColor != null
        then "${ansi.fgHex borderColor}${line}${ansi.resetAll}"
        else line;
      
      contentLines = map formatLine content;
      
    in map applyBorderColor ([topLine] ++ contentLines ++ [bottomLine]);

  # ============================================================================
  # Panel (box with padding)
  # ============================================================================
  
  panel = { content, width, title ? null, padding ? 1, chars ? defaultChars, titleColor ? null }:
    let
      innerWidth = width - 2 - (padding * 2);
      
      # Add horizontal padding to each line
      padLine = line:
        let
          truncated = utils.truncate innerWidth line;
          padded = utils.padRight innerWidth truncated;
          hPad = utils.repeat padding " ";
        in hPad + padded + hPad;
      
      # Add vertical padding (empty lines)
      vPadding = builtins.genList (_: utils.repeat (innerWidth + padding * 2) " ") padding;
      
      paddedContent = vPadding ++ (map padLine content) ++ vPadding;
      
    in box { content = paddedContent; inherit width title chars titleColor; };

  # ============================================================================
  # Split Layouts
  # ============================================================================
  
  # Split horizontally (side by side)
  # leftContent and rightContent are lists of strings
  # Returns combined list of strings
  splitHorizontal = { leftContent, rightContent, leftWidth, rightWidth, gap ? 0 }:
    let
      maxHeight = utils.max [(builtins.length leftContent) (builtins.length rightContent)];
      gapStr = utils.repeat gap " ";
      
      getLine = content: idx:
        if idx < builtins.length content
        then builtins.elemAt content idx
        else "";
      
      combineLine = idx:
        let
          left = utils.padRight leftWidth (getLine leftContent idx);
          right = utils.padRight rightWidth (getLine rightContent idx);
        in left + gapStr + right;
      
    in builtins.genList combineLine maxHeight;

  # Split vertically (stacked)
  splitVertical = { topContent, bottomContent, gap ? 0 }:
    let
      gapLines = builtins.genList (_: "") gap;
    in topContent ++ gapLines ++ bottomContent;

  # ============================================================================
  # Multi-column Layout
  # ============================================================================
  
  # Arrange multiple boxes in columns
  columns = { boxes, widths, gap ? 1 }:
    let
      numBoxes = builtins.length boxes;
      gapStr = utils.repeat gap " ";
      
      # Find max height across all boxes
      heights = map builtins.length boxes;
      maxHeight = utils.max heights;
      
      # Get line from box, padding if needed
      getLine = boxIdx: lineIdx:
        let
          boxContent = builtins.elemAt boxes boxIdx;
          width = builtins.elemAt widths boxIdx;
          line = if lineIdx < builtins.length boxContent
                 then builtins.elemAt boxContent lineIdx
                 else "";
        in utils.padRight width line;
      
      # Combine all columns for a single row
      makeRow = lineIdx:
        let
          cols = builtins.genList (boxIdx: getLine boxIdx lineIdx) numBoxes;
        in builtins.concatStringsSep gapStr cols;
      
    in builtins.genList makeRow maxHeight;

  # ============================================================================
  # Section Divider
  # ============================================================================
  
  # Horizontal divider with optional label
  divider = { width, label ? null, chars ? defaultChars, color ? null }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      
      line = if label == null 
             then horizontalLine width chars
             else let labelStr = " ${label} ";
                      labelLen = builtins.stringLength labelStr;
                      leftWidth = (width - labelLen) / 2;
                      rightWidth = width - labelLen - leftWidth;
                  in horizontalLine leftWidth chars + labelStr + horizontalLine rightWidth chars;
      
    in if color != null
       then "${ansi.fgHex color}${line}${ansi.resetAll}"
       else line;

  # ============================================================================
  # Table
  # ============================================================================
  
  # Render a simple table
  # headers: list of {name, width}
  # rows: list of lists (each inner list is a row of values)
  table = { headers, rows, chars ? defaultChars, headerColor ? null }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      
      totalWidth = utils.sum (map (h: h.width) headers) + builtins.length headers - 1;
      
      # Render header row
      renderHeader = h: utils.padRight h.width h.name;
      headerLine = builtins.concatStringsSep " " (map renderHeader headers);
      coloredHeader = if headerColor != null
                      then "${ansi.fgHex headerColor}${headerLine}${ansi.resetAll}"
                      else headerLine;
      
      # Render separator
      separatorParts = map (h: horizontalLine h.width chars) headers;
      separator = builtins.concatStringsSep chars.topT separatorParts;
      
      # Render data rows
      renderCell = idx: value:
        let width = (builtins.elemAt headers idx).width;
        in utils.padRight width (utils.truncate width (toString value));
      
      renderRow = row:
        builtins.concatStringsSep " " (builtins.genList (i: renderCell i (builtins.elemAt row i)) (builtins.length headers));
      
      dataLines = map renderRow rows;
      
    in [coloredHeader separator] ++ dataLines;

  # ============================================================================
  # Helper: Join lines into single string
  # ============================================================================
  
  joinLines = lines:
    builtins.concatStringsSep "\n" lines;

  # ============================================================================
  # Composite Box Layouts
  # ============================================================================
  
  # Create a box with a sub-section (like Memory with Swap below it)
  boxWithSubsection = { 
    mainContent, 
    subContent, 
    width, 
    mainTitle ? null, 
    subTitle ? null, 
    chars ? defaultChars,
    titleColor ? null 
  }:
    let
      ansi = import ./ansi.nix { inherit pkgs utils; };
      innerWidth = width - 2;
      
      # Format content lines (account for ANSI codes)
      formatLine = line:
        let
          visualLen = utils.visualLength line;
          paddingNeeded = if visualLen < innerWidth
                          then innerWidth - visualLen
                          else 0;
          padded = line + utils.repeat paddingNeeded " ";
        in chars.vertical + padded + chars.vertical;


      
      # Title bar
      makeTitle = title:
        if title == null then horizontalLine innerWidth chars
        else let titleStr = " ${title} ";
                 coloredTitle = if titleColor != null 
                               then "${ansi.fgHex titleColor}${titleStr}${ansi.resetAll}"
                               else titleStr;
                 titleLen = builtins.stringLength titleStr;
                 rightPad = innerWidth - titleLen - 1;
             in chars.horizontal + coloredTitle + horizontalLine (if rightPad > 0 then rightPad else 0) chars;
      
      # Build structure
      topLine = chars.topLeft + makeTitle mainTitle + chars.topRight;
      mainLines = map formatLine mainContent;
      dividerLine = chars.leftT + makeTitle subTitle + chars.rightT;
      subLines = map formatLine subContent;
      bottomLine = chars.bottomLeft + horizontalLine innerWidth chars + chars.bottomRight;
      
    in [topLine] ++ mainLines ++ [dividerLine] ++ subLines ++ [bottomLine];
}

