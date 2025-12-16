# CPU metrics processing
{ pkgs, utils, platform }:

rec {
  # ============================================================================
  # CPU Usage Calculation
  # ============================================================================
  
  # Calculate CPU percentage from current and previous raw values
  # cpuData: current CPU times from platform
  # prevData: previous CPU times (from state file)
  # Returns: list of { name, pct, user, system, idle }
  #
  # On macOS, the platform provides percentages directly in the 'active' field
  # On Linux, we need to calculate deltas from cumulative counters
  calculateUsage = { cpuData, prevData ? [] }:
    let
      # Create a lookup map from previous data
      prevMap = builtins.listToAttrs (map (c: { name = c.name; value = c; }) prevData);
      
      # Check if this is macOS-style data (total = 100) or Linux-style (cumulative counters)
      isMacOS = cpuData != [] && (builtins.head cpuData).total == 100;
      
      # Calculate percentage for a single CPU entry
      calcOne = current:
        let
          prev = prevMap.${current.name} or null;
          
          # For macOS, use the active percentage directly
          macOSResult = {
            name = current.name;
            pct = utils.clamp 0 100 current.active;
            user = utils.clamp 0 100 current.user;
            system = utils.clamp 0 100 current.system;
            idle = utils.clamp 0 100 current.idle;
            iowait = utils.clamp 0 100 (current.iowait or 0);
            raw = current;
          };
          
          # For Linux, calculate delta from previous
          linuxResult = if prev == null then {
            name = current.name;
            pct = 0;
            user = 0;
            system = 0;
            idle = 100;
            iowait = 0;
            raw = current;
          }
          else let
            # Calculate deltas
            totalDelta = current.total - prev.total;
            activeDelta = current.active - prev.active;
            idleDelta = current.idleTotal - prev.idleTotal;
            userDelta = current.user - prev.user;
            systemDelta = current.system - prev.system;
            iowaitDelta = (current.iowait or 0) - (prev.iowait or 0);
            
            # Calculate percentages (avoid division by zero)
            safeTotalDelta = if totalDelta == 0 then 1 else totalDelta;
            
            pct = (activeDelta * 100) / safeTotalDelta;
            userPct = (userDelta * 100) / safeTotalDelta;
            systemPct = (systemDelta * 100) / safeTotalDelta;
            idlePct = (idleDelta * 100) / safeTotalDelta;
            iowaitPct = (iowaitDelta * 100) / safeTotalDelta;
            
          in {
            name = current.name;
            pct = utils.clamp 0 100 pct;
            user = utils.clamp 0 100 userPct;
            system = utils.clamp 0 100 systemPct;
            idle = utils.clamp 0 100 idlePct;
            iowait = utils.clamp 0 100 iowaitPct;
            raw = current;
          };
          
        in if isMacOS then macOSResult else linuxResult;
      
    in map calcOne cpuData;

  # ============================================================================
  # CPU Info Formatting
  # ============================================================================
  
  # Get overall CPU percentage (first entry is usually total)
  getOverallUsage = cpuUsage:
    let total = utils.find (c: c.name == "cpu") cpuUsage;
    in if total != null then total.pct else 0;

  # Get per-core usage (filter out the "cpu" total entry)
  getCoreUsage = cpuUsage:
    builtins.filter (c: c.name != "cpu") cpuUsage;

  # Format CPU info for display
  formatCpuInfo = cpuInfo:
    let
      model = cpuInfo.model or "Unknown CPU";
      coreCount = cpuInfo.coreCount or 0;
      freq = cpuInfo.frequency or 0;
      
      # Truncate long model names
      shortModel = utils.truncate 30 model;
      
      # Format frequency
      freqStr = if freq > 1000 then "${toString (utils.round 1 (freq / 1000))} GHz"
                else if freq > 0 then "${toString (builtins.floor freq)} MHz"
                else "";
      
    in {
      model = shortModel;
      cores = "${toString coreCount} cores";
      frequency = freqStr;
      summary = "${shortModel} (${toString coreCount} cores)";
    };

  # ============================================================================
  # CPU History for Sparklines
  # ============================================================================
  
  # Add current value to history, keeping last N values
  updateHistory = { history, value, maxLen ? 60 }:
    let
      newHistory = history ++ [value];
      len = builtins.length newHistory;
    in if len > maxLen 
       then utils.drop (len - maxLen) newHistory
       else newHistory;

  # ============================================================================
  # Main CPU Metrics Function
  # ============================================================================
  
  # Get all CPU metrics
  # prevState: previous state from JSON file
  # Returns: { usage, info, overall, cores, history }
  getMetrics = { prevState ? {} }:
    let
      # Get raw data from platform
      rawUsage = platform.getCpuUsage;
      info = platform.getCpuInfo;
      
      # Get previous CPU data from state
      prevCpuData = prevState.cpuRaw or [];
      prevHistory = prevState.cpuHistory or [];
      
      # Calculate usage percentages
      usage = calculateUsage { cpuData = rawUsage; prevData = prevCpuData; };
      
      # Extract overall and per-core
      overall = getOverallUsage usage;
      cores = getCoreUsage usage;
      
      # Update history
      history = updateHistory { 
        history = prevHistory; 
        value = overall; 
        maxLen = 60; 
      };
      
      # Format info
      formattedInfo = formatCpuInfo info;
      
    in {
      inherit usage overall cores history info;
      formatted = formattedInfo;
      
      # Raw data to save to state file
      stateData = {
        cpuRaw = rawUsage;
        cpuHistory = history;
      };
    };
}


