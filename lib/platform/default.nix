# Platform detection and abstraction layer
{ pkgs, utils }:

let
  linux = import ./linux.nix { inherit pkgs utils; };
  darwin = import ./darwin.nix { inherit pkgs utils; };
  
  # Select the appropriate platform implementation
  impl = if utils.isDarwin then darwin else linux;

in {
  inherit (impl) 
    getCpuInfo
    getCpuUsage
    getMemoryInfo
    getDiskInfo
    getNetworkInfo
    getProcessList
    getTemperature
    getBatteryInfo
    getLoadAverage
    getUptime;
  
  # Platform name for display
  platformName = utils.platformName;
  
  # Raw platform implementations for direct access
  linux = linux;
  darwin = darwin;
}

