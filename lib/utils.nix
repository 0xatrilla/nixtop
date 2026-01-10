# nixmon utilities - String, number, and list helper functions
{ pkgs }:

rec {
  # ============================================================================
  # String utilities
  # ============================================================================
  
  # Pad a string to a fixed width (left-aligned)
  padRight = width: str:
    let
      len = builtins.stringLength str;
      padding = if len >= width then [] else builtins.genList (_: " ") (width - len);
    in str + builtins.concatStringsSep "" padding;

  # Pad a string to a fixed width (right-aligned)
  padLeft = width: str:
    let
      len = builtins.stringLength str;
      padding = if len >= width then [] else builtins.genList (_: " ") (width - len);
    in builtins.concatStringsSep "" padding + str;

  # Center a string within a width
  center = width: str:
    let
      len = builtins.stringLength str;
      totalPad = if len >= width then 0 else width - len;
      leftPad = totalPad / 2;
      rightPad = totalPad - leftPad;
      leftSpaces = builtins.concatStringsSep "" (builtins.genList (_: " ") leftPad);
      rightSpaces = builtins.concatStringsSep "" (builtins.genList (_: " ") rightPad);
    in leftSpaces + str + rightSpaces;

  # Strip ANSI escape codes from a string (for length calculation)
  stripAnsi = str:
    let
      len = builtins.stringLength str;
      isEsc = c: c == "\x1b";
      # Simple state machine to remove escape sequences
      process = idx: inEscape: acc:
        if idx >= len then acc
        else let
          char = builtins.substring idx 1 str;
        in
          if inEscape then
            # In escape sequence, look for terminator (letter)
            if builtins.match "[a-zA-Z]" char != null
            then process (idx + 1) false acc
            else process (idx + 1) true acc
          else if isEsc char
          then process (idx + 1) true acc
          else process (idx + 1) false (acc + char);
    in process 0 false "";

  # Calculate visual length (excluding ANSI codes)
  visualLength = str:
    builtins.stringLength (stripAnsi str);

  # Truncate a string to max length with ellipsis
  # Note: This is not ANSI-aware - use with plain strings or pre-calculated widths
  truncate = maxLen: str:
    let len = builtins.stringLength str;
    in if len <= maxLen then str
       else builtins.substring 0 (maxLen - 1) str + "…";

  # Repeat a string n times
  repeat = n: str:
    if n <= 0 then ""
    else builtins.concatStringsSep "" (builtins.genList (_: str) n);

  # Split string by delimiter (simple implementation)
  split = delim: str:
    let
      len = builtins.stringLength str;
      delimLen = builtins.stringLength delim;
      
      findDelim = start:
        if start > len - delimLen then null
        else if builtins.substring start delimLen str == delim then start
        else findDelim (start + 1);
      
      splitAt = pos:
        let before = builtins.substring 0 pos str;
            after = builtins.substring (pos + delimLen) (len - pos - delimLen) str;
        in [before] ++ split delim after;
    in
      if delimLen == 0 then [str]
      else let pos = findDelim 0;
           in if pos == null then [str]
              else splitAt pos;

  # Split string by whitespace (handles multiple spaces)
  splitWhitespace = str:
    builtins.filter (s: s != "") (builtins.split "[ \t\n]+" str);

  # Join list with separator
  join = sep: list:
    builtins.concatStringsSep sep (map toString list);

  # Trim leading and trailing whitespace
  trim = str:
    let
      chars = builtins.stringLength str;
      findStart = i:
        if i >= chars then chars
        else let c = builtins.substring i 1 str;
             in if c == " " || c == "\t" || c == "\n" then findStart (i + 1)
                else i;
      findEnd = i:
        if i < 0 then 0
        else let c = builtins.substring i 1 str;
             in if c == " " || c == "\t" || c == "\n" then findEnd (i - 1)
                else i + 1;
      start = findStart 0;
      end = findEnd (chars - 1);
    in if start >= end then ""
       else builtins.substring start (end - start) str;
  
  # Convert string to lowercase (simple ASCII-only implementation)
  toLower = str:
    let
      len = builtins.stringLength str;
      convertChar = i:
        if i >= len then ""
        else let
          c = builtins.substring i 1 str;
          code = builtins.substring 0 1 c;
          # Simple ASCII conversion: A-Z (65-90) -> a-z (97-122)
          # In Nix, we can't easily do character code conversion, so use string replacement
          lower = builtins.replaceStrings 
            ["A" "B" "C" "D" "E" "F" "G" "H" "I" "J" "K" "L" "M" "N" "O" "P" "Q" "R" "S" "T" "U" "V" "W" "X" "Y" "Z"]
            ["a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z"]
            c;
        in lower + convertChar (i + 1);
    in convertChar 0;

  # Check if string contains substring
  contains = needle: haystack:
    let
      hLen = builtins.stringLength haystack;
      nLen = builtins.stringLength needle;
      check = i:
        if i > hLen - nLen then false
        else if builtins.substring i nLen haystack == needle then true
        else check (i + 1);
    in if nLen == 0 then true
       else if nLen > hLen then false
       else check 0;

  # ============================================================================
  # Number utilities
  # ============================================================================

  # Parse integer from string (handles leading/trailing whitespace)
  parseInt = str:
    let 
      cleaned = trim str;
      # Only keep numeric characters (and minus sign)
      isNumeric = builtins.match "^-?[0-9]+$" cleaned != null;
      result = if isNumeric then builtins.tryEval (builtins.fromJSON cleaned) else { success = false; };
    in if cleaned == "" then 0
       else if result.success then result.value
       else 0;

  # Parse float from string
  parseFloat = str:
    let 
      cleaned = trim str;
      # Only keep numeric characters (including decimal point and minus)
      isNumeric = builtins.match "^-?[0-9]+\\.?[0-9]*$" cleaned != null;
      result = if isNumeric then builtins.tryEval (builtins.fromJSON cleaned) else { success = false; };
    in if cleaned == "" then 0.0
       else if result.success then result.value
       else 0.0;

  # Safe division (returns 0 if divisor is 0)
  safeDiv = a: b:
    if b == 0 then 0 else a / b;

  # Calculate percentage
  percentage = part: total:
    if total == 0 then 0
    else (part * 100) / total;

  # Round to n decimal places
  round = decimals: num:
    let
      factor = pow 10 decimals;
      rounded = builtins.floor (num * factor + 0.5);
    in rounded / factor;

  # Power function
  pow = base: exp:
    if exp == 0 then 1
    else if exp < 0 then 1.0 / (pow base (-exp))
    else base * pow base (exp - 1);

  # Clamp value between min and max
  clamp = min: max: val:
    if val < min then min
    else if val > max then max
    else val;

  # Format bytes to human readable
  formatBytes = bytes:
    let
      units = ["B" "KB" "MB" "GB" "TB" "PB"];
      findUnit = val: idx:
        if idx >= builtins.length units - 1 then { inherit val idx; }
        else if val < 1024 then { inherit val idx; }
        else findUnit (val / 1024.0) (idx + 1);
      result = findUnit bytes 0;
      rounded = round 1 result.val;
    in "${toString rounded} ${builtins.elemAt units result.idx}";

  # Format bytes per second
  formatBytesPerSec = bytes:
    "${formatBytes bytes}/s";

  # Format percentage with symbol
  formatPercent = pct:
    "${toString (round 1 pct)}%";

  # Format number with thousands separator
  formatNumber = num:
    let
      str = toString (builtins.floor num);
      len = builtins.stringLength str;
      insertCommas = i: acc:
        if i >= len then acc
        else
          let
            char = builtins.substring (len - 1 - i) 1 str;
            sep = if i > 0 && (i / 3) * 3 == i then "," else "";
          in insertCommas (i + 1) (char + sep + acc);
    in insertCommas 0 "";

  # ============================================================================
  # List utilities
  # ============================================================================

  # Get first n elements of list
  take = n: list:
    let len = builtins.length list;
    in if n >= len then list
       else builtins.genList (i: builtins.elemAt list i) n;

  # Drop first n elements of list
  drop = n: list:
    let len = builtins.length list;
    in if n >= len then []
       else builtins.genList (i: builtins.elemAt list (i + n)) (len - n);

  # Zip two lists together
  zip = a: b:
    let len = min (builtins.length a) (builtins.length b);
    in builtins.genList (i: {
      fst = builtins.elemAt a i;
      snd = builtins.elemAt b i;
    }) len;

  # Range from start to end (exclusive)
  range = start: end:
    if start >= end then []
    else builtins.genList (i: start + i) (end - start);

  # Sum of list
  sum = list:
    builtins.foldl' (a: b: a + b) 0 list;

  # Reverse list
  reverse = list:
    builtins.foldl' (acc: item: [item] ++ acc) [] list;
 
  # Maximum of list
  max = list:
    if list == [] then 0
    else builtins.foldl' (a: b: if a > b then a else b) (builtins.head list) list;

  # Minimum of list  
  min = list:
    if list == [] then 0
    else builtins.foldl' (a: b: if a < b then a else b) (builtins.head list) list;

  # Average of list
  avg = list:
    if list == [] then 0
    else (sum list) / (builtins.length list);

  # Sort list by comparison function
  sortBy = compare: list:
    let
      len = builtins.length list;
      # Simple insertion sort for small lists
      insert = x: sorted:
        if sorted == [] then [x]
        else let head = builtins.head sorted;
                 tail = builtins.tail sorted;
             in if compare x head <= 0 then [x] ++ sorted
                else [head] ++ insert x tail;
    in builtins.foldl' (sorted: x: insert x sorted) [] list;

  # Sort by attribute
  sortByAttr = attr: list:
    sortBy (a: b:
      if a.${attr} < b.${attr} then -1
      else if a.${attr} > b.${attr} then 1
      else 0
    ) list;

  # Reverse sort by attribute (descending)
  sortByAttrDesc = attr: list:
    sortBy (a: b:
      if a.${attr} > b.${attr} then -1
      else if a.${attr} < b.${attr} then 1
      else 0
    ) list;

  # Find element matching predicate
  find = pred: list:
    let
      filtered = builtins.filter pred list;
    in if filtered == [] then null
       else builtins.head filtered;

  # Group list by key function
  groupBy = keyFn: list:
    builtins.foldl' (acc: item:
      let key = keyFn item;
          existing = acc.${key} or [];
      in acc // { ${key} = existing ++ [item]; }
    ) {} list;

  # ============================================================================
  # Attribute set utilities
  # ============================================================================

  # Merge two attribute sets (second overrides first)
  merge = a: b: a // b;

  # Deep merge two attribute sets
  deepMerge = a: b:
    let
      aNames = builtins.attrNames a;
      bNames = builtins.attrNames b;
      allNames = aNames ++ (builtins.filter (n: !builtins.elem n aNames) bNames);
    in builtins.listToAttrs (map (name:
      let
        aVal = a.${name} or null;
        bVal = b.${name} or null;
        merged =
          if aVal == null then bVal
          else if bVal == null then aVal
          else if builtins.isAttrs aVal && builtins.isAttrs bVal then deepMerge aVal bVal
          else bVal;
      in { inherit name; value = merged; }
    ) allNames);

  # Get attribute with default value
  getOr = default: attr: set:
    set.${attr} or default;

  # ============================================================================
  # Platform detection
  # ============================================================================

  # Detect current platform
  currentSystem = builtins.currentSystem or "x86_64-linux";
  
  isLinux = builtins.match ".*-linux" currentSystem != null;
  isDarwin = builtins.match ".*-darwin" currentSystem != null;
  
  platformName = if isDarwin then "darwin" else "linux";
}

