#!/bin/bash
# Usage (root) : install-daemon.sh install|uninstall <dossier_ressources>
set -e
ACTION="$1"
RES="$2"
DEST="/Library/Application Support/Rempart"
PLIST="/Library/LaunchDaemons/com.rempart.hosts.plist"

case "$ACTION" in
  install)
    mkdir -p "$DEST"
    cp "$RES/rempart-hosts-daemon.sh" "$DEST/hosts-daemon.sh"
    cp "$RES/com.rempart.hosts.plist" "$PLIST"
    chown root:wheel "$DEST/hosts-daemon.sh" "$PLIST"
    chmod 755 "$DEST/hosts-daemon.sh"
    chmod 644 "$PLIST"
    launchctl bootout system "$PLIST" 2>/dev/null || true
    launchctl bootstrap system "$PLIST"
    ;;
  uninstall)
    launchctl bootout system "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    rm -rf "$DEST"
    awk -v b="# >>> REMPART BEGIN" -v e="# <<< REMPART END" '$0==b{s=1;next} $0==e{s=0;next} !s{print}' /etc/hosts > /tmp/rempart-hosts.clean
    cat /tmp/rempart-hosts.clean > /etc/hosts
    rm -f /tmp/rempart-hosts.clean
    dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null || true
    ;;
esac
