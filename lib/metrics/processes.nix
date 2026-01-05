# Process list metrics processing
{ pkgs, utils, platform }:

rec {
  # ============================================================================
  # Process Sorting
  # ============================================================================
  
  # Sort by CPU usage (descending)
  sortByCpu = processes:
    utils.sortByAttrDesc "cpuPercent" processes;

  # Sort by memory usage (descending)
  sortByMemory = processes:
    utils.sortByAttrDesc "memPercent" processes;

  # Sort by PID
  sortByPid = processes:
    utils.sortByAttr "pid" processes;

  # Sort by name
  sortByName = processes:
    utils.sortByAttr "name" processes;

  # Generic sort function
  sortBy = sortKey: processes:
    if sortKey == "cpu" then sortByCpu processes
    else if sortKey == "mem" || sortKey == "memory" then sortByMemory processes
    else if sortKey == "pid" then sortByPid processes
    else if sortKey == "name" then sortByName processes
    else sortByCpu processes;  # Default to CPU

  # ============================================================================
  # Process Filtering
  # ============================================================================
  
  # Filter out kernel/system processes
  filterUserProcesses = processes:
    builtins.filter (p: 
      p.name != "" && 
      p.name != "kernel" &&
      !utils.contains "[" p.name  # Linux kernel threads
    ) processes;

  # Filter by minimum CPU usage
  filterByCpuThreshold = threshold: processes:
    builtins.filter (p: (p.cpuPercent or 0) >= threshold) processes;

  # Filter by minimum memory usage
  filterByMemThreshold = threshold: processes:
    builtins.filter (p: (p.memPercent or 0) >= threshold) processes;

  # Search by name (case-insensitive substring match)
  searchByName = query: processes:
    if query == "" then processes
    else let
      queryLower = utils.toLower query;
    in builtins.filter (p: 
      let nameLower = utils.toLower (p.name or "");
      in utils.contains queryLower nameLower
    ) processes;

  # ============================================================================
  # Process Formatting
  # ============================================================================
  
  # Format a single process for display
  formatProcess = { process, pidWidth ? 7, userWidth ? 8, cpuWidth ? 5, memWidth ? 5, nameWidth ? 30 }:
    let
      pid = utils.padLeft pidWidth (toString (process.pid or 0));
      user = utils.padRight userWidth (utils.truncate userWidth (process.user or "?"));
      cpu = utils.padLeft cpuWidth (toString (utils.round 1 (process.cpuPercent or 0)));
      mem = utils.padLeft memWidth (toString (utils.round 1 (process.memPercent or 0)));
      name = utils.padRight nameWidth (utils.truncate nameWidth (process.name or "unknown"));
      
    in {
      pid = pid;
      user = user;
      cpu = cpu;
      mem = mem;
      name = name;
      line = "${pid} ${user} ${cpu} ${mem}  ${name}";
    };

  # Format process list header
  formatHeader = { pidWidth ? 7, userWidth ? 8, cpuWidth ? 5, memWidth ? 5, nameWidth ? 30 }:
    let
      pid = utils.padLeft pidWidth "PID";
      user = utils.padRight userWidth "USER";
      cpu = utils.padLeft cpuWidth "CPU%";
      mem = utils.padLeft memWidth "MEM%";
      name = utils.padRight nameWidth "NAME";
    in "${pid} ${user} ${cpu} ${mem}  ${name}";

  # ============================================================================
  # CPU Percentage Calculation
  # ============================================================================
  
  # Calculate CPU percentages from raw CPU times
  # On macOS, cpuPercent is already set by ps, so we use it directly
  # On Linux, we need to calculate from cpuTime deltas
  calculateCpuPercent = { processes, prevProcesses ? [], interval ? 2, numCpus ? 1 }:
    let
      prevMap = builtins.listToAttrs (
        map (p: { name = toString p.pid; value = p; }) prevProcesses
      );
      
      calcProcess = p:
        let
          # If process already has a non-zero cpuPercent (macOS), use it
          hasCpuPercent = (p.cpuPercent or 0) > 0;
          
          prev = prevMap.${toString p.pid} or null;
          
          # cpuTime is in jiffies (typically 100 per second on Linux)
          cpuTimeDelta = if prev != null then (p.cpuTime or 0) - (prev.cpuTime or 0) else 0;
          
          # Calculate percentage: (delta / (interval * jiffies_per_sec)) * 100 / num_cpus
          # Assuming 100 jiffies per second
          calculatedPct = if interval > 0 
                          then (cpuTimeDelta * 100.0) / (interval * 100 * numCpus)
                          else 0;
          
          # Use existing cpuPercent if available, otherwise calculate
          finalPct = if hasCpuPercent then p.cpuPercent else calculatedPct;
          
        in p // {
          cpuPercent = utils.clamp 0 100 finalPct;
          cpuTime = p.cpuTime or 0;
        };
      
    in map calcProcess processes;

  # ============================================================================
  # Memory Percentage Calculation
  # ============================================================================
  
  # Calculate memory percentages
  calculateMemPercent = { processes, totalMemory }:
    let
      safeTotalMem = if totalMemory == 0 then 1 else totalMemory;
      
      calcProcess = p:
        let
          memKb = p.memoryKb or 0;
          memPct = (memKb * 100.0) / (safeTotalMem / 1024);
        in p // {
          memPercent = utils.clamp 0 100 memPct;
        };
      
    in map calcProcess processes;

  # ============================================================================
  # Main Process Metrics Function
  # ============================================================================
  
  getMetrics = { prevState ? {}, sortKey ? "cpu", maxProcesses ? 20, interval ? 2, processFilter ? "" }:
    let
      # Get raw process list from platform
      rawProcesses = platform.getProcessList;
      
      # Get memory info for percentage calculation
      memInfo = platform.getMemoryInfo;
      totalMemory = memInfo.total or 17179869184;  # Default 16GB
      
      # Get CPU info for percentage calculation
      cpuInfo = platform.getCpuInfo;
      numCpus = cpuInfo.coreCount or 8;
      
      # Get previous process data
      prevProcesses = prevState.processes or [];
      
      # Calculate CPU percentages
      withCpuPct = calculateCpuPercent { 
        processes = rawProcesses; 
        inherit prevProcesses interval numCpus;
      };
      
      # Calculate memory percentages
      withMemPct = calculateMemPercent { 
        processes = withCpuPct; 
        inherit totalMemory;
      };
      
      # Filter and sort
      userFiltered = filterUserProcesses withMemPct;
      nameFiltered = searchByName processFilter userFiltered;
      sorted = sortBy sortKey nameFiltered;
      
      # Take top N
      topProcesses = utils.take maxProcesses sorted;
      
      # Format for display
      formatted = map (p: formatProcess { process = p; }) topProcesses;
      
      # Calculate summary stats
      totalCpu = utils.sum (map (p: p.cpuPercent or 0) nameFiltered);
      totalMem = utils.sum (map (p: p.memPercent or 0) nameFiltered);
      
    in {
      processes = topProcesses;
      formatted = formatted;
      
      # Summary
      count = builtins.length nameFiltered;
      filtered = processFilter != "";
      totalCpuUsage = totalCpu;
      totalMemUsage = totalMem;
      
      # Header
      header = formatHeader {};
      
      # State data to persist
      stateData = {
        processes = map (p: { 
          pid = p.pid; 
          cpuTime = p.cpuTime or 0; 
        }) rawProcesses;
      };
    };

  # ============================================================================
  # Process Summary
  # ============================================================================
  
  # Get quick summary of process stats
  getSummary = processes:
    let
      running = builtins.filter (p: (p.state or "") == "R") processes;
      sleeping = builtins.filter (p: (p.state or "") == "S") processes;
      
    in {
      total = builtins.length processes;
      running = builtins.length running;
      sleeping = builtins.length sleeping;
    };
}


