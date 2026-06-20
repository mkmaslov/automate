#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# This script creates an SSL certificate and pushes it to OpenWRT router.
# -----------------------------------------------------------------------------

# BEGIN_SHARED
# -----------------------------------------------------------------------------
PRE=$'\033[1;31m'
MSG='ERROR: this is a template script, do NOT run this'
POST=$'\033[0m'
printf '%s%s%s\n' "$PRE" "$MSG" "$POST" >&2
return 1 2>/dev/null || exit 1
# -----------------------------------------------------------------------------
# END_SHARED

#------------------------------------------------------------------------------
# Script-specific functions
#------------------------------------------------------------------------------

# Show usage instructions and exit
usage() { 
  title "Usage: ${0##*/} -t SSH_TARGET [-h ROUTER_HOST] [-a ROUTER_IP] [-d DIR_CERT]"
  msg "\nExamples:"
  msg "  ${0##*/} -t root@192.168.10.1"
  msg "  ${0##*/} -t root@192.168.10.1 -h router.lan -a 192.168.10.1 -d ./OPENWRT-CERT"
  msg "\nDefaults:"
  msg "  ROUTER_HOST=router.lan"
  msg "  ROUTER_IP=192.168.10.1"
  msg "  DIR_CERT=./OPENWRT-CERT"
  exit 1
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT
# ═════════════════════════════════════════════════════════════════════════════

# Parse CLI arguments
SSH_TARGET=""
ROUTER_HOST="router.lan"
ROUTER_IP="192.168.10.1"
DIR_CERT="./OPENWRT-CERT"

while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case "$1" in
    -t) SSH_TARGET="$2" ;;
    -h) ROUTER_HOST="$2" ;;
    -a) ROUTER_IP="$2" ;;
    -d) DIR_CERT="$2" ;;
    *) usage ;;
  esac
  shift 2
done
[[ -n "$SSH_TARGET" ]] || usage

# Verify that required commands are enabled
enforce_cmds openssl ssh

# Create folder for local certificate authority
mkdir -p "${DIR_CERT}"
# Convert relative path to absolute
PATH_CERT="$(cd "${DIR_CERT}" && pwd)"
msg "Created ${PATH_CERT}"

# Create local CA
openssl genrsa -out "${PATH_CERT}/local-CA.key" 4096
openssl req -x509 -new -nodes -key "${PATH_CERT}/local-CA.key" -sha256 \
  -days 3650 -out "${PATH_CERT}/local-CA.crt" -subj "/CN=local CA for uhttpd"
msg "Created local CA key and certificate"

# Create OpenSSL config for uhttpd certificate
cat > "${PATH_CERT}/uhttpd-cert.cnf" <<EOF
  [req]
  default_bits       = 2048
  prompt             = no
  default_md         = sha256
  distinguished_name = dn
  req_extensions     = req_ext
  [dn]
  CN = ${ROUTER_HOST}
  [req_ext]
  subjectAltName = @alt_names
  [alt_names]
  DNS.1 = ${ROUTER_HOST}
  IP.1 = ${ROUTER_IP}
EOF

# Create uhttpd private key and CSR
openssl genrsa -out "${PATH_CERT}/uhttpd.key" 2048
openssl req -new -key "${PATH_CERT}/uhttpd.key" \
  -out "${PATH_CERT}/uhttpd.csr" -config "${PATH_CERT}/uhttpd-cert.cnf"

# Sign uhttpd certificate with local CA
openssl x509 -req -in "${PATH_CERT}/uhttpd.csr" -out "${PATH_CERT}/uhttpd.crt" \
  -CA "${PATH_CERT}/local-CA.crt" -CAkey "${PATH_CERT}/local-CA.key" -CAcreateserial \
  -days 825 -sha256 -extensions req_ext -extfile "${PATH_CERT}/uhttpd-cert.cnf"
msg "Signed uhttpd certificate with local CA"

# Copy certificate/key to router
cat "${PATH_CERT}/uhttpd.crt" | ssh "${SSH_TARGET}" "cat > /etc/uhttpd-custom.crt"
cat "${PATH_CERT}/uhttpd.key" | ssh "${SSH_TARGET}" "cat > /etc/uhttpd-custom.key"
msg "Sent uhttpd certificate and key to router"

# Change router config
ssh "${SSH_TARGET}" 'sh -s' <<EOF
  set -e

  ROUTER_HOST='${ROUTER_HOST}'
  ROUTER_IP='${ROUTER_IP}'

  # Use custom uhttpd certificate/key
  uci set uhttpd.main.cert='/etc/uhttpd-custom.crt'
  uci set uhttpd.main.key='/etc/uhttpd-custom.key'
  uci commit uhttpd

  # Fix file permissions
  chmod 644 /etc/uhttpd-custom.crt
  chmod 600 /etc/uhttpd-custom.key

  # Make router.lan resolve locally
  uci -q del_list dhcp.@dnsmasq[0].address="/\${ROUTER_HOST}/\${ROUTER_IP}"
  uci add_list dhcp.@dnsmasq[0].address="/\${ROUTER_HOST}/\${ROUTER_IP}"
  uci commit dhcp

  # Restart services
  /etc/init.d/uhttpd restart
  /etc/init.d/dnsmasq restart
EOF

success "Created certificates in: ${PATH_CERT}"
msg "Import this CA certificate into browser:"
msg "  ${PATH_CERT}/local-CA.crt"

# -----------------------------------------------------------------------------