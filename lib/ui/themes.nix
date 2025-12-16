# Theme definitions for nixmon
{ pkgs, utils }:

rec {
  # ============================================================================
  # Theme structure
  # ============================================================================
  
  # Each theme defines colors for different UI elements
  # Structure:
  # {
  #   name = "Theme Name";
  #   colors = {
  #     background = "#hex";
  #     foreground = "#hex";
  #     border = "#hex";
  #     title = "#hex";
  #     highlight = "#hex";
  #     cpu = "#hex";
  #     memory = "#hex";
  #     network = "#hex";
  #     disk = "#hex";
  #     process = "#hex";
  #     temp = "#hex";
  #     battery = "#hex";
  #     graph = "#hex";
  #     graphFill = "#hex";
  #     low = "#hex";
  #     medium = "#hex";
  #     high = "#hex";
  #     critical = "#hex";
  #   };
  # }

  # ============================================================================
  # Built-in themes
  # ============================================================================
  
  themes = {
    # Default theme - Dracula inspired
    default = {
      name = "Default";
      colors = {
        background = "#282a36";
        foreground = "#f8f8f2";
        border = "#6272a4";
        title = "#bd93f9";
        highlight = "#50fa7b";
        
        cpu = "#ff79c6";
        memory = "#8be9fd";
        network = "#50fa7b";
        disk = "#ffb86c";
        process = "#f8f8f2";
        temp = "#ff5555";
        battery = "#50fa7b";
        
        graph = "#bd93f9";
        graphFill = "#44475a";
        
        low = "#50fa7b";
        medium = "#f1fa8c";
        high = "#ffb86c";
        critical = "#ff5555";
        
        headerBg = "#44475a";
        headerFg = "#f8f8f2";
        selected = "#44475a";
      };
    };
    
    # Nord theme
    nord = {
      name = "Nord";
      colors = {
        background = "#2e3440";
        foreground = "#eceff4";
        border = "#4c566a";
        title = "#88c0d0";
        highlight = "#a3be8c";
        
        cpu = "#bf616a";
        memory = "#5e81ac";
        network = "#a3be8c";
        disk = "#ebcb8b";
        process = "#eceff4";
        temp = "#bf616a";
        battery = "#a3be8c";
        
        graph = "#81a1c1";
        graphFill = "#3b4252";
        
        low = "#a3be8c";
        medium = "#ebcb8b";
        high = "#d08770";
        critical = "#bf616a";
        
        headerBg = "#3b4252";
        headerFg = "#eceff4";
        selected = "#4c566a";
      };
    };
    
    # Monokai theme
    monokai = {
      name = "Monokai";
      colors = {
        background = "#272822";
        foreground = "#f8f8f2";
        border = "#75715e";
        title = "#ae81ff";
        highlight = "#a6e22e";
        
        cpu = "#f92672";
        memory = "#66d9ef";
        network = "#a6e22e";
        disk = "#fd971f";
        process = "#f8f8f2";
        temp = "#f92672";
        battery = "#a6e22e";
        
        graph = "#ae81ff";
        graphFill = "#3e3d32";
        
        low = "#a6e22e";
        medium = "#e6db74";
        high = "#fd971f";
        critical = "#f92672";
        
        headerBg = "#3e3d32";
        headerFg = "#f8f8f2";
        selected = "#49483e";
      };
    };
    
    # Gruvbox Dark theme
    gruvbox = {
      name = "Gruvbox";
      colors = {
        background = "#282828";
        foreground = "#ebdbb2";
        border = "#665c54";
        title = "#d3869b";
        highlight = "#b8bb26";
        
        cpu = "#fb4934";
        memory = "#83a598";
        network = "#b8bb26";
        disk = "#fe8019";
        process = "#ebdbb2";
        temp = "#fb4934";
        battery = "#b8bb26";
        
        graph = "#d3869b";
        graphFill = "#3c3836";
        
        low = "#b8bb26";
        medium = "#fabd2f";
        high = "#fe8019";
        critical = "#fb4934";
        
        headerBg = "#3c3836";
        headerFg = "#ebdbb2";
        selected = "#504945";
      };
    };
    
    # Solarized Dark theme
    solarized = {
      name = "Solarized";
      colors = {
        background = "#002b36";
        foreground = "#839496";
        border = "#586e75";
        title = "#268bd2";
        highlight = "#859900";
        
        cpu = "#dc322f";
        memory = "#268bd2";
        network = "#859900";
        disk = "#cb4b16";
        process = "#839496";
        temp = "#dc322f";
        battery = "#859900";
        
        graph = "#6c71c4";
        graphFill = "#073642";
        
        low = "#859900";
        medium = "#b58900";
        high = "#cb4b16";
        critical = "#dc322f";
        
        headerBg = "#073642";
        headerFg = "#93a1a1";
        selected = "#073642";
      };
    };
    
    # One Dark theme
    onedark = {
      name = "One Dark";
      colors = {
        background = "#282c34";
        foreground = "#abb2bf";
        border = "#4b5263";
        title = "#c678dd";
        highlight = "#98c379";
        
        cpu = "#e06c75";
        memory = "#61afef";
        network = "#98c379";
        disk = "#d19a66";
        process = "#abb2bf";
        temp = "#e06c75";
        battery = "#98c379";
        
        graph = "#c678dd";
        graphFill = "#3e4451";
        
        low = "#98c379";
        medium = "#e5c07b";
        high = "#d19a66";
        critical = "#e06c75";
        
        headerBg = "#3e4451";
        headerFg = "#abb2bf";
        selected = "#3e4451";
      };
    };
    
    # Tokyo Night theme
    tokyonight = {
      name = "Tokyo Night";
      colors = {
        background = "#1a1b26";
        foreground = "#c0caf5";
        border = "#414868";
        title = "#bb9af7";
        highlight = "#9ece6a";
        
        cpu = "#f7768e";
        memory = "#7aa2f7";
        network = "#9ece6a";
        disk = "#ff9e64";
        process = "#c0caf5";
        temp = "#f7768e";
        battery = "#9ece6a";
        
        graph = "#bb9af7";
        graphFill = "#24283b";
        
        low = "#9ece6a";
        medium = "#e0af68";
        high = "#ff9e64";
        critical = "#f7768e";
        
        headerBg = "#24283b";
        headerFg = "#c0caf5";
        selected = "#33467c";
      };
    };
    
    # Catppuccin Mocha theme
    catppuccin = {
      name = "Catppuccin";
      colors = {
        background = "#1e1e2e";
        foreground = "#cdd6f4";
        border = "#585b70";
        title = "#cba6f7";
        highlight = "#a6e3a1";
        
        cpu = "#f38ba8";
        memory = "#89b4fa";
        network = "#a6e3a1";
        disk = "#fab387";
        process = "#cdd6f4";
        temp = "#f38ba8";
        battery = "#a6e3a1";
        
        graph = "#cba6f7";
        graphFill = "#313244";
        
        low = "#a6e3a1";
        medium = "#f9e2af";
        high = "#fab387";
        critical = "#f38ba8";
        
        headerBg = "#313244";
        headerFg = "#cdd6f4";
        selected = "#45475a";
      };
    };

    # Matrix theme (green on black)
    matrix = {
      name = "Matrix";
      colors = {
        background = "#000000";
        foreground = "#00ff00";
        border = "#003300";
        title = "#00ff00";
        highlight = "#00ff00";
        
        cpu = "#00ff00";
        memory = "#00dd00";
        network = "#00ff00";
        disk = "#00bb00";
        process = "#00ff00";
        temp = "#00ff00";
        battery = "#00ff00";
        
        graph = "#00ff00";
        graphFill = "#001100";
        
        low = "#00ff00";
        medium = "#00dd00";
        high = "#00bb00";
        critical = "#ff0000";
        
        headerBg = "#001100";
        headerFg = "#00ff00";
        selected = "#003300";
      };
    };
  };

  # ============================================================================
  # Theme functions
  # ============================================================================
  
  # Get theme by name (defaults to "default")
  getTheme = name:
    themes.${name} or themes.default;

  # List available theme names
  themeNames = builtins.attrNames themes;

  # Get color from theme
  getColor = theme: colorName:
    let t = if builtins.isString theme then getTheme theme else theme;
    in t.colors.${colorName} or "#ffffff";
}

