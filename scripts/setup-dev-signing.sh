#!/bin/zsh
#
# 创建本地自签名代码签名证书，使 TCC 权限在重新构建后持久化。
# 一次性设置；重复运行是幂等的。

set -euo pipefail

IDENTITY_NAME="ShellIsland Dev Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning -v "$KEYCHAIN" 2>/dev/null | grep -q "\"$IDENTITY_NAME\""; then
    echo "✓ Code signing identity \"$IDENTITY_NAME\" already exists and is trusted."
    echo "  scripts/build.sh will use it automatically."
    exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "✗ openssl is required but not on PATH." >&2
    exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

key_pem="$tmp_dir/key.pem"
cert_pem="$tmp_dir/cert.pem"
cert_p12="$tmp_dir/cert.p12"
p12_password=$(openssl rand -hex 16)

echo "• Generating 10-year self-signed code signing certificate…"
openssl req -x509 -newkey rsa:2048 \
    -keyout "$key_pem" -out "$cert_pem" \
    -days 3650 -nodes \
    -subj "/CN=$IDENTITY_NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    2>/dev/null

echo "• Packaging into PKCS#12…"
openssl pkcs12 -export -legacy \
    -out "$cert_p12" -inkey "$key_pem" -in "$cert_pem" \
    -name "$IDENTITY_NAME" \
    -password "pass:$p12_password" \
    2>/dev/null

echo "• Importing into login keychain…"
security import "$cert_p12" \
    -k "$KEYCHAIN" \
    -P "$p12_password" \
    -T /usr/bin/codesign \
    >/dev/null

echo "• Adding Code Signing trust override…"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$cert_pem" >/dev/null

echo
echo "✓ Identity \"$IDENTITY_NAME\" created and trusted."
security find-identity -p codesigning -v "$KEYCHAIN" | grep "\"$IDENTITY_NAME\""
echo
echo "Next: run \`zsh scripts/run.sh\`. The bundle will now be"
echo "signed with this identity, and TCC grants will persist across rebuilds."
