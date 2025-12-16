# Battery metrics processing
{ pkgs, utils, platform }:

rec {
  # ============================================================================
  # Battery Status Formatting
  # ============================================================================
  
  # Format battery percentage
  formatPercent = pct:
    "${toString (builtins.floor pct)}%";

  # Get battery status icon
  getStatusIcon = { charging, discharging, full, pct }:
    if full then "🔋"
    else if charging then "⚡"
    else if pct <= 10 then "🪫"
    else "🔋";

  # Get status text
  getStatusText = { charging, discharging, full, status }:
    if full then "Full"
    else if charging then "Charging"
    else if discharging then "Discharging"
    else status;

  # ============================================================================
  # Battery Level Classification
  # ============================================================================
  
  # Get battery level status
  getBatteryLevel = pct:
    if pct >= 90 then "full"
    else if pct >= 50 then "good"
    else if pct >= 25 then "low"
    else if pct >= 10 then "critical"
    else "empty";

  # Get battery color
  getBatteryColor = pct:
    let
      colors = import ../ui/colors.nix { inherit pkgs utils; };
    in colors.getBatteryColor pct;

  # ============================================================================
  # Time Estimation
  # ============================================================================
  
  # Estimate remaining time based on discharge rate
  # This is a rough estimate - actual time depends on usage patterns
  estimateTimeRemaining = { capacity, dischargeRate }:
    if dischargeRate <= 0 then null
    else let
      hours = capacity / dischargeRate;
      wholeHours = builtins.floor hours;
      minutes = builtins.floor ((hours - wholeHours) * 60);
    in {
      hours = wholeHours;
      minutes = minutes;
      formatted = "${toString wholeHours}h ${toString minutes}m";
    };

  # Estimate time to full charge
  estimateTimeToFull = { currentCapacity, maxCapacity, chargeRate }:
    if chargeRate <= 0 then null
    else let
      remaining = maxCapacity - currentCapacity;
      hours = remaining / chargeRate;
      wholeHours = builtins.floor hours;
      minutes = builtins.floor ((hours - wholeHours) * 60);
    in {
      hours = wholeHours;
      minutes = minutes;
      formatted = "${toString wholeHours}h ${toString minutes}m";
    };

  # ============================================================================
  # Main Battery Metrics Function
  # ============================================================================
  
  getMetrics = { prevState ? {} }:
    let
      # Get raw battery data from platform
      batteryInfo = platform.getBatteryInfo;
      
      present = batteryInfo.present or false;
      battery = batteryInfo.battery;
      
      # If no battery, return minimal info
      noBattery = {
        present = false;
        battery = null;
        summary = "No battery";
        stateData = {};
      };
      
      # Process battery info
      processBattery = bat:
        let
          capacity = bat.capacity or 100;
          charging = bat.charging or false;
          discharging = bat.discharging or false;
          full = bat.full or false;
          status = bat.status or "Unknown";
          
          level = getBatteryLevel capacity;
          icon = getStatusIcon { inherit charging discharging full; pct = capacity; };
          statusText = getStatusText { inherit charging discharging full status; };
          
          # Get history for tracking
          prevHistory = prevState.batteryHistory or [];
          newHistory = prevHistory ++ [capacity];
          history = let len = builtins.length newHistory;
                    in if len > 60 then utils.drop (len - 60) newHistory else newHistory;
          
        in {
          present = true;
          
          battery = {
            name = bat.name or "Battery";
            capacity = capacity;
            capacityStr = formatPercent capacity;
            
            inherit charging discharging full;
            status = statusText;
            
            inherit level icon;
            
            # Power info if available
            power = bat.power or null;
          };
          
          # Quick access values
          percent = capacity;
          isCharging = charging;
          isLow = capacity <= 25;
          isCritical = capacity <= 10;
          
          # Summary for display
          summary = "${icon} ${formatPercent capacity} (${statusText})";
          
          # History for tracking
          inherit history;
          
          # State data to persist
          stateData = {
            batteryHistory = history;
          };
        };
      
    in if !present || battery == null 
       then noBattery 
       else processBattery battery;

  # ============================================================================
  # Battery Health
  # ============================================================================
  
  # Calculate battery health percentage
  # Based on design capacity vs current max capacity
  calculateHealth = { designCapacity, currentMaxCapacity }:
    if designCapacity <= 0 then 100
    else utils.clamp 0 100 ((currentMaxCapacity * 100) / designCapacity);

  # Get health status
  getHealthStatus = healthPct:
    if healthPct >= 80 then "good"
    else if healthPct >= 50 then "fair"
    else "poor";
}



