#!/bin/bash
# Requires: certbot + python3-certbot-dns-cloudflare, curl, openssl.  Run as root (default /etc/letsencrypt).
# Usage: pan-acme.sh [-u]   (-u = update config, "-" ends the domain list)
umask 077
DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$DIR/pan-acme.conf"
DOM="$DIR/pan-acme.domains"
LOG="$DIR/pan-acme.log"
CF_CREDS="$DIR/cloudflare.ini"

log() { echo "$(date '+%F %T') [${2:-INFO}] $1" | tee -a "$LOG"; }
die() { log "FAILED: $1" ERROR; exit 1; }
tag() { sed -n "s:.*<$1>\([^<]*\)</$1>.*:\1:p" | head -1; }

read_value() {
  local cur="${!1}" v
  read -rp "$2${cur:+ [$cur]}: " v
  printf -v "$1" '%s' "${v:-$cur}"
}
read_secret() {
  local v
  read -rsp "$2${!1:+ [Enter = keep existing]}: " v; echo
  if [ -n "$v" ]; then printf -v "$1" '%s' "$v"; fi
}

check_response() {  # response step
  echo "$1" | grep -Eq 'status=.success' || die "$2 failed: $1"
}

wait_pan_job() {
  local x s r
  while true; do
    sleep 5
    x=$(/usr/bin/curl -sk --data-urlencode "type=op" --data-urlencode "cmd=<show><jobs><id>$1</id></jobs></show>" --data-urlencode "key=$PAN_KEY" "$URL" | tr -d '\n')
    s=$(echo "$x" | tag status)
    log "  Job $1 status: $s"
    if [ ${#s} -le 1 ] || [ "$s" = "FIN" ]; then break; fi
  done
  r=$(echo "$x" | tag result)
  [ "$r" = "OK" ] || die "Job $1 finished with result: $r"
  log "  Job $1 completed OK"
}

setup() {
  [ -f "$CONF" ] && . "$CONF"
  MODE=${MODE:-panorama}
  ACME=${ACME:-LE_STAGE}
  while true; do
    read_value MODE "Mode (panorama, firewall)"; MODE=${MODE,,}
    [ "$MODE" = panorama ] || [ "$MODE" = firewall ] && break
  done
  read_value ACME "ACME server (LE_STAGE, LE_PROD, or directory URL)"
  case $ACME in
    LE_*) EAB_KID=""; EAB_HMAC="" ;;
    *)    read_value EAB_KID "EAB key ID"; read_secret EAB_HMAC "EAB HMAC key" ;;
  esac
  read_value CONTACT "Contact email"
  read_secret CF_TOKEN "Cloudflare API token"
  read_value PAN_IP "$MODE mgmt IP"

  read -rp "$MODE admin user (blank = keep existing API key): " u
  if [ -n "$u" ]; then
    read -rsp "$MODE admin password: " p; echo
    PAN_KEY=$(/usr/bin/curl -sk --data-urlencode "type=keygen" --data-urlencode "user=$u" --data-urlencode "password=$p" "https://$PAN_IP/api/" | tag key)
  fi

  for var in MODE ACME EAB_KID EAB_HMAC CONTACT CF_TOKEN PAN_IP PAN_KEY; do
    printf '%s=%q\n' "$var" "${!var}"
  done > "$CONF"

  echo; echo "Domains (blank or - to finish)"
  old=(); [ -f "$DOM" ] && mapfile -t old < "$DOM"
  : > "$DOM.new"
  i=0
  while true; do
    read -r name tpl stk <<< "${old[$i]}"
    read_value name "Certificate FQDN #$((i+1))"
    [ -z "$name" ] || [ "$name" = "-" ] && break
    if [ "$MODE" = panorama ]; then
      read_value tpl "  Panorama template"
      read_value stk "  Template stack to push"
    fi
    echo "$name $tpl $stk" >> "$DOM.new"
    i=$((i+1))
  done
  mv "$DOM.new" "$DOM"
  log "Configuration saved to $CONF"
}

[ "$1" = "-u" ] || [ ! -f "$CONF" ] && { setup; [ "$1" = "-u" ] && exit 0; }

##########################################################
#######  Run
###########################################################
log "Run started"
. "$CONF"
URL="https://$PAN_IP/api/"
case $ACME in
  LE_STAGE) SERVER=https://acme-staging-v02.api.letsencrypt.org/directory ;;
  LE_PROD)  SERVER=https://acme-v02.api.letsencrypt.org/directory ;;
  *)        SERVER=$ACME ;;
esac
EAB=(); [ -n "$EAB_KID" ] && EAB=(--eab-kid "$EAB_KID" --eab-hmac-key "$EAB_HMAC")
PFX_PASS=$(/usr/bin/openssl rand -hex 16)
printf 'dns_cloudflare_api_token = %s\n' "$CF_TOKEN" > "$CF_CREDS"
log "Config loaded: mode=$MODE, validation=cloudflare, $(grep -c . "$DOM") certs"

while read -r name tpl stk <&3; do
  #*************  Get Cert
  log "Requesting cert for $name"
  certbot certonly --non-interactive --agree-tos --email "$CONTACT" --server "$SERVER" "${EAB[@]}" --dns-cloudflare --dns-cloudflare-credentials "$CF_CREDS" --dns-cloudflare-propagation-seconds 30 --cert-name "$name" -d "$name" --force-renew < /dev/null || die "certbot failed for $name"
  LIVE=/etc/letsencrypt/live/$name
  [ -s "$LIVE/fullchain.pem" ] && [ -s "$LIVE/privkey.pem" ] || die "Certificate files missing for $name"
  log "Cert for $name issued"

  #*************  Bundle and Copy Cert to PAN
  T=""; [ "$MODE" = panorama ] && T="&target-tpl=$tpl"
  /usr/bin/openssl pkcs12 -export -out "$DIR/full.pfx" -inkey $LIVE/privkey.pem -in $LIVE/cert.pem -certfile $LIVE/chain.pem -passout pass:$PFX_PASS
  log "Uploading cert for $name to $MODE"
  resp=$(/usr/bin/curl -sk --form file=@$LIVE/fullchain.pem "${URL}?type=import&category=certificate&certificate-name=$name&format=pem$T&key=$PAN_KEY")
  check_response "$resp" "Certificate import for $name"
  resp=$(/usr/bin/curl -sk --form file=@"$DIR/full.pfx" "${URL}?type=import&category=private-key&certificate-name=$name&format=pkcs12&passphrase=$PFX_PASS$T&key=$PAN_KEY")
  check_response "$resp" "Private key import for $name"
  rm "$DIR/full.pfx"
  log "Upload complete for $name"
done 3< "$DOM"

##########################################################
#######  Commit / Push
###########################################################
log "Committing changes on $MODE"
resp=$(/usr/bin/curl -sk --data-urlencode "type=commit" --data-urlencode "cmd=<commit/>" --data-urlencode "key=$PAN_KEY" "$URL")
check_response "$resp" "Commit on $MODE"
job=$(echo "$resp" | tag job)

if [ "$MODE" = panorama ]; then
  wait_pan_job "$job"
  for stk in $(awk '$3 {print $3}' "$DOM" | sort -u); do
    log "Pushing to template stack $stk"
    resp=$(/usr/bin/curl -sk --data-urlencode "type=commit" --data-urlencode "action=all" --data-urlencode "cmd=<commit-all><template-stack><name>$stk</name></template-stack></commit-all>" --data-urlencode "key=$PAN_KEY" "$URL")
    check_response "$resp" "Push to $stk"
    log "Push started for $stk - job $(echo "$resp" | tag job)"
  done
else
  log "Commit job $job started (not waiting)"
fi
log "Run finished"
