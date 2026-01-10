# Linux platform data collection
# Reads from /proc and /sys filesystems
{ pkgs, utils }:

rec {
  # ============================================================================
  # File reading helpers
  # ============================================================================
  
  # Safely read a file, returning empty string if it doesn't exist
  # Must check pathExists first because tryEval doesn't catch readFile errors
  readFileSafe = path:
    if builtins.pathExists path
    then builtins.readFile path
    else "";

  # Read file and split into lines
  readLines = path:
    let content = readFileSafe path;
    in if content == "" then []
       else builtins.filter (l: l != "") (utils.split "\n" content);

  # ============================================================================
  # CPU Information
  # ============================================================================
  
  # Parse /proc/cpuinfo for CPU model and core count
  getCpuInfo = 
    let
      lines = readLines "/proc/cpuinfo";
      
      # Find model name
      modelLine = utils.find (l: utils.contains "model name" l) lines;
      model = if modelLine == null then "Unknown CPU"
              else let parts = utils.split ":" modelLine;
                   in if builtins.length parts >= 2 
                      then utils.trim (builtins.elemAt parts 1)
                      else "Unknown CPU";
      
      # Count processor entries for core count
      processorLines = builtins.filter (l: utils.contains "processor" l && utils.contains ":" l) lines;
      coreCount = builtins.length processorLines;
      
      # Get CPU frequency from /proc/cpuinfo or /sys
      freqLine = utils.find (l: utils.contains "cpu MHz" l) lines;
      freq = if freqLine == null then 0
             else let parts = utils.split ":" freqLine;
                  in if builtins.length parts >= 2 
                     then utils.parseFloat (utils.trim (builtins.elemAt parts 1))
                     else 0;
    in {
      inherit model coreCount;
      frequency = freq;
    };

  # Parse /proc/stat for CPU usage times
  # Returns: { total, idle, user, system, ... } for each CPU
  getCpuUsage = 
    let
      lines = readLines "/proc/stat";
      
      # Parse a single cpu line
      parseCpuLine = line:
        let
          parts = builtins.filter (p: p != "") (utils.split " " line);
          name = builtins.elemAt parts 0;
          # Values: user, nice, system, idle, iowait, irq, softirq, steal, guest, guest_nice
          user = if builtins.length parts > 1 then utils.parseInt (builtins.elemAt parts 1) else 0;
          nice = if builtins.length parts > 2 then utils.parseInt (builtins.elemAt parts 2) else 0;
          system = if builtins.length parts > 3 then utils.parseInt (builtins.elemAt parts 3) else 0;
          idle = if builtins.length parts > 4 then utils.parseInt (builtins.elemAt parts 4) else 0;
          iowait = if builtins.length parts > 5 then utils.parseInt (builtins.elemAt parts 5) else 0;
          irq = if builtins.length parts > 6 then utils.parseInt (builtins.elemAt parts 6) else 0;
          softirq = if builtins.length parts > 7 then utils.parseInt (builtins.elemAt parts 7) else 0;
          steal = if builtins.length parts > 8 then utils.parseInt (builtins.elemAt parts 8) else 0;
          
          total = user + nice + system + idle + iowait + irq + softirq + steal;
          idleTotal = idle + iowait;
          active = total - idleTotal;
        in {
          inherit name user nice system idle iowait irq softirq steal total;
          idleTotal = idleTotal;
          active = active;
        };
      
      # Filter cpu lines (cpu, cpu0, cpu1, etc.)
      cpuLines = builtins.filter (l: builtins.substring 0 3 l == "cpu") lines;
      
    in map parseCpuLine cpuLines;

  # ============================================================================
  # Memory Information
  # ============================================================================
  
  # Parse /proc/meminfo
  getMemoryInfo = 
    let
      lines = readLines "/proc/meminfo";
      
      # Parse a meminfo line into name and value (in kB)
      parseLine = line:
        let
          parts = utils.split ":" line;
          name = if builtins.length parts >= 1 then utils.trim (builtins.elemAt parts 0) else "";
          valuePart = if builtins.length parts >= 2 then utils.trim (builtins.elemAt parts 1) else "0";
          value = utils.parseInt (builtins.head (utils.split " " valuePart));
        in { inherit name value; };
      
      parsed = map parseLine lines;
      
      # Create attribute set from parsed lines
      memMap = builtins.listToAttrs (map (p: { name = p.name; value = p.value; }) parsed);
      
      # Extract key values (all in kB)
      total = memMap.MemTotal or 0;
      free = memMap.MemFree or 0;
      available = memMap.MemAvailable or free;
      buffers = memMap.Buffers or 0;
      cached = memMap.Cached or 0;
      sReclaimable = memMap.SReclaimable or 0;
      
      # Calculate used memory
      used = total - available;
      
      # Swap
      swapTotal = memMap.SwapTotal or 0;
      swapFree = memMap.SwapFree or 0;
      swapUsed = swapTotal - swapFree;
      
    in {
      # All values in bytes (convert from kB)
      total = total * 1024;
      free = free * 1024;
      available = available * 1024;
      used = used * 1024;
      buffers = buffers * 1024;
      cached = (cached + sReclaimable) * 1024;
      
      swap = {
        total = swapTotal * 1024;
        free = swapFree * 1024;
        used = swapUsed * 1024;
      };
      
      # Percentages
      usedPercent = utils.percentage used total;
      swapUsedPercent = if swapTotal > 0 then utils.percentage swapUsed swapTotal else 0;
    };

  # ============================================================================
  # Disk Information
  # ============================================================================
  
  # Parse /proc/mounts and df-like info
  getDiskInfo = 
    let
      # Read mount points
      mounts = readLines "/proc/mounts";
      
      # Parse a mount line
      parseMount = line:
        let
          parts = builtins.filter (p: p != "") (utils.split " " line);
        in if builtins.length parts >= 3 then {
          device = builtins.elemAt parts 0;
          mountPoint = builtins.elemAt parts 1;
          fsType = builtins.elemAt parts 2;
        } else null;
      
      # Filter real filesystems (not virtual)
      isRealFs = m: m != null && 
                    builtins.substring 0 1 m.device == "/" &&
                    !utils.contains "snap" m.mountPoint &&
                    !utils.contains "docker" m.mountPoint;
      
      realMounts = builtins.filter isRealFs (map parseMount mounts);
      
      # Read disk stats from /proc/diskstats
      diskStats = readLines "/proc/diskstats";
      
      # Parse diskstats line
      parseDiskStat = line:
        let
          parts = builtins.filter (p: p != "") (utils.split " " line);
        in if builtins.length parts >= 14 then {
          name = builtins.elemAt parts 2;
          readsCompleted = utils.parseInt (builtins.elemAt parts 3);
          sectorsRead = utils.parseInt (builtins.elemAt parts 5);
          writesCompleted = utils.parseInt (builtins.elemAt parts 7);
          sectorsWritten = utils.parseInt (builtins.elemAt parts 9);
        } else null;
      
      diskStatsParsed = builtins.filter (d: d != null) (map parseDiskStat diskStats);
      
    in {
      mounts = realMounts;
      stats = diskStatsParsed;
    };

  # ============================================================================
  # Network Information
  # ============================================================================
  
  # Parse /proc/net/dev
  getNetworkInfo = 
    let
      lines = readLines "/proc/net/dev";
      
      # Skip header lines
      dataLines = utils.drop 2 lines;
      
      # Parse a network interface line
      parseInterface = line:
        let
          # Split by colon first to separate interface name
          colonParts = utils.split ":" line;
          name = if builtins.length colonParts >= 1 
                 then utils.trim (builtins.elemAt colonParts 0) 
                 else "";
          rest = if builtins.length colonParts >= 2 
                 then builtins.elemAt colonParts 1 
                 else "";
          
          # Split the rest by whitespace
          parts = builtins.filter (p: p != "") (utils.split " " rest);
          
          # Values: rx_bytes, rx_packets, rx_errs, rx_drop, rx_fifo, rx_frame, rx_compressed, rx_multicast,
          #         tx_bytes, tx_packets, tx_errs, tx_drop, tx_fifo, tx_colls, tx_carrier, tx_compressed
          rxBytes = if builtins.length parts > 0 then utils.parseInt (builtins.elemAt parts 0) else 0;
          rxPackets = if builtins.length parts > 1 then utils.parseInt (builtins.elemAt parts 1) else 0;
          txBytes = if builtins.length parts > 8 then utils.parseInt (builtins.elemAt parts 8) else 0;
          txPackets = if builtins.length parts > 9 then utils.parseInt (builtins.elemAt parts 9) else 0;
          
        in if name == "" then null else {
          inherit name rxBytes rxPackets txBytes txPackets;
        };
      
      interfaces = builtins.filter (i: i != null && i.name != "lo") (map parseInterface dataLines);
      
    in {
      inherit interfaces;
    };

  # ============================================================================
  # Process List
  # ============================================================================
  
  # List processes from /proc
  getProcessList = 
    let
      # Get list of numeric directories in /proc (PIDs)
      procDir = builtins.tryEval (builtins.readDir "/proc");
      entries = if procDir.success then procDir.value else {};
      
      # Filter to only numeric (PID) directories
      isNumeric = s: builtins.match "[0-9]+" s != null;
      pidDirs = builtins.filter isNumeric (builtins.attrNames entries);
      pidNums = map utils.parseInt pidDirs;
      sortedPidNums = utils.sortBy (a: b: if a < b then -1 else if a > b then 1 else 0) pidNums;
      sortedPidDirs = map toString sortedPidNums;
      
      # Read process info for a single PID
      readProcess = pid:
        let
          statContent = readFileSafe "/proc/${pid}/stat";
        in if statContent == "" then null else
          let
            # Parse stat file using a regex to avoid splitting the comm field
            # Format: pid (comm) state ppid pgrp session tty_nr tpgid flags minflt cminflt majflt cmajflt utime stime ...
            statMatch = builtins.match "^[0-9]+ \((.*)\) ([A-Za-z]) (.*)$" statContent;
          in if statMatch == null then null else
            let
              statusContent = readFileSafe "/proc/${pid}/status";
              cmdlineContent = readFileSafe "/proc/${pid}/cmdline";
              name = builtins.elemAt statMatch 0;
              state = builtins.elemAt statMatch 1;
              rest = builtins.elemAt statMatch 2;
              restParts = builtins.filter (p: p != "") (utils.split " " rest);

              # utime and stime are fields 14 and 15 overall, index 10/11 in the rest section
              utime = if builtins.length restParts > 10 then utils.parseInt (builtins.elemAt restParts 10) else 0;
              stime = if builtins.length restParts > 11 then utils.parseInt (builtins.elemAt restParts 11) else 0;

              # Parse status file for memory and user info
              statusLines = if statusContent == "" then [] else utils.split "\n" statusContent;

              findValue = prefix:
                let
                  matching = utils.find (l: utils.contains prefix l) statusLines;
                in if matching == null then "0"
                   else let parts = utils.split ":" matching;
                        in if builtins.length parts >= 2 
                           then utils.trim (builtins.elemAt parts 1)
                           else "0";

              uidLine = findValue "Uid:";
              vmRssLine = findValue "VmRSS:";

              uid = if uidLine == "0" then 0
                    else utils.parseInt (builtins.head (utils.split "\t" uidLine));
              vmRss = if vmRssLine == "0" then 0
                      else utils.parseInt (builtins.head (utils.split " " vmRssLine));

              # Clean up cmdline
              cmdline = builtins.replaceStrings ["\x00"] [" "] cmdlineContent;

            in {
              pid = utils.parseInt pid;
              inherit name state uid;
              cpuTime = utime + stime;
              memoryKb = vmRss;
              command = if cmdline == "" then name else utils.trim cmdline;
            };
      
      # Read all processes (limit to avoid performance issues)
      processes = map readProcess (utils.take 200 pidDirs);
      
    in builtins.filter (p: p != null) processes;

  # ============================================================================
  # Temperature
  # ============================================================================
  
  # Read from /sys/class/thermal
  getTemperature = 
    let
      thermalDir = builtins.tryEval (builtins.readDir "/sys/class/thermal");
      entries = if thermalDir.success then thermalDir.value else {};
      
      # Find thermal zones
      thermalZones = builtins.filter (n: utils.contains "thermal_zone" n) (builtins.attrNames entries);
      
      # Read temperature from a thermal zone
      readTemp = zone:
        let
          typePath = "/sys/class/thermal/${zone}/type";
          tempPath = "/sys/class/thermal/${zone}/temp";
          
          type = utils.trim (readFileSafe typePath);
          tempRaw = readFileSafe tempPath;
          # Temperature is in millidegrees Celsius
          temp = if tempRaw == "" then 0 else (utils.parseInt (utils.trim tempRaw)) / 1000.0;
        in {
          name = zone;
          inherit type temp;
        };
      
      temps = map readTemp thermalZones;
      
      # Also try hwmon sensors
      hwmonDir = builtins.tryEval (builtins.readDir "/sys/class/hwmon");
      hwmonEntries = if hwmonDir.success then hwmonDir.value else {};
      hwmons = builtins.attrNames hwmonEntries;
      
    in {
      thermal = temps;
      # Return the first non-zero CPU temperature
      cpuTemp = let matching = utils.find (t: t.temp > 0 && (utils.contains "cpu" t.type || utils.contains "x86" t.type || utils.contains "core" t.type)) temps;
                in if matching != null then matching.temp else 0;
    };

  # ============================================================================
  # Battery
  # ============================================================================
  
  # Read from /sys/class/power_supply
  getBatteryInfo = 
    let
      psDir = builtins.tryEval (builtins.readDir "/sys/class/power_supply");
      entries = if psDir.success then psDir.value else {};
      
      # Find battery (usually BAT0 or BAT1)
      batteries = builtins.filter (n: utils.contains "BAT" n) (builtins.attrNames entries);
      
      # Read battery info
      readBattery = bat:
        let
          basePath = "/sys/class/power_supply/${bat}";
          
          status = utils.trim (readFileSafe "${basePath}/status");
          capacityRaw = readFileSafe "${basePath}/capacity";
          capacity = if capacityRaw == "" then 0 else utils.parseInt (utils.trim capacityRaw);
          
          # Energy or charge based reporting
          energyNow = utils.parseInt (utils.trim (readFileSafe "${basePath}/energy_now"));
          energyFull = utils.parseInt (utils.trim (readFileSafe "${basePath}/energy_full"));
          chargeNow = utils.parseInt (utils.trim (readFileSafe "${basePath}/charge_now"));
          chargeFull = utils.parseInt (utils.trim (readFileSafe "${basePath}/charge_full"));
          
          # Power draw
          powerNow = utils.parseInt (utils.trim (readFileSafe "${basePath}/power_now"));
          currentNow = utils.parseInt (utils.trim (readFileSafe "${basePath}/current_now"));
          
        in {
          name = bat;
          inherit status capacity;
          charging = status == "Charging";
          discharging = status == "Discharging";
          full = status == "Full";
        };
      
      batInfo = if batteries == [] then null
                else readBattery (builtins.head batteries);
      
    in {
      present = batteries != [];
      battery = batInfo;
    };

  # ============================================================================
  # System Info
  # ============================================================================
  
  # Get load average from /proc/loadavg
  getLoadAverage = 
    let
      content = readFileSafe "/proc/loadavg";
      parts = utils.split " " content;
    in {
      load1 = if builtins.length parts > 0 then utils.parseFloat (builtins.elemAt parts 0) else 0;
      load5 = if builtins.length parts > 1 then utils.parseFloat (builtins.elemAt parts 1) else 0;
      load15 = if builtins.length parts > 2 then utils.parseFloat (builtins.elemAt parts 2) else 0;
    };

  # Get uptime from /proc/uptime
  getUptime = 
    let
      content = readFileSafe "/proc/uptime";
      parts = utils.split " " content;
      seconds = if builtins.length parts > 0 then utils.parseFloat (builtins.elemAt parts 0) else 0;
      
      # Convert to human readable
      days = builtins.floor (seconds / 86400);
      hours = builtins.floor ((seconds - days * 86400) / 3600);
      minutes = builtins.floor ((seconds - days * 86400 - hours * 3600) / 60);
      
    in {
      inherit seconds days hours minutes;
      formatted = "${toString days}d ${toString hours}h ${toString minutes}m";
    };
}

