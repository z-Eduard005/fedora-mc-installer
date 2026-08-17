#!/bin/bash
INSTALL_DIR="$HOME/Programs/proton-legacylauncher"
LL_URL="https://dl.llaun.ch/legacy/installer"
LL_FILENAME="LegacyLauncher.exe"
STEAM_PATH="$HOME/.steam/steam"
STEAM_COMPDATA_DIR="$STEAM_PATH/steamapps/compatdata"
FIRST_LOCAL_STEAM_APP_ID=2147483647
MC_REL_PATH="pfx/drive_c/users/steamuser/AppData/Roaming/.tlauncher/legacy/Minecraft"
PFX_FILE_FLAG="$INSTALL_DIR/.pfx-created"
INSTALLER="$INSTALL_DIR/installer.sh"
DESKTOP_ENTRY_PATH="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_ENTRY_PATH/LL.desktop"
LL_ICON="$HOME/.local/share/icons/LL.png"
GITHUB_CONTENT="https://raw.githubusercontent.com/z-Eduard005/linux-mc-installer/main"
DEFAULT_PROTON="Proton Hotfix"
BOOKMARKS_FILE="$HOME/.config/gtk-3.0/bookmarks"

success() { printf "\033[1;32m%b\033[0m" "$1"; }
err() { printf "\033[1;31m%b\033[0m" "$1"; }
warn() { printf "\033[1;33m%b\033[0m" "$1"; }

ask_confirm() {
  read -rp "$(warn "$1 [y/N]: ")" proceed
  [[ "$proceed" != [yY] ]] && { echo "$(err "Aborted.")"; exit 1; }
}

pm_install() {
  local cmd=""
  if command -v dnf >/dev/null 2>&1; then
    cmd="sudo dnf install -y --skip-unavailable"
  elif command -v apt >/dev/null 2>&1; then
    cmd="sudo apt install -y --ignore-missing"
  elif command -v pacman >/dev/null 2>&1; then
    cmd="sudo pacman -S --noconfirm"
  elif command -v zypper >/dev/null 2>&1; then
    cmd="sudo zypper install -y"
  elif command -v xbps-install >/dev/null 2>&1; then
    cmd="sudo xbps-install -Sy"
  else
    echo "$(err "No supported package manager found. Please install $1 manually")"; exit 1
  fi
  $cmd "$1" || { echo "$(err "Failed to install $1. Try again.")"; exit 1; }
}

create_start_script() {
  cat > "$START_SCRIPT" <<EOF
detect_dri_prime() {
  local onboard=\$(lspci -nnk 2>/dev/null | grep -B1 "Onboard" | grep "1002" | awk '{print \$1}')
  local amd_gpus=\$(lspci -nnd ::03xx 2>/dev/null | grep "1002")
  local bus_id

  if [ -n "\$onboard" ]; then
    bus_id=\$(echo "\$amd_gpus" | grep -v "\$onboard" | head -1 | awk '{print \$1}')
  else
    bus_id=\$(echo "\$amd_gpus" | head -1 | awk '{print \$1}')
  fi

  [ -n "\$bus_id" ] && echo "pci-0000_\$(echo "\$bus_id" | tr ':.' '_')" || echo "1"
}

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_PATH"
export STEAM_COMPAT_DATA_PATH="$PFX_PATH"
DRI_PRIME="\$(detect_dri_prime)" gamemoderun "$STEAM_PATH/steamapps/common/${SELECTED_PROTON:-$DEFAULT_PROTON}/proton" run "$PFX_PATH/$MC_REL_PATH/LL.exe"
EOF
  chmod +x "$START_SCRIPT"
}

if [ "$EUID" -eq 0 ]; then
  echo "$(err 'Do not run this script with "sudo"!')" >&2
  exit 1
fi

sudo -v || exit 1
while true; do
  sudo -n true
  sleep 240
  kill -0 "$$" || exit
done 2>/dev/null &

command -v gamemoderun >/dev/null 2>&1 || pm_install gamemode
command -v xdg-open >/dev/null 2>&1 || pm_install xdg-utils
command -v curl >/dev/null 2>&1 || pm_install curl
command -v inotifywait >/dev/null 2>&1 || pm_install inotify-tools
command -v lspci >/dev/null 2>&1 || pm_install pciutils

pfx_flag_missing=false
[ ! -f "$PFX_FILE_FLAG" ] && pfx_flag_missing=true
$pfx_flag_missing && echo "$(success "Installing LegacyLauncher for steam-proton use...")"
mkdir -p "$INSTALL_DIR"

if [ ! -d "$STEAM_PATH" ]; then
  echo "Steam is not installed. Installing via package manager..."
  if flatpak list | grep -q com.valvesoftware.Steam; then
    if ask_confirm "Detected Flatpak version of Steam. Do you want to reinstall it as native version? (this will delete app data)"; then
      sudo flatpak remove -y com.valvesoftware.Steam
    else
      echo "$(err "This program works only with native version of steam :(")"
      exit 1
    fi
  fi

  pm_install steam
  steam >/dev/null 2>&1 &
fi

curl -fsSL -o "$INSTALLER" "$GITHUB_CONTENT/installer.sh" || { echo "$(err "Script wasn't installed. Try again.")"; exit 1; }
chmod +x "$INSTALLER"
echo "$(success "File updated - $(basename "$INSTALLER")")"

if [ ! -f "$INSTALL_DIR/$LL_FILENAME" ]; then
  echo "$(success "Please install LegacyLauncher first from opening link")"
  for i in 3 2 1; do echo -ne "\r$i"; sleep 1; done; echo -ne "\rWaiting...\n"
  xdg-open "$LL_URL" >/dev/null 2>&1 &
  sleep 3

  while true; do
    f=$(timeout 60s inotifywait -e moved_to --format "%f" "$HOME/Downloads" 2>/dev/null)
    [ $? -eq 124 ] && { echo "$(err "No new files detected in 1 minute. Exiting.")"; exit 1; }
    [ -z "$f" ] && continue
    [[ "$f" =~ \.(part|crdownload|tmp)$ ]] && continue
    break
  done

  [ -z "$f" ] && { echo "$(err "LegacyLauncher download not detected. Try again.")"; exit 1; }
  mv -n "$HOME/Downloads/$f" "$INSTALL_DIR/$LL_FILENAME"
  echo "Moved $f to $INSTALL_DIR/$LL_FILENAME"
fi

if $pfx_flag_missing; then
  if ! pgrep -x "steam" >/dev/null; then
    steam >/dev/null 2>&1 &
  fi

  echo "$(warn "Once Steam has launched, follow these steps:")"
  cat <<EOF
  1. In Steam, use 'Add a Non-Steam Game' to add: $INSTALL_DIR/$LL_FILENAME
  2. Right-click the game entry in Steam and select 'Manage...'
    2.1. Mark it as Hidden!
  3. Right-click the game entry in Steam and select 'Properties...'
    3.1. Disable steam overlay
    3.2. Compatibility -> force to use specific compatibility tool -> '$DEFAULT_PROTON'
    3.3. Press Play -> install -> close it without downloading any version!

Continue only after all done
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
  if [ ! -d "$INSTALL_DIR/$(basename "$PFX_PATH")" ]; then
    mv "$PFX_PATH" "$INSTALL_DIR/$(basename "$PFX_PATH")"
    ln -s "$INSTALL_DIR/$(basename "$PFX_PATH")" "$STEAM_COMPDATA_DIR"
    echo "$(basename "$PFX_PATH")" > "$PFX_FILE_FLAG"
    chmod -w "$PFX_FILE_FLAG"
  fi

  if ! grep -q "file://$PFX_PATH/$MC_REL_PATH Minecraft" "$BOOKMARKS_FILE" 2>/dev/null; then
    sed -i "1s|^|file://$PFX_PATH/$MC_REL_PATH Minecraft\n|" "$BOOKMARKS_FILE"
  fi
fi
[ -z "$PFX_PATH" ] && PFX_PATH="$INSTALL_DIR/$(cat "$PFX_FILE_FLAG")"

START_SCRIPT="$PFX_PATH/$MC_REL_PATH/LL.sh"; create_start_script

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

create_start_script
echo "$(success "File updated - $(basename "$START_SCRIPT")")"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=LL
Exec=/bin/bash -lc "$START_SCRIPT"
Type=Application
Terminal=false
Icon=$LL_ICON
Categories=Application;
EOF
echo "$(success "File updated - $(basename "$DESKTOP_FILE")")"

curl -fsSL -o "$LL_ICON" "$GITHUB_CONTENT/LL.png" || echo "$(warn "Icon wasn't installed. Just run the same command again.")"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_ENTRY_PATH"

$pfx_flag_missing && echo -e "$(success "\nMinecraft successfully installed\nYou can play by launching 'LL' desktop file\n")"
echo "$(warn "If you want to change proton version, run this script again - $INSTALLER")"
