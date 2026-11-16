#!/bin/bash
# REMPART_DAEMON_VERSION=3
# Service système Rempart (root) :
#  1. maintient la section Rempart de /etc/hosts (sites bloqués)
#  2. ferme les apps bloquées, même si l'app Rempart est quittée
RULES="/Users/Shared/Rempart/hosts-rules.txt"
APPS="/Users/Shared/Rempart/apps-rules.txt"
HOSTS="/etc/hosts"
BEGIN="# >>> REMPART BEGIN"
END="# <<< REMPART END"
DOMAIN_RE='^([a-z0-9-]+\.)+[a-z]{2,}$'
NUM_RE='^[0-9]+$'

sync_hosts() {
  local now block tmp p domain until
  now=$(date +%s)
  block=""
  if [ -f "$RULES" ]; then
    while read -r domain until; do
      [[ "$domain" =~ $DOMAIN_RE ]] || continue
      if [ -n "$until" ]; then
        [[ "$until" =~ $NUM_RE ]] || continue
        [ "$until" -gt "$now" ] && continue
      fi
      for p in "" www. m. mobile.; do
        block+="0.0.0.0 ${p}${domain}"$'\n'
        block+=":: ${p}${domain}"$'\n'
      done
    done < "$RULES"
  fi

  tmp=$(mktemp /tmp/rempart-hosts.XXXXXX)
  awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip{print}' "$HOSTS" > "$tmp"
  if [ -n "$block" ]; then
    { echo "$BEGIN"; printf "%s" "$block"; echo "$END"; } >> "$tmp"
  fi
  if ! cmp -s "$tmp" "$HOSTS"; then
    cat "$tmp" > "$HOSTS"
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null
  fi
  rm -f "$tmp"
}

kill_apps() {
  [ -f "$APPS" ] || return
  local now procs until path pid
  now=$(date +%s)
  procs=$(ps -axo pid=,command=)
  while IFS='|' read -r until path; do
    [[ "$until" =~ $NUM_RE ]] || continue
    [[ "$path" == /*.app ]] || continue
    case "$path" in
      *..*|*/Rempart.app|*/Finder.app|*/System\ Settings.app) continue ;;
      /Applications/*.app|/System/Applications/*.app|/Users/*/Applications/*.app) ;;
      *) continue ;;
    esac
    [ "$until" -gt "$now" ] && continue
    for pid in $(printf "%s\n" "$procs" | awk -v p="$path/Contents/" 'index($0,p)>0 {print $1}'); do
      kill -9 "$pid" 2>/dev/null
    done
  done < "$APPS"
}

while true; do
  sync_hosts
  kill_apps
  sleep 2
done
