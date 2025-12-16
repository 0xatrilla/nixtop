# Memory metrics processing
{ pkgs, utils, platform }:

rec {
  # ============================================================================
  # Memory Formatting
  # ============================================================================
  
  # Format memory values for display
  formatMemory = memInfo:
    let
      total = memInfo.total or 0;
      used = memInfo.used or 0;
      available = memInfo.available or 0;
      cached = memInfo.cached or 0;
      buffers = memInfo.buffers or 0;
      
      usedPct = memInfo.usedPercent or 0;
      
    in {
      totalStr = utils.formatBytes total;
      usedStr = utils.formatBytes used;
      availableStr = utils.formatBytes available;
      cachedStr = utils.formatBytes cached;
      buffersStr = utils.formatBytes buffers;
      
      usedPercent = usedPct;
      
      # Summary line
      summary = "${utils.formatBytes used} / ${utils.formatBytes total}";
      
      # Detailed breakdown
      breakdown = {
        used = { value = used; pct = usedPct; label = "Used"; };
        cached = { value = cached; pct = utils.percentage cached total; label = "Cached"; };
        available = { value = available; pct = utils.percentage available total; label = "Available"; };
      };
    };

  # Format swap values
  formatSwap = swapInfo:
    let
      total = swapInfo.total or 0;
      used = swapInfo.used or 0;
      free = swapInfo.free or 0;
      
      usedPct = if total > 0 then utils.percentage used total else 0;
      
    in {
      totalStr = utils.formatBytes total;
      usedStr = utils.formatBytes used;
      freeStr = utils.formatBytes free;
      
      usedPercent = usedPct;
      
      # Summary
      summary = if total == 0 then "No swap"
                else "${utils.formatBytes used} / ${utils.formatBytes total}";
      
      # Whether swap is in use
      active = used > 0;
    };

  # ============================================================================
  # Memory History
  # ============================================================================
  
  updateHistory = { history, value, maxLen ? 60 }:
    let
      newHistory = history ++ [value];
      len = builtins.length newHistory;
    in if len > maxLen 
       then utils.drop (len - maxLen) newHistory
       else newHistory;

  # ============================================================================
  # Memory Pressure Indicators
  # ============================================================================
  
  # Determine memory pressure level
  getPressureLevel = usedPct:
    if usedPct >= 90 then "critical"
    else if usedPct >= 75 then "high"
    else if usedPct >= 50 then "medium"
    else "low";

  # Get color based on pressure
  getPressureColor = usedPct:
    let
      colors = import ../ui/colors.nix { inherit pkgs utils; };
    in colors.getMemoryColor usedPct;

  # ============================================================================
  # Main Memory Metrics Function
  # ============================================================================
  
  getMetrics = { prevState ? {} }:
    let
      # Get raw data from platform
      memInfo = platform.getMemoryInfo;
      
      # Get previous history
      prevHistory = prevState.memHistory or [];
      
      # Format values
      memory = formatMemory memInfo;
      swap = formatSwap (memInfo.swap or { total = 0; used = 0; free = 0; });
      
      # Update history
      history = updateHistory {
        history = prevHistory;
        value = memory.usedPercent;
        maxLen = 60;
      };
      
      # Pressure level
      pressure = getPressureLevel memory.usedPercent;
      
    in {
      inherit memory swap history pressure;
      
      # Quick access values
      usedPercent = memory.usedPercent;
      swapUsedPercent = swap.usedPercent;
      
      # Raw info for reference
      raw = memInfo;
      
      # State data to persist
      stateData = {
        memHistory = history;
      };
    };

  # ============================================================================
  # macOS Specific Memory Info
  # ============================================================================
  
  # Format macOS-specific memory breakdown
  formatDarwinMemory = memInfo:
    let
      wired = memInfo.wired or 0;
      active = memInfo.active or 0;
      inactive = memInfo.inactive or 0;
      compressed = memInfo.compressed or 0;
      total = memInfo.total or 1;
      
    in {
      wired = { 
        value = wired; 
        pct = utils.percentage wired total; 
        label = "Wired";
        description = "Memory that can't be swapped out";
      };
      active = { 
        value = active; 
        pct = utils.percentage active total; 
        label = "Active";
        description = "Memory currently in use";
      };
      inactive = { 
        value = inactive; 
        pct = utils.percentage inactive total; 
        label = "Inactive";
        description = "Memory not recently used";
      };
      compressed = { 
        value = compressed; 
        pct = utils.percentage compressed total; 
        label = "Compressed";
        description = "Memory compressed to save space";
      };
    };
}



