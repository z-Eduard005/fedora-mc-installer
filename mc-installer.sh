#!/bin/bash
INSTALL_DIR="$HOME/Programs/proton-legacylauncher"
LL_URL="https://dl.llaun.ch/legacy/installer"
LL_FILENAME="LegacyLauncher.exe"
STEAM_PATH="$HOME/.steam/steam"
STEAM_COMPDATA_DIR="$STEAM_PATH/steamapps/compatdata"
FIRST_LOCAL_STEAM_APP_ID=2147483647
MC_REL_PATH="pfx/drive_c/users/steamuser/AppData/Roaming/.tlauncher/legacy/Minecraft"
PFX_FILE_FLAG="$INSTALL_DIR/.pfx-created"
INSTALLER="$INSTALL_DIR/mc-installer.sh"
DESKTOP_ENTRY_PATH="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_ENTRY_PATH/LL.desktop"
LL_ICON="$HOME/.local/share/icons/LL.png"
GITHUB_CONTENT="https://raw.githubusercontent.com/z-Eduard005/fedora-mc-installer/main"
DEFAULT_PROTON="Proton Hotfix"

success() { printf "\033[1;32m%s\033[0m" "$1"; }
err() { printf "\033[1;31m%s\033[0m" "$1"; }
warn() { printf "\033[1;33m%s\033[0m" "$1"; }

ask_confirm() {
  read -rp "$(warn "$1 [y/N]: ")" proceed
  if [[ "$proceed" != "y" && "$proceed" != "Y" ]]; then
    echo "$(err "Aborted.")"; exit 1
  fi
}

pfx_flag_missing=false
[ ! -f "$PFX_FILE_FLAG" ] && pfx_flag_missing=true
$pfx_flag_missing && echo "$(success "Installing tlauncher for steam-proton use :)")"

if [ ! -d "$STEAM_PATH" ]; then
  echo "Steam is not installed. Installing via dnf (RPM version)..."
  if flatpak list | grep -q com.valvesoftware.Steam; then
    echo -e "$(err "Detected Flatpak version of Steam\nPlease uninstall it manually before continuing :(")"
    exit 1
  fi

  sudo dnf install steam || { echo "$(err "Failed to install Steam. Please install it manually.")"; exit 1; }
  if [ ! -d "$STEAM_PATH" ]; then
    echo "$(err "Steam did not install correctly")"; exit 1
  fi
fi

if [ ! -d "$INSTALL_DIR" ]; then
  ask_confirm "Proceed with creating $INSTALL_DIR folder?"
  mkdir -p "$INSTALL_DIR"
fi

echo "sh -c \"\$(curl -fsSL "$GITHUB_CONTENT/mc-installer.sh")\"" > "$INSTALLER" || echo "$(err "Script wasn't installed. Please try again.")"
chmod +x "$INSTALLER"; echo "$(success "File updated - $(basename "$INSTALLER")")"

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "installing inotify-tools..."
  sudo dnf install -y inotify-tools
fi

if [ ! -f "$INSTALL_DIR/$LL_FILENAME" ]; then
  echo "$(success "Please install legacy-launcher first from opening link")"
  for i in 3 2 1; do echo -ne "\r$i"; sleep 1; done; echo -ne "\rWaiting..."
  xdg-open "$LL_URL" >/dev/null 2>&1

  while true; do
    f=$(timeout 60s inotifywait -e close_write --format "%f" "$HOME/Downloads" 2>/dev/null)
    [ $? -eq 124 ] && { echo "$(err "No new files detected in 1 minute. Exiting.")"; exit 1; }
    [[ "$f" =~ \.part$ ]] && continue
    break
  done

  mv -n "$HOME/Downloads/$f" "$INSTALL_DIR/$LL_FILENAME"
  echo "Moved and renamed $f to $INSTALL_DIR/$LL_FILENAME"
fi

if $pfx_flag_missing; then
  steam >/dev/null 2>&1 & cat <<EOF

Launching Steam...

Once Steam has launched, follow these steps:
  1. In Steam, use 'Add a Non-Steam Game' to add: $INSTALL_DIR/$LL_FILENAME
  2. Right-click the game entry in Steam and select 'Manage...'
    2.1. Mark it as Hidden!
  3. Right-click the game entry in Steam and select 'Properties...'
    3.1. Disable steam overlay
    3.2. Compatibility -> force to use specific compatibility tool -> '$DEFAULT_PROTON'
    3.3. Press Play -> install -> close it without downloading any version!

Continue after all done
EOF
  ask_confirm "All done?"

  for dirname in "$STEAM_COMPDATA_DIR"/*; do
  [ -d "$dirname" ] && [ ! -L "$dirname" ] || continue
    base=$(basename "$dirname")
    if [[ "$base" =~ ^[0-9]+$ ]] && [ "$base" -gt "$FIRST_LOCAL_STEAM_APP_ID" ]; then
      path="$STEAM_COMPDATA_DIR/$base/$MC_REL_PATH"
      [ -e "$path" ] && { PFX_PATH="$STEAM_COMPDATA_DIR/$base"; break; }
    fi
  done
  [ -z "$PFX_PATH" ] && { echo "$(err "No Proton folder found! Maybe you forgot to press 'Play' on $LL_FILENAME to initialize proton")"; exit 1; }

  echo "Creating symlink for Proton prefix..."
  mv "$PFX_PATH" "$INSTALL_DIR/$(basename "$PFX_PATH")"
  ln -s "$INSTALL_DIR/$(basename "$PFX_PATH")" "$STEAM_COMPDATA_DIR"
  echo "$(basename "$PFX_PATH")" > "$PFX_FILE_FLAG"
fi
[ -z "$PFX_PATH" ] && PFX_PATH="$INSTALL_DIR/$(cat "$PFX_FILE_FLAG")"

protons=()
while IFS= read -r dir; do
  if [[ "$dir" == "$DEFAULT_PROTON" ]]; then
    protons=("$dir" "${protons[@]}")
  else
    protons+=("$dir")
  fi
done < <(ls -1 "$STEAM_PATH/steamapps/common" | grep "^Proton" | sort)

[ ${#protons[@]} -eq 0 ] && { echo "$(err "No Proton found")"; exit 1; }

PS3='Choose proton version (1 - default): '
select SELECTED_PROTON in "${protons[@]}"; do
  if [[ -n "$SELECTED_PROTON" ]]; then
    break
  fi
done

START_SCRIPT="$PFX_PATH/$MC_REL_PATH/LL.sh"
cat > "$START_SCRIPT" <<EOF
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_PATH"
export STEAM_COMPAT_DATA_PATH="$PFX_PATH"
gamemoderun "$STEAM_PATH/steamapps/common/$SELECTED_PROTON/proton" run "$PFX_PATH/$MC_REL_PATH/LL.exe"
EOF
chmod +x "$START_SCRIPT"; echo "$(success "File updated - $(basename "$START_SCRIPT")")"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=LL
Exec=$START_SCRIPT
Type=Application
Terminal=false
Icon=$LL_ICON
Categories=Application;
EOF
echo "$(success "File updated - $(basename "$DESKTOP_FILE")")"

sh -c "$(curl -fsSL -o "$LL_ICON" "$GITHUB_CONTENT/LL.png")" || echo "$(warn "Icon wasn't installed. Just run the same command again.")"
update-desktop-database "$DESKTOP_ENTRY_PATH"
$pfx_flag_missing && { echo -e "$(success "\nMinecraft succusfully installed :)\nYou can play by launching 'LL' icon in overview")"; echo "$(warn "If you want to cnahge proton version, run this script again - $INSTALLER")"; }
