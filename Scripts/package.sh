#!/bin/bash
#
# 설치용 배포본을 만든다.
#
#   ./Scripts/package.sh              build/MacClean-<버전>.dmg 생성
#   ./Scripts/package.sh --install    만든 뒤 /Applications 에 바로 설치
#
# macOS 에서만 동작한다. 맥 앱 바이너리는 맥에서만 만들 수 있다.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MacClean"
VERSION="$(cat VERSION)"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
STAGING_DIR="${BUILD_DIR}/dmg-staging"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

if [ "$(uname)" != "Darwin" ]; then
  echo "이 스크립트는 macOS 에서만 동작합니다. (현재: $(uname))" >&2
  exit 1
fi

# ── 1. 앱 번들 만들기 ──────────────────────────────────────────────────
./Scripts/build_app.sh

# ── 2. DMG 구성 ────────────────────────────────────────────────────────
echo "▸ 디스크 이미지 만드는 중…"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

# `ditto` 를 쓰는 이유: `cp -R` 은 확장 속성과 심볼릭 링크를 온전히 옮기지 못해
# 앱 번들이 깨질 수 있다.
ditto "${APP_DIR}" "${STAGING_DIR}/${APP_NAME}.app"

# 끌어다 놓기 설치를 위한 /Applications 바로가기.
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}" >/dev/null

rm -rf "${STAGING_DIR}"

SIZE="$(du -h "${DMG_PATH}" | cut -f1 | tr -d ' ')"
echo "✓ 완성: ${DMG_PATH} (${SIZE})"

# ── 3. 선택: 바로 설치 ─────────────────────────────────────────────────
if [ "${1:-}" = "--install" ]; then
  echo "▸ /Applications 에 설치하는 중…"
  rm -rf "/Applications/${APP_NAME}.app"
  ditto "${APP_DIR}" "/Applications/${APP_NAME}.app"
  echo "✓ 설치 완료: /Applications/${APP_NAME}.app"
  echo
  echo "  ⚠️  전체 디스크 접근 권한을 **다시** 켜야 합니다."
  echo "     권한은 앱의 위치마다 따로 붙습니다. build 폴더에서 켠 권한은"
  echo "     /Applications 로 옮긴 앱에는 적용되지 않습니다."
  echo "     시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근"
  echo "     → 목록에서 예전 MacClean 을 빼고, /Applications/${APP_NAME}.app 을 추가하세요."
  open "/Applications/${APP_NAME}.app"
else
  echo
  echo "  설치: DMG 를 열고 MacClean 을 Applications 로 끌어다 놓으세요."
  echo "  또는: ./Scripts/package.sh --install"
  open "${BUILD_DIR}"
fi

echo
echo "  ※ 이 앱은 애플 개발자 인증서로 서명되지 않았습니다 (임시 서명만 되어 있습니다)."
echo "     직접 빌드한 앱이라 이 맥에서는 그냥 열립니다."
echo "     다른 맥으로 옮기면 Gatekeeper 가 막습니다. 그 맥에서 이렇게 푸세요:"
echo "       xattr -dr com.apple.quarantine /Applications/${APP_NAME}.app"
