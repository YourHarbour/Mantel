#!/bin/bash
# Creates a self-signed code signing identity for Mantel, in the login keychain.
#
# Why: macOS keys the Accessibility permission (and every other TCC permission) to the app's
# code signature. Ad-hoc signing has no stable identity, so the signature changes on every
# rebuild and the permission silently stops applying — the row stays ticked in System Settings
# while the app is told it isn't trusted. A self-signed certificate gives the app one fixed
# identity, so a grant survives rebuilds.
#
# The certificate never leaves this machine and is not a security boundary: it lets macOS
# recognise "this is the same app as last time", nothing more.
set -euo pipefail

NAME="Mantel Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "已存在：$NAME"
    security find-identity -v -p codesigning | grep "$NAME" || true
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# LibreSSL (what macOS ships as `openssl`) has no -legacy flag, so do not pass one.
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -passout pass:mantel 2>/dev/null

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P mantel \
    -T /usr/bin/codesign -T /usr/bin/security

# Trust it for code signing, in the user's own trust domain (no admin rights needed).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "已创建：$NAME"
security find-identity -v -p codesigning | grep "$NAME" || true
