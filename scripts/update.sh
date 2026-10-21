#!/bin/bash
set -euo pipefail

UPSTREAM_OWNER_REPO="${UPSTREAM_OWNER_REPO:-throwaway31265/free-sleep}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/${UPSTREAM_OWNER_REPO}/${UPSTREAM_BRANCH}/scripts/install.sh"

REPO_PATH="/home/dac/free-sleep"
BACKUP_BASE="/home/dac/free-sleep-backup"
BACKUP_PATH="${BACKUP_BASE}-$(date +%Y%m%d-%H%M%S)"
TEMP_INSTALL_SCRIPT="/tmp/free-sleep-install-$$.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: update.sh must be run as root."
  exit 1
fi

if [ -d "$BACKUP_BASE" ]; then
  echo "WARNING: Legacy backup folder $BACKUP_BASE already exists."
  echo "It will not be modified by this run."
fi

# Keep biometrics stopped through the downloaded installer, including older installers.
services_to_restore=""
restore_services() {
  for service_name in $services_to_restore; do
    systemctl start "$service_name" || true
  done
  rm -f "$TEMP_INSTALL_SCRIPT"
}
trap restore_services EXIT
for service_name in free-sleep-stream free-sleep; do
  if systemctl is-active --quiet "$service_name"; then
    services_to_restore="$service_name $services_to_restore"
    systemctl stop "$service_name"
  fi
done

if [ -f /persistent/free-sleep-data/free-sleep.db ] && [ -f "$REPO_PATH/scripts/sqlite_maintenance.py" ]; then
  python3 "$REPO_PATH/scripts/sqlite_maintenance.py" backup \
    /persistent/free-sleep-data/free-sleep.db \
    /persistent/free-sleep-data/free-sleep-copy.db --checkpoint
fi

if [ -x "$REPO_PATH/scripts/unblock_internet_access.sh" ]; then
  echo "Unblocking WAN access before update..."
  sh "$REPO_PATH/scripts/unblock_internet_access.sh"
else
  echo "WARNING: $REPO_PATH/scripts/unblock_internet_access.sh not found, continuing without unblocking script."
fi

if systemctl list-unit-files --type=service --no-pager | grep -q '^free-sleep.service'; then
  echo "Stopping free-sleep.service..."
  systemctl stop free-sleep.service || true
  echo "Disabling free-sleep.service..."
  systemctl disable free-sleep.service || true
fi

if [ -d "$REPO_PATH" ]; then
  echo "Backing up current repository to $BACKUP_PATH..."
  mv "$REPO_PATH" "$BACKUP_PATH"
else
  echo "WARNING: $REPO_PATH not found. Continuing without backup."
fi

echo "Downloading installer from $INSTALL_SCRIPT_URL..."
curl -fsSL "$INSTALL_SCRIPT_URL" -o "$TEMP_INSTALL_SCRIPT"
chmod 700 "$TEMP_INSTALL_SCRIPT"

update_succeeded=false
if [ -s "$TEMP_INSTALL_SCRIPT" ] && /bin/bash "$TEMP_INSTALL_SCRIPT" && [ -d "$REPO_PATH" ]; then
  echo "Update completed successfully."
  update_succeeded=true
  if [ -d "$BACKUP_PATH" ]; then
    rm -rf "$BACKUP_PATH"
  fi
else
  echo "ERROR: Update failed, restoring backup..."
  rm -rf "$REPO_PATH"
  if [ -d "$BACKUP_PATH" ]; then
    mv "$BACKUP_PATH" "$REPO_PATH"
    if systemctl list-unit-files --type=service --no-pager | grep -q '^free-sleep.service'; then
      systemctl enable free-sleep.service || true
      systemctl start free-sleep.service || true
    fi
  else
    echo "ERROR: Backup path $BACKUP_PATH does not exist; cannot restore."
    exit 1
  fi
fi

if [ -x "$REPO_PATH/scripts/block_internet_access.sh" ]; then
  echo "Re-applying WAN block rules..."
  sh "$REPO_PATH/scripts/block_internet_access.sh"
else
  echo "WARNING: $REPO_PATH/scripts/block_internet_access.sh not found, skipping."
fi

if [ "$update_succeeded" != true ]; then
  echo "Update failed; the previous installation was restored." >&2
  exit 1
fi

echo -e "\033[0;32mUpdate script finished.\033[0m"
echo -e "\033[0;32mRecommended: reboot with 'reboot -h now'.\033[0m"
