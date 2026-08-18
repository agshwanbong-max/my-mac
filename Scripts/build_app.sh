#!/bin/bash
#
# Chaff.app 번들을 만든다. Xcode 프로젝트 없이 SPM 만으로 동작한다.
#
#   ./Scripts/build_app.sh            릴리즈 빌드 후 ./build/Chaff.app 생성
#   ./Scripts/build_app.sh --run      만들고 바로 실행
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Chaff"
BUNDLE_ID="${CHAFF_BUNDLE_ID:-local.chaff.app}"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
VERSION="$(cat VERSION)"

# 배포용 서명은 release.sh 가 따로 한다.
# 여기서 임시 서명을 해두면 그쪽에서 다시 벗겨내야 하므로, 건너뛸 수 있게 한다.
SKIP_ADHOC_SIGN="${SKIP_ADHOC_SIGN:-0}"

echo "▸ 빌드 중…"
swift build -c release --product "${APP_NAME}"

BINARY="$(swift build -c release --product "${APP_NAME}" --show-bin-path)/${APP_NAME}"
if [ ! -f "${BINARY}" ]; then
  echo "빌드 결과물을 찾지 못했습니다: ${BINARY}" >&2
  exit 1
fi

echo "▸ 앱 번들 구성 중…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BINARY}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# 번역 파일. SPM 은 리소스를 `Chaff_ChaffCore.bundle` 로 묶어 빌드 폴더에 둔다.
# 이걸 Contents/Resources 에 넣어야 `Bundle.module` 이 찾는다.
# 빠뜨리면 앱이 조용히 키 이름("verdict.safe")을 화면에 찍는다.
BIN_PATH="$(swift build -c release --product "${APP_NAME}" --show-bin-path)"
BUNDLE_COUNT=0
for RESOURCE_BUNDLE in "${BIN_PATH}"/*.bundle; do
  [ -e "${RESOURCE_BUNDLE}" ] || continue
  cp -R "${RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/"
  BUNDLE_COUNT=$((BUNDLE_COUNT + 1))
done
if [ "${BUNDLE_COUNT}" -eq 0 ]; then
  echo "리소스 번들을 찾지 못했습니다. 번역이 빠진 앱이 만들어집니다." >&2
  exit 1
fi

ICON_SOURCE="Sources/ChaffApp/Resources/AppIcon.icns"
if [ -f "${ICON_SOURCE}" ]; then
  cp "${ICON_SOURCE}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
else
  echo "  (아이콘이 없습니다. python3 Scripts/make_icon.py 로 만들 수 있습니다.)"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- 이걸 안 적으면 macOS 는 앱을 한국어 전용으로 보고, 영어 사용자에게도
         메뉴와 창을 한국어로 띄운다. 번역 파일이 있어도 소용없다. -->
    <key>CFBundleDevelopmentRegion</key>
    <string>ko</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>ko</string>
        <string>en</string>
        <string>ja</string>
        <string>zh-Hans</string>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- 샌드박스를 쓰지 않는다. 샌드박스 안에서는 ~/Library 를 읽을 수 없어
         이 앱이 하려는 일 자체가 불가능하다. -->
</dict>
</plist>
PLIST

if [ "${SKIP_ADHOC_SIGN}" != "1" ]; then
  echo "▸ 임시 서명 중…"
  codesign --force --sign - "${APP_DIR}" 2>/dev/null || {
    echo "  (서명 실패 — 서명 없이 진행합니다. 첫 실행 시 Gatekeeper 경고가 뜰 수 있습니다.)"
  }
fi

# 파인더는 아이콘을 공격적으로 캐시한다. 번들 수정 시각을 건드려 다시 읽게 만든다.
touch "${APP_DIR}"

echo "✓ 완료: ${APP_DIR}"
echo
echo "  전체 디스크 접근 권한을 켜야 iPhone 백업 · 메일 첨부 · 샌드박스 앱 캐시까지 검사합니다:"
echo "  시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 → ${APP_DIR} 추가"

if [ "${1:-}" = "--run" ]; then
  open "${APP_DIR}"
fi
