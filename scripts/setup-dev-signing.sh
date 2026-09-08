#!/bin/bash
# Create one local signing identity. Never rotates an existing certificate.
set -euo pipefail
umask 077
name="Murmeln Dev"

if [[ $# -ne 0 ]]; then
  echo "Usage: bash scripts/setup-dev-signing.sh" >&2
  exit 2
fi

identities=$(/usr/bin/security find-identity -v -p codesigning | awk '/"Murmeln Dev"$/ {print $2}')
if [[ "$identities" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "Reusing the existing Murmeln Dev signing identity: $identities"
  exit 0
fi
if [[ -n "$identities" ]] || /usr/bin/security find-certificate -c "$name" >/dev/null 2>&1; then
  echo "An existing Murmeln Dev certificate needs repair in Keychain Access. Refusing to replace it or change identity." >&2
  exit 1
fi

keychain=$(/usr/bin/security default-keychain -d user | sed -E 's/^[[:space:]]*"(.*)"$/\1/')
[[ -f "$keychain" ]] || { echo "No user keychain is available." >&2; exit 1; }
temporary=$(mktemp -d "${TMPDIR:-/tmp}/murmeln-signing-setup.XXXXXX")
trap 'rm -rf "$temporary"' EXIT

cat > "$temporary/openssl.cnf" <<'CONFIG'
[req]
prompt = no
distinguished_name = subject
x509_extensions = code_signing
[subject]
CN = Murmeln Dev
[code_signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
CONFIG

# Temporary private material is owner-only, never printed, and removed on exit.
/usr/bin/openssl req -new -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
  -config "$temporary/openssl.cnf" -keyout "$temporary/key.pem" \
  -out "$temporary/certificate.pem" > "$temporary/openssl.log" 2>&1
# LibreSSL req writes PKCS#8; security's openssl importer needs PKCS#1 RSA.
/usr/bin/openssl rsa -in "$temporary/key.pem" -out "$temporary/key-rsa.pem" \
  >> "$temporary/openssl.log" 2>&1
/usr/bin/security import "$temporary/key-rsa.pem" -k "$keychain" -f openssl -t priv \
  -x -T /usr/bin/codesign
/usr/bin/security import "$temporary/certificate.pem" -k "$keychain" -f pemseq -t cert
# User trust for code signing only. No system keychain, TLS trust or broad key ACL.
/usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$temporary/certificate.pem"

identity=$(/usr/bin/security find-identity -v -p codesigning | awk '/"Murmeln Dev"$/ {print $2}')
expected=$(/usr/bin/openssl x509 -in "$temporary/certificate.pem" -noout -fingerprint -sha1 | sed 's/.*=//;s/://g')
[[ "$identity" == "$expected" ]] || { echo "The new certificate is not a unique usable signing identity. Repair it in Keychain Access; do not generate another." >&2; exit 1; }
echo "Created the local Murmeln Dev signing identity: $identity"
echo "The private key is in your user keychain. Existing app permissions were not changed."
