#!/bin/bash
# 生成签名安装包：astrbot-installer-v<VER>.tar.gz + manifest.json + manifest.sig
# 用法：
#   ./tools/make-release.sh                  # 默认 1.0.0
#   ./tools/make-release.sh 1.0.1            # 指定版本
# 依赖：openssl、tar、sha256sum
set -euo pipefail

cd "$(dirname "$0")/.."

VER="${1:-1.0.0}"
OUT="release"
KEY="${INSTALLER_KEY:-tools/keys/installer-key.pem}"

if [ ! -f "$KEY" ]; then
  echo "缺少签名私钥：$KEY"
  echo "生成新密钥对："
  echo "  mkdir -p tools/keys && openssl genpkey -algorithm ed25519 -out tools/keys/installer-key.pem"
  echo "  openssl pkey -in tools/keys/installer-key.pem -pubout -out tools/keys/installer-public.pem"
  echo "然后把 installer-public.pem 的公钥内容写入 apk/astrbot-installer-bootstrap.sh"
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/astrbot-installer"

cp astrbot-startup.sh "$OUT/astrbot-installer/astrbot-startup.sh"
chmod 755 "$OUT/astrbot-installer/astrbot-startup.sh"

ARTIFACT="astrbot-installer-v${VER}.tar.gz"
tar -czf "$OUT/$ARTIFACT" -C "$OUT" astrbot-installer

SHA=$(sha256sum "$OUT/$ARTIFACT" | awk '{print $1}')

cat > "$OUT/manifest.json" <<EOF
{
  "format": "astrbot-android-installer-v1",
  "artifact": "$ARTIFACT",
  "sha256": "$SHA",
  "version": "$VER"
}
EOF

openssl pkeyutl -sign -rawin -inkey "$KEY" \
  -in "$OUT/manifest.json" -out "$OUT/manifest.sig"

# 自校验
openssl pkey -in "$KEY" -pubout -out /tmp/_pubcheck.pem >/dev/null 2>&1
openssl pkeyutl -verify -rawin -pubin -inkey /tmp/_pubcheck.pem \
  -in "$OUT/manifest.json" -sigfile "$OUT/manifest.sig" >/dev/null
rm -f /tmp/_pubcheck.pem

echo "OK: $OUT/$ARTIFACT"
echo "    sha256=$SHA"
echo "    manifest=$OUT/manifest.json"
echo "    signature=$OUT/manifest.sig"
