#!/usr/bin/env bash
# ============================================================
#  arch_cleanup.sh — Comprehensive Arch Linux System Cleanup
#  Run as a normal user (sudo will be invoked where needed)
# ============================================================

set -euo pipefail

# ── Colours ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[DONE]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Helpers ──────────────────────────────────────────────────
free_space_mb() { df --output=avail -m / | tail -1 | tr -d ' '; }

ask() {
    # ask <prompt> — returns 0 (yes) or 1 (no)
    local ans
    read -rp "$(echo -e "${YELLOW}[?]${RESET} $1 [y/N]: ")" ans
    [[ "${ans,,}" == "y" ]]
}

# ── Preflight ────────────────────────────────────────────────
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║      Arch Linux System Cleanup Script        ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

BEFORE=$(free_space_mb)
info "Free space before cleanup: ${BEFORE} MB"

# ── 1. Pacman Cache ──────────────────────────────────────────
section "Pacman Package Cache"

if command -v paccache &>/dev/null; then
    info "Removing all but the 2 most recent versions of each cached package…"
    sudo paccache -rk2
    info "Removing cached packages for uninstalled software…"
    sudo paccache -ruk0
    success "paccache sweep complete."
else
    warn "'paccache' not found. Install 'pacman-contrib' for smarter cache pruning."
    warn "Falling back to full pacman cache wipe (keeps no old packages)."
    if ask "Wipe entire pacman cache (/var/cache/pacman/pkg)?"; then
        sudo pacman -Scc --noconfirm
        success "Pacman cache wiped."
    fi
fi

# ── 2. Orphaned Packages ─────────────────────────────────────
section "Orphaned Packages"

ORPHANS=$(pacman -Qdtq 2>/dev/null || true)
if [[ -n "$ORPHANS" ]]; then
    echo -e "${YELLOW}Orphaned packages found:${RESET}"
    echo "$ORPHANS"
    if ask "Remove all orphaned packages?"; then
        # shellcheck disable=SC2086
        sudo pacman -Rns --noconfirm $ORPHANS
        success "Orphans removed."
    fi
else
    success "No orphaned packages found."
fi

# ── 3. AUR / yay / paru Cache ────────────────────────────────
section "AUR Helper Cache"

for helper in yay paru; do
    if command -v "$helper" &>/dev/null; then
        info "Cleaning $helper cache…"
        "$helper" -Sc --noconfirm 2>/dev/null || true
        success "$helper cache cleaned."
    fi
done

# ── 4. Systemd Journal Logs ──────────────────────────────────
section "Systemd Journal Logs"

JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null | awk '{print $NF}' || echo "unknown")
info "Current journal size: ${JOURNAL_SIZE}"
if ask "Truncate journal to last 2 weeks / 200 MB?"; then
    sudo journalctl --vacuum-time=2weeks --vacuum-size=200M
    success "Journal vacuumed."
fi

# ── 5. User Cache (~/.cache) ─────────────────────────────────
section "User Cache (~/.cache)"

CACHE_SIZE=$(du -sh "$HOME/.cache" 2>/dev/null | cut -f1 || echo "0")
info "~/.cache size: ${CACHE_SIZE}"

# Always safe to clear these sub-directories
SAFE_CACHE_DIRS=(
    "$HOME/.cache/thumbnails"
    "$HOME/.cache/pip"
    "$HOME/.cache/go/build"
    "$HOME/.cache/npm"
    "$HOME/.cache/yarn"
    "$HOME/.cache/pnpm"
    "$HOME/.cache/cargo/registry"
    "$HOME/.cache/rust"
    "$HOME/.cache/fontconfig"
    "$HOME/.cache/mesa_shader_cache"
    "$HOME/.cache/nvidia"
    "$HOME/.cache/google-chrome/Default/Cache"
    "$HOME/.cache/chromium/Default/Cache"
    "$HOME/.cache/mozilla/firefox"
    "$HOME/.cache/BraveSoftware"
    "$HOME/.cache/vivaldi"
    "$HOME/.cache/opera"
    "$HOME/.cache/thunderbird"
)

info "Clearing known safe cache directories…"
for dir in "${SAFE_CACHE_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
        info "  Cleared: $dir"
    fi
done
success "Safe cache directories cleared."

if ask "Also wipe ENTIRE ~/.cache (may slow first app launch)?"; then
    rm -rf "$HOME/.cache"/*
    success "~/.cache fully wiped."
fi

# ── 6. Temporary Files ───────────────────────────────────────
section "Temporary Files"

info "Clearing /tmp…"
sudo rm -rf /tmp/* 2>/dev/null || true
success "/tmp cleared."

if [[ -d /var/tmp ]]; then
    if ask "Clear /var/tmp (persistent temp files)?"; then
        sudo rm -rf /var/tmp/* 2>/dev/null || true
        success "/var/tmp cleared."
    fi
fi

# ── 7. Broken Symlinks ───────────────────────────────────────
section "Broken Symlinks (Home Directory)"

info "Searching for broken symlinks in ~ (may take a moment)…"
BROKEN_LINKS=$(find "$HOME" -xtype l 2>/dev/null | head -50 || true)
if [[ -n "$BROKEN_LINKS" ]]; then
    echo -e "${YELLOW}Broken symlinks found:${RESET}"
    echo "$BROKEN_LINKS"
    if ask "Delete all broken symlinks listed above?"; then
        find "$HOME" -xtype l -delete 2>/dev/null || true
        success "Broken symlinks removed."
    fi
else
    success "No broken symlinks found."
fi

# ── 8. Trash / Rubbish Bin ───────────────────────────────────
section "Trash"

TRASH_DIR="$HOME/.local/share/Trash"
if [[ -d "$TRASH_DIR" ]]; then
    TRASH_SIZE=$(du -sh "$TRASH_DIR" 2>/dev/null | cut -f1 || echo "0")
    info "Trash size: ${TRASH_SIZE}"
    if ask "Empty trash?"; then
        rm -rf "${TRASH_DIR:?}/files/"* "${TRASH_DIR:?}/info/"* 2>/dev/null || true
        success "Trash emptied."
    fi
else
    success "Trash directory not found / already empty."
fi

# ── 9. Old Config / Residue Directories ──────────────────────
section "App Residue (config dirs for removed apps)"

info "Scanning ~/.config and ~/.local/share for directories whose app is no longer installed…"

RESIDUE_FOUND=false
for cfg_dir in "$HOME/.config"/*/; do
    app=$(basename "$cfg_dir")
    # Skip common non-app dirs
    [[ "$app" =~ ^(systemd|dconf|pulse|pipewire|user-dirs|mimeapps|autostart|environment\.d)$ ]] && continue
    if ! pacman -Qq "$app" &>/dev/null 2>&1; then
        echo -e "  ${YELLOW}Possible residue:${RESET} $cfg_dir  (no pacman package named '$app')"
        RESIDUE_FOUND=true
    fi
done

if $RESIDUE_FOUND; then
    warn "Review the list above — not every directory maps 1-to-1 to a package name."
    warn "Delete them manually if you're sure the app is gone."
else
    success "No obvious config residue detected."
fi

# ── 10. Flatpak (if installed) ───────────────────────────────
section "Flatpak Cleanup"

if command -v flatpak &>/dev/null; then
    info "Removing unused Flatpak runtimes…"
    flatpak uninstall --unused -y 2>/dev/null || true
    info "Removing Flatpak cache…"
    rm -rf "$HOME/.var/app/"*"/cache/"* 2>/dev/null || true
    success "Flatpak cleaned."
else
    info "Flatpak not installed — skipping."
fi

# ── 11. Docker (if installed) ────────────────────────────────
section "Docker Cleanup"

if command -v docker &>/dev/null; then
    if ask "Run 'docker system prune' (removes stopped containers, dangling images, unused networks)?"; then
        docker system prune -f
        success "Docker pruned."
    fi
else
    info "Docker not installed — skipping."
fi

# ── 12. Python / pip Cache ───────────────────────────────────
section "Python pip Cache"

PIP_CACHE=$(pip cache dir 2>/dev/null || echo "")
if [[ -n "$PIP_CACHE" && -d "$PIP_CACHE" ]]; then
    info "Clearing pip cache at $PIP_CACHE…"
    pip cache purge 2>/dev/null || rm -rf "$PIP_CACHE"
    success "pip cache cleared."
fi

# ── 13. Cargo / Rust Cache ───────────────────────────────────
section "Rust / Cargo Cache"

if [[ -d "$HOME/.cargo/registry/cache" ]]; then
    CARGO_SIZE=$(du -sh "$HOME/.cargo/registry/cache" 2>/dev/null | cut -f1 || echo "0")
    info "Cargo registry cache: ${CARGO_SIZE}"
    if ask "Clear Cargo registry cache?"; then
        rm -rf "$HOME/.cargo/registry/cache"
        success "Cargo cache cleared."
    fi
fi

# ── 14. Node / npm Cache ─────────────────────────────────────
section "Node.js / npm Cache"

if command -v npm &>/dev/null; then
    info "Clearing npm cache…"
    npm cache clean --force 2>/dev/null || true
    success "npm cache cleared."
fi

if command -v yarn &>/dev/null; then
    info "Clearing yarn cache…"
    yarn cache clean 2>/dev/null || true
    success "yarn cache cleared."
fi

# ── 15. Thumbnail Cache ──────────────────────────────────────
section "Thumbnail Cache"

THUMB_DIR="$HOME/.cache/thumbnails"
if [[ -d "$THUMB_DIR" ]]; then
    THUMB_SIZE=$(du -sh "$THUMB_DIR" 2>/dev/null | cut -f1 || echo "0")
    info "Thumbnail cache: ${THUMB_SIZE}"
    rm -rf "$THUMB_DIR"
    success "Thumbnail cache removed."
fi

# ── 16. Duplicate pacman DB locks ────────────────────────────
section "Pacman Lock File"

if [[ -f /var/lib/pacman/db.lck ]]; then
    warn "Stale pacman lock file detected!"
    if ask "Remove /var/lib/pacman/db.lck? (Only do this if no pacman process is running)"; then
        sudo rm /var/lib/pacman/db.lck
        success "Lock file removed."
    fi
else
    success "No stale pacman lock file."
fi

# ── Summary ──────────────────────────────────────────────────
AFTER=$(free_space_mb)
SAVED=$(( AFTER - BEFORE ))

section "Cleanup Complete"
echo -e "  Free space before : ${BOLD}${BEFORE} MB${RESET}"
echo -e "  Free space after  : ${BOLD}${AFTER} MB${RESET}"
echo -e "  Space reclaimed   : ${GREEN}${BOLD}${SAVED} MB${RESET}"
echo ""
success "Arch Linux cleanup finished. Enjoy your lean system!"
