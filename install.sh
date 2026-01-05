#!/usr/bin/env bash
# Install nixmon globally so it can be run from anywhere

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_PATH="${1:-$SCRIPT_DIR}"

echo "Installing nixmon from: $FLAKE_PATH"
echo ""

# Check if nix profile is available
if ! command -v nix &> /dev/null; then
  echo "Error: nix is not installed or not in PATH"
  exit 1
fi

# Check if flakes are enabled
if ! nix flake --version &>/dev/null; then
  echo "Error: Nix flakes are not enabled."
  echo "Enable them by adding to ~/.config/nix/nix.conf:"
  echo "  experimental-features = nix-command flakes"
  exit 1
fi

# Install using nix profile
echo "Installing nixmon packages to user profile..."
if [ -f "$FLAKE_PATH/flake.nix" ]; then
  # Try to remove existing installations first (ignore errors)
  nix profile remove nixmon 2>/dev/null || true
  nix profile remove nixmon-themes 2>/dev/null || true
  nix profile remove nixmon-export-json 2>/dev/null || true
  nix profile remove nixmon-export-csv 2>/dev/null || true
  
  # Install main nixmon package
  echo "  Installing nixmon..."
  # Quote the flake path to handle spaces
  FLAKE_REF="$(cd "$FLAKE_PATH" && pwd)"
  if nix profile add "$FLAKE_REF#nixmon" 2>&1; then
    echo "    ✓ nixmon installed"
  elif nix profile install "$FLAKE_REF#nixmon" 2>&1; then
    echo "    ✓ nixmon installed (using deprecated command)"
  else
    # Try default package
    if nix profile add "$FLAKE_REF#default" 2>&1; then
      echo "    ✓ nixmon installed (as default)"
    elif nix profile install "$FLAKE_REF#default" 2>&1; then
      echo "    ✓ nixmon installed (as default, using deprecated command)"
    else
      echo ""
      echo "Error: Failed to install nixmon."
      echo "Tried: $FLAKE_REF#nixmon and $FLAKE_REF#default"
      exit 1
    fi
  fi
  
  # Install additional packages
  echo "  Installing nixmon-themes..."
  if nix profile add "$FLAKE_REF#themes" 2>&1; then
    echo "    ✓ nixmon-themes installed"
  elif nix profile install "$FLAKE_REF#themes" 2>&1; then
    echo "    ✓ nixmon-themes installed (using deprecated command)"
  else
    echo "    ⚠ nixmon-themes installation failed (optional)"
  fi
  
  echo "  Installing nixmon-export-json..."
  if nix profile add "$FLAKE_REF#export-json" 2>&1; then
    echo "    ✓ nixmon-export-json installed"
  elif nix profile install "$FLAKE_REF#export-json" 2>&1; then
    echo "    ✓ nixmon-export-json installed (using deprecated command)"
  else
    echo "    ⚠ nixmon-export-json installation failed (optional)"
  fi
  
  echo "  Installing nixmon-export-csv..."
  if nix profile add "$FLAKE_REF#export-csv" 2>&1; then
    echo "    ✓ nixmon-export-csv installed"
  elif nix profile install "$FLAKE_REF#export-csv" 2>&1; then
    echo "    ✓ nixmon-export-csv installed (using deprecated command)"
  else
    echo "    ⚠ nixmon-export-csv installation failed (optional)"
  fi
else
  echo "Error: flake.nix not found at $FLAKE_PATH"
  exit 1
fi

echo ""
echo "✓ All nixmon packages installed successfully!"
echo ""
echo "You can now run 'nixmon' from anywhere."
echo ""
echo "Commands:"
echo "  nixmon              - Run the monitor"
echo "  nixmon-themes       - Preview themes"
echo "  nixmon-export-json  - Export metrics to JSON"
echo "  nixmon-export-csv   - Export metrics to CSV"
echo ""
echo "To update all packages:"
echo "  nix profile upgrade nixmon"
echo "  nix profile upgrade nixmon-themes"
echo "  nix profile upgrade nixmon-export-json"
echo "  nix profile upgrade nixmon-export-csv"
echo ""
echo "To uninstall:"
echo "  nix profile remove nixmon"
echo "  nix profile remove nixmon-themes"
echo "  nix profile remove nixmon-export-json"
echo "  nix profile remove nixmon-export-csv"
