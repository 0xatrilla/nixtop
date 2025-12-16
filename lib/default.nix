# nixmon library - Main entry point
{ pkgs }:

let
  # Utility functions
  utils = import ./utils.nix { inherit pkgs; };
  
  # UI components
  ui = {
    ansi = import ./ui/ansi.nix { inherit pkgs utils; };
    colors = import ./ui/colors.nix { inherit pkgs utils; };
    themes = import ./ui/themes.nix { inherit pkgs utils; };
    graphs = import ./ui/graphs.nix { inherit pkgs utils; };
    boxes = import ./ui/boxes.nix { inherit pkgs utils; };
  };
  
  # Add render after ui is defined (it depends on other ui components)
  uiWithRender = ui // {
    render = import ./ui/render.nix { inherit pkgs utils; ui = ui; };
  };
  
  # Platform-specific data collection
  platform = import ./platform { inherit pkgs utils; };
  
  # Metrics processing
  metrics = {
    cpu = import ./metrics/cpu.nix { inherit pkgs utils platform; };
    memory = import ./metrics/memory.nix { inherit pkgs utils platform; };
    disk = import ./metrics/disk.nix { inherit pkgs utils platform; };
    network = import ./metrics/network.nix { inherit pkgs utils platform; };
    processes = import ./metrics/processes.nix { inherit pkgs utils platform; };
    temperature = import ./metrics/temperature.nix { inherit pkgs utils platform; };
    battery = import ./metrics/battery.nix { inherit pkgs utils platform; };
  };

in {
  inherit utils platform metrics;
  ui = uiWithRender;
}
