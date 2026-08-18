#!/bin/bash
#
# 서명 · 공증 · 스테이플까지 끝낸 배포본을 만든다.
#
#   ./Scripts/release.sh
#
# 결과: build/MacClean-<버전>.dmg — 다른 맥에 그냥 옮겨도 경고 없이 열린다.
#
# ── 한 번만 해두면 되는 준비 ─────────────────────────────────────────────
#
# 1) Developer ID Application 인증서가 키체인에 있어야 한다.
#    Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application
#    확인:  security find-identity -v -p codesigning
#
# 2) 공증 자격증명을 키체인에 저장해 둔다. 이건 딱 한 번만 하면 된다.
#
#    xcrun notarytool store-credentials "MacClean" \
#      --apple-id "<애플 ID>" \
#      --team-id "<10자리 팀 ID>" \
#      --password "<앱 암호>"
#
#    앱 암호는 계정 비밀번호가 아니다. appleid.apple.com → 로그인 및 보안 →
#    앱 암호 에서 새로 만든다.
#    팀 ID 는 developer.apple.com → Membership 에서 볼 수 있다.
#
#    이 스크립트는 비밀번호를 묻지도, 파일에 적지도 않는다. 키체인에 맡긴다.
#
# ── 환경 변수로 바꿀 수 있는 것 ──────────────────────────────────────────
#   NOTARY_PROFILE   공증 자격증명 이름 (기본: MacClean)
#   SIGN_IDENTITY    서명 인증서 (기본: 키체인에서 Developer ID Application 자동 탐색)
#   MACCLEAN_BUNDLE_ID  번들 ID (기본: local.macclean.app)
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MacClean"
VERSION="$(cat VERSION)"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
ZIP_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
STAGING_DIR="${BUILD_DIR}/dmg-staging"
NOTARY_PROFILE="${NOTARY_PROFILE:-MacClean}"

fail() { echo "✗ $1" >&2; exit 1; }

# ── 0. 미리 확인 ───────────────────────────────────────────────────────
# 20분짜리 빌드와 공증을 돌린 뒤에 "인증서가 없다" 를 알게 되면 안 된다.
echo "▸ 준비 상태 확인 중…"

[ "$(uname)" = "Darwin" ] || fail "macOS 에서만 동작합니다. (현재: $(uname))"
command -v xcrun >/dev/null || fail "Xcode Command Line Tools 가 필요합니다: xcode-select --install"
xcrun notarytool --version >/dev/null 2>&1 || fail "notarytool 을 쓸 수 없습니다. Xcode 13 이상이 필요합니다."

if [ -z "${SIGN_IDENTITY:-}" ]; then
  # 키체인에서 Developer ID Application 인증서를 찾는다.
  SIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" \
    | head -1 \
    | sed -E 's/.*"(.+)".*/\1/')"
fi

if [ -z "${SIGN_IDENTITY}" ]; then
  echo "✗ Developer ID Application 인증서를 찾지 못했습니다." >&2
  echo "" >&2
  echo "  Xcode → Settings → Accounts → Manage Certificates → + →" >&2
  echo "  Developer ID Application 을 만들어 주세요." >&2
  echo "" >&2
  echo "  현재 키체인에 있는 서명 인증서:" >&2
  security find-identity -v -p codesigning >&2 || true
  exit 1
fi
echo "  인증서: ${SIGN_IDENTITY}"

# 저장된 공증 자격증명이 실제로 통하는지 지금 확인한다.
if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
  echo "✗ 공증 자격증명 '${NOTARY_PROFILE}' 을 쓸 수 없습니다." >&2
  echo "" >&2
  echo "  한 번만 저장해 두면 됩니다:" >&2
  echo "" >&2
  echo "    xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\" >&2
  echo "      --apple-id \"<애플 ID>\" \\" >&2
  echo "      --team-id \"<10자리 팀 ID>\" \\" >&2
  echo "      --password \"<앱 암호>\"" >&2
  echo "" >&2
  echo "  앱 암호는 계정 비밀번호가 아닙니다." >&2
  echo "  appleid.apple.com → 로그인 및 보안 → 앱 암호 에서 만드세요." >&2
  exit 1
fi
echo "  공증 자격증명: ${NOTARY_PROFILE}"

# ── 1. 빌드 ────────────────────────────────────────────────────────────
# 임시 서명은 건너뛴다. 어차피 아래에서 제대로 다시 서명한다.
SKIP_ADHOC_SIGN=1 ./Scripts/build_app.sh

# ── 2. 서명 ────────────────────────────────────────────────────────────
# 공증을 받으려면 두 가지가 필수다.
#   --options runtime  강화된 런타임. 이게 없으면 공증이 거부된다.
#   --timestamp        보안 타임스탬프. 인증서가 만료돼도 서명이 유효하게 남는다.
#
# `--deep` 은 쓰지 않는다. 애플이 권장하지 않고, 중첩된 코드를 잘못 서명하는 원인이 된다.
# 이 번들에는 실행 파일이 하나뿐이라 그냥 번들만 서명하면 된다.
echo "▸ 서명 중…"
codesign --force \
  --sign "${SIGN_IDENTITY}" \
  --options runtime \
  --timestamp \
  "${APP_DIR}"

echo "▸ 서명 확인 중…"
codesign --verify --strict --verbose=2 "${APP_DIR}"

# ── 3. 앱 공증 ─────────────────────────────────────────────────────────
# 앱 자체를 먼저 공증하고 스테이플한다.
# DMG 만 공증하면, 사용자가 앱을 꺼낸 뒤에는 Gatekeeper 가 매번 온라인 확인을 한다.
# 앱에 직접 스테이플해 두면 네트워크가 없어도 바로 열린다.
echo "▸ 앱 공증 중… (애플 서버 응답까지 몇 분 걸립니다)"
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"

xcrun notarytool submit "${ZIP_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

echo "▸ 앱에 스테이플 중…"
xcrun stapler staple "${APP_DIR}"
rm -f "${ZIP_PATH}"

# ── 4. DMG 만들고 공증 ─────────────────────────────────────────────────
echo "▸ 디스크 이미지 만드는 중…"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"
ditto "${APP_DIR}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}" >/dev/null
rm -rf "${STAGING_DIR}"

codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${DMG_PATH}"

echo "▸ 디스크 이미지 공증 중…"
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

echo "▸ 디스크 이미지에 스테이플 중…"
xcrun stapler staple "${DMG_PATH}"

# ── 5. 최종 확인 ───────────────────────────────────────────────────────
# 다른 맥에서 열릴지를 여기서 미리 확인한다.
echo "▸ 최종 확인…"
spctl --assess --type execute --verbose=2 "${APP_DIR}"
xcrun stapler validate "${APP_DIR}"
xcrun stapler validate "${DMG_PATH}"

SIZE="$(du -h "${DMG_PATH}" | cut -f1 | tr -d ' ')"
echo
echo "✓ 공증 완료: ${DMG_PATH} (${SIZE})"
echo
echo "  다른 맥에 그대로 옮겨도 경고 없이 열립니다."
echo "  xattr 로 quarantine 을 풀 필요도 없습니다."
echo
echo "  설치: ./Scripts/package.sh --install"
echo "  또는 DMG 를 열고 MacClean 을 Applications 로 끌어다 놓으세요."
