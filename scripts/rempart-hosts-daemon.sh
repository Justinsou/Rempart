#!/bin/bash
# Service système Rempart : maintient la section Rempart de /etc/hosts.
RULES="/Users/Shared/Rempart/hosts-rules.txt"
HOSTS="/etc/hosts"
BEGIN="# >>> REMPART BEGIN"
END="# <<< REMPART END"
DOMAIN_RE='^([a-z0-9-]+\.)+[a-z]{2,}$'
NUM_RE='^[0-9]+$'

while true; do
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
  sleep 3
done
