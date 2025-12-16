# Disk metrics processing
{ pkgs, utils, platform }:

rec {
  # ============================================================================
  # Disk Space Formatting
  # ============================================================================
  
  # Format a single mount point
  formatMount = mount:
    let
      total = mount.total or 0;
      used = mount.used or 0;
      available = mount.available or 0;
      usedPct = mount.usedPercent or (if total > 0 then utils.percentage used total else 0);
      
    in {
      device = mount.device or "unknown";
      mountPoint = mount.mountPoint or "/";
      fsType = mount.fsType or "unknown";
      
      total = total;
      used = used;
      available = available;
      usedPercent = usedPct;
      
      # Formatted strings
      totalStr = utils.formatBytes total;
      usedStr = utils.formatBytes used;
      availableStr = utils.formatBytes available;
      
      # Summary
      summary = "${utils.formatBytes used} / ${utils.formatBytes total}";
    };

  # Format all mount points
  formatMounts = mounts:
    map formatMount mounts;

  # ============================================================================
  # Disk I/O Calculation
  # ============================================================================
  
  # Calculate I/O rates from current and previous stats
  # sectorSize is typically 512 bytes
  calculateIO = { currentStats, prevStats ? [], interval ? 2, sectorSize ? 512 }:
    let
      prevMap = builtins.listToAttrs (map (s: { name = s.name; value = s; }) prevStats);
      
      calcDisk = current:
        let
          prev = prevMap.${current.name} or null;
          
          readDelta = if prev != null then current.sectorsRead - prev.sectorsRead else 0;
          writeDelta = if prev != null then current.sectorsWritten - prev.sectorsWritten else 0;
          
          # Convert sectors to bytes and divide by interval for per-second rate
          readBytesPerSec = if interval > 0 then (readDelta * sectorSize) / interval else 0;
          writeBytesPerSec = if interval > 0 then (writeDelta * sectorSize) / interval else 0;
          
        in {
          name = current.name;
          readRate = utils.clamp 0 1000000000 readBytesPerSec;  # Cap at 1GB/s
          writeRate = utils.clamp 0 1000000000 writeBytesPerSec;
          
          readRateStr = utils.formatBytesPerSec readBytesPerSec;
          writeRateStr = utils.formatBytesPerSec writeBytesPerSec;
          
          raw = current;
        };
      
    in map calcDisk currentStats;

  # ============================================================================
  # Disk Health Indicators
  # ============================================================================
  
  # Get status based on usage percentage
  getUsageLevel = usedPct:
    if usedPct >= 95 then "critical"
    else if usedPct >= 90 then "warning"
    else if usedPct >= 75 then "high"
    else "normal";

  # ============================================================================
  # Main Disk Metrics Function
  # ============================================================================
  
  getMetrics = { prevState ? {}, interval ? 2 }:
    let
      # Get raw data from platform
      diskInfo = platform.getDiskInfo;
      
      mounts = diskInfo.mounts or [];
      stats = diskInfo.stats or [];
      
      # Format mount points
      formattedMounts = formatMounts mounts;
      
      # Calculate I/O rates if we have previous stats
      prevDiskStats = prevState.diskStats or [];
      ioRates = calculateIO { 
        currentStats = stats; 
        prevStats = prevDiskStats; 
        inherit interval; 
      };
      
      # Find main disk (usually / mount)
      mainDisk = utils.find (m: m.mountPoint == "/") formattedMounts;
      
      # Sum total I/O
      totalReadRate = utils.sum (map (d: d.readRate) ioRates);
      totalWriteRate = utils.sum (map (d: d.writeRate) ioRates);
      
    in {
      mounts = formattedMounts;
      io = ioRates;
      
      # Quick access to main disk
      main = mainDisk;
      
      # Total I/O
      totalIO = {
        readRate = totalReadRate;
        writeRate = totalWriteRate;
        readRateStr = utils.formatBytesPerSec totalReadRate;
        writeRateStr = utils.formatBytesPerSec totalWriteRate;
      };
      
      # State data to persist
      stateData = {
        diskStats = stats;
      };
    };

  # ============================================================================
  # Disk Summary
  # ============================================================================
  
  # Get summary of all disks for compact display
  getSummary = mounts:
    let
      totalSpace = utils.sum (map (m: m.total) mounts);
      usedSpace = utils.sum (map (m: m.used) mounts);
      overallPct = if totalSpace > 0 then utils.percentage usedSpace totalSpace else 0;
      
    in {
      count = builtins.length mounts;
      totalSpace = totalSpace;
      usedSpace = usedSpace;
      overallPercent = overallPct;
      
      totalStr = utils.formatBytes totalSpace;
      usedStr = utils.formatBytes usedSpace;
    };
}



