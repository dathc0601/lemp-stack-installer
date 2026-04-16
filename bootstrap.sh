#!/bin/bash
###############################################################################
#  LEMP Stack Installer — Bootstrap (Remote Installer)
#  Usage: curl -fsSL https://raw.githubusercontent.com/dathc0601/lemp-stack-installer/main/server-setup/bootstrap.sh | sudo bash
#
#  Clones (or updates) the repo to /opt/server-setup, creates the
#  lemp-manage symlink, and hands off to install.sh.
#  Re-running this command updates the installer before executing it.
###############################################################################

set -Eeuo pipefail

INSTALL_DIR="/opt/server-setup"
REPO_URL="https://github.com/dathc0601/lemp-stack-installer.git"
BRANCH="main"

# --- Ensure git is available ------------------------------------------------
if ! command -v git &>/dev/null; then
    echo "[i] Installing git..."
    apt-get update -y -qq && apt-get install -y -qq git
fi

# --- Clone or update --------------------------------------------------------
if [[ -d "${INSTALL_DIR}/.git" ]]; then
    echo "[i] Updating existing installation..."
    git -C "$INSTALL_DIR" fetch origin "$BRANCH" --quiet
    git -C "$INSTALL_DIR" reset --hard "origin/${BRANCH}" --quiet
else
    echo "[i] Cloning installer to ${INSTALL_DIR}..."
    rm -rf "$INSTALL_DIR"
    git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

# --- Create lemp-manage symlink ---------------------------------------------
ln -sf "${INSTALL_DIR}/manage.sh" /usr/local/bin/lemp-manage

# --- Hand off to installer --------------------------------------------------
chmod +x "${INSTALL_DIR}/install.sh"
# Reopen stdin from the terminal — when invoked via `curl | bash`, stdin is the
# pipe (already consumed), so interactive prompts (read) would get EOF.
exec "${INSTALL_DIR}/install.sh" "$@" < /dev/tty
