# Temperature metrics processing
{ pkgs, utils, platform }:

rec {
  # ============================================================================
  # Temperature Formatting
  # ============================================================================
  
  # Format temperature value
  formatTemp = celsius:
    "${toString (utils.round 1 celsius)}°C";

  # Format temperature with color indication
  formatTempWithStatus = celsius:
    let
      status = getTempStatus celsius;
    in {
      value = celsius;
      formatted = formatTemp celsius;
      inherit status;
    };

  # ============================================================================
  # Temperature Status
  # ============================================================================
  
  # Get temperature status based on value
  # Thresholds are rough estimates - actual values vary by hardware
  getTempStatus = celsius:
    if celsius >= 95 then "critical"
    else if celsius >= 85 then "hot"
    else if celsius >= 70 then "warm"
    else if celsius >= 50 then "normal"
    else "cool";

  # Get color for temperature
  getTempColor = celsius:
    let
      colors = import ../ui/colors.nix { inherit pkgs utils; };
    in colors.getTempColor celsius;

  # ============================================================================
  # Sensor Aggregation
  # ============================================================================
  
  # Find the maximum temperature across all sensors
  getMaxTemp = sensors:
    let temps = map (s: s.temp or 0) sensors;
    in utils.max temps;

  # Find the average temperature
  getAvgTemp = sensors:
    let temps = map (s: s.temp or 0) sensors;
    in utils.avg temps;

  # Get CPU-specific temperature
  getCpuTemp = sensors:
    let
      cpuSensor = utils.find (s: 
        utils.contains "cpu" (s.type or "") ||
        utils.contains "CPU" (s.type or "") ||
        utils.contains "x86" (s.type or "") ||
        utils.contains "Core" (s.type or "")
      ) sensors;
    in if cpuSensor != null then cpuSensor.temp else getMaxTemp sensors;

  # ============================================================================
  # Main Temperature Metrics Function
  # ============================================================================
  
  getMetrics = { prevState ? {} }:
    let
      # Get raw temperature data from platform
      tempInfo = platform.getTemperature;
      
      sensors = tempInfo.thermal or [];
      cpuTemp = tempInfo.cpuTemp or 0;
      
      # Get previous history
      prevHistory = prevState.tempHistory or [];
      
      # Use platform-provided CPU temp or calculate from sensors
      actualCpuTemp = if cpuTemp > 0 then cpuTemp else getCpuTemp sensors;
      
      # Format temperatures
      formattedSensors = map (s: {
        name = s.name;
        type = s.type or "unknown";
        temp = s.temp;
        formatted = formatTemp s.temp;
        status = getTempStatus s.temp;
      }) sensors;
      
      # Update history
      newHistory = (prevHistory ++ [actualCpuTemp]);
      history = let len = builtins.length newHistory;
                in if len > 60 then utils.drop (len - 60) newHistory else newHistory;
      
      # Summary stats
      maxTemp = getMaxTemp sensors;
      avgTemp = getAvgTemp sensors;
      
    in {
      sensors = formattedSensors;
      
      # CPU temperature (main display value)
      cpu = {
        temp = actualCpuTemp;
        formatted = formatTemp actualCpuTemp;
        status = getTempStatus actualCpuTemp;
      };
      
      # Summary
      max = {
        temp = maxTemp;
        formatted = formatTemp maxTemp;
        status = getTempStatus maxTemp;
      };
      
      avg = {
        temp = avgTemp;
        formatted = formatTemp avgTemp;
      };
      
      # History for sparkline
      inherit history;
      
      # State data to persist
      stateData = {
        tempHistory = history;
      };
    };

  # ============================================================================
  # Temperature Alerts
  # ============================================================================
  
  # Check if any sensor is above threshold
  hasHighTemp = sensors: threshold:
    builtins.any (s: (s.temp or 0) >= threshold) sensors;

  # Get critical sensors
  getCriticalSensors = sensors: threshold:
    builtins.filter (s: (s.temp or 0) >= threshold) sensors;
}



