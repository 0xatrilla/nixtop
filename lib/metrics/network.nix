# Network metrics processing
{ pkgs, utils, platform }:

rec {
  # ============================================================================
  # Network Speed Calculation
  # ============================================================================
  
  # Calculate network speeds from byte counters
  # interval: seconds between measurements
  calculateSpeeds = { currentData, prevData ? [], interval ? 2 }:
    let
      currentInterfaces = currentData.interfaces or [];
      prevInterfaces = prevData.interfaces or [];
      
      # Create lookup map
      prevMap = builtins.listToAttrs (map (i: { name = i.name; value = i; }) prevInterfaces);
      
      calcInterface = current:
        let
          prev = prevMap.${current.name} or null;
          
          # Calculate byte deltas
          rxDelta = if prev != null then current.rxBytes - prev.rxBytes else 0;
          txDelta = if prev != null then current.txBytes - prev.txBytes else 0;
          
          # Handle counter wraparound (rare but possible)
          safeRxDelta = if rxDelta < 0 then 0 else rxDelta;
          safeTxDelta = if txDelta < 0 then 0 else txDelta;
          
          # Calculate per-second rates
          rxRate = if interval > 0 then safeRxDelta / interval else 0;
          txRate = if interval > 0 then safeTxDelta / interval else 0;
          
        in {
          name = current.name;
          
          # Total bytes
          rxBytes = current.rxBytes;
          txBytes = current.txBytes;
          rxPackets = current.rxPackets;
          txPackets = current.txPackets;
          
          # Rates (bytes per second)
          rxRate = rxRate;
          txRate = txRate;
          
          # Formatted rates
          rxRateStr = utils.formatBytesPerSec rxRate;
          txRateStr = utils.formatBytesPerSec txRate;
          
          # Total traffic formatted
          rxTotalStr = utils.formatBytes current.rxBytes;
          txTotalStr = utils.formatBytes current.txBytes;
        };
      
    in map calcInterface currentInterfaces;

  # ============================================================================
  # Network History
  # ============================================================================
  
  updateHistory = { history, rxRate, txRate, maxLen ? 60 }:
    let
      newRxHistory = (history.rx or []) ++ [rxRate];
      newTxHistory = (history.tx or []) ++ [txRate];
      
      trimHistory = h:
        let len = builtins.length h;
        in if len > maxLen then utils.drop (len - maxLen) h else h;
      
    in {
      rx = trimHistory newRxHistory;
      tx = trimHistory newTxHistory;
    };

  # ============================================================================
  # Main Network Metrics Function
  # ============================================================================
  
  getMetrics = { prevState ? {}, interval ? 2, preferredInterface ? "auto" }:
    let
      # Get raw data from platform
      netInfo = platform.getNetworkInfo;
      
      # Get previous network data
      prevNetData = prevState.netData or { interfaces = []; };
      prevHistory = prevState.netHistory or { rx = []; tx = []; };
      
      # Calculate speeds
      interfacesRaw = calculateSpeeds {
        currentData = netInfo;
        prevData = prevNetData;
        inherit interval;
      };

      dedupeInterfaces = list:
        builtins.foldl' (acc: iface:
          if builtins.any (existing: existing.name == iface.name) acc
          then acc
          else acc ++ [iface]
        ) [] list;

      interfaces = dedupeInterfaces interfacesRaw;
      
      # Find preferred interface (by name) or fall back to first active
      preferred = if preferredInterface != "auto"
                  then getInterface preferredInterface interfaces
                  else null;
      primary = if preferred != null
                then preferred
                else utils.find (i: i.rxBytes > 0 || i.txBytes > 0) interfaces;
      primaryInterface = if primary != null then primary
                        else if interfaces != [] then builtins.head interfaces
                        else {
                          name = "none";
                          rxRate = 0; txRate = 0;
                          rxRateStr = "0 B/s"; txRateStr = "0 B/s";
                          rxBytes = 0; txBytes = 0;
                          rxTotalStr = "0 B"; txTotalStr = "0 B";
                        };
      
      # Update history with primary interface rates
      history = updateHistory {
        history = prevHistory;
        rxRate = primaryInterface.rxRate;
        txRate = primaryInterface.txRate;
        maxLen = 60;
      };
      
      # Calculate totals across all interfaces
      totalRxRate = utils.sum (map (i: i.rxRate) interfaces);
      totalTxRate = utils.sum (map (i: i.txRate) interfaces);
      
    in {
      inherit interfaces history;
      
      # Primary interface for display
      primary = primaryInterface;
      
      # Totals
      total = {
        rxRate = totalRxRate;
        txRate = totalTxRate;
        rxRateStr = utils.formatBytesPerSec totalRxRate;
        txRateStr = utils.formatBytesPerSec totalTxRate;
      };
      
      # State data to persist
      stateData = {
        netData = netInfo;
        netHistory = history;
      };
    };

  # ============================================================================
  # Interface Filtering
  # ============================================================================
  
  # Filter to only active interfaces
  getActiveInterfaces = interfaces:
    builtins.filter (i: i.rxBytes > 0 || i.txBytes > 0) interfaces;

  # Get interface by name
  getInterface = name: interfaces:
    utils.find (i: i.name == name) interfaces;

  # ============================================================================
  # Network Summary
  # ============================================================================
  
  getSummary = interfaces:
    let
      active = getActiveInterfaces interfaces;
      
    in {
      interfaceCount = builtins.length interfaces;
      activeCount = builtins.length active;
      
      # List of active interface names
      activeNames = map (i: i.name) active;
    };
}



