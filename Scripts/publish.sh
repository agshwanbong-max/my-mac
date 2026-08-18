#!/bin/bash
#
# 공증까지 끝난 배포본을 GitHub Release 로 올린다.
#
#   ./Scripts/publish.sh
#
# 미리 `./Scripts/release.sh` 로 서명·공증을 끝내 두어야 한다.
#
# 함께 올리는 것
#   Chaff-<버전>.dmg      배포본
#   Chaff-<버전>.dmg.sha256   내려받은 파일이 온전한지 확인용
#   appcast.json             앱이 새 버전을 확인하는 안내문
#
# `appcast.json` 은 latest/download 경로로 항상 최신 릴리스에서 서빙되므로,
# 앱이 보는 주소는 한 번 정하면 바뀌지 않는다.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Chaff"
VERSION="$(cat VERSION)"
TAG="v${VERSION}"
BUILD_DIR="build"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"
MANIFEST_PATH="${BUILD_DIR}/appcast.json"
REPO="agshwanbong-max/my-mac"

fail() { echo "✗ $1" >&2; exit 1; }

# ── 준비 확인 ──────────────────────────────────────────────────────────
[ -f "${DMG_PATH}" ] || fail "배포본이 없습니다: ${DMG_PATH}
  먼저 ./Scripts/release.sh 로 서명·공증을 끝내세요."

command -v gh >/dev/null || fail "GitHub CLI 가 필요합니다: brew install gh
  설치 후 gh auth login 으로 로그인하세요."

gh auth status >/dev/null 2>&1 || fail "GitHub 에 로그인되어 있지 않습니다: gh auth login"

# 공증이 실제로 붙어 있는지 확인한다. 공증 안 된 걸 올리면
# 받는 사람 맥에서 열리지 않는다.
if command -v xcrun >/dev/null; then
  xcrun stapler validate "${DMG_PATH}" >/dev/null 2>&1 \
    || fail "이 DMG 에는 공증 티켓이 붙어 있지 않습니다. ./Scripts/release.sh 를 먼저 돌리세요."
fi

if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  fail "${TAG} 릴리스가 이미 있습니다.
  새 버전을 내려면 VERSION 파일을 올리고 release.sh 부터 다시 돌리세요."
fi

# ── 체크섬 ─────────────────────────────────────────────────────────────
echo "▸ 체크섬 계산 중…"
shasum -a 256 "${DMG_PATH}" | awk '{print $1}' > "${CHECKSUM_PATH}"
CHECKSUM="$(cat "${CHECKSUM_PATH}")"

# ── 업데이트 안내문 ────────────────────────────────────────────────────
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}.dmg"
NOTES_URL="https://github.com/${REPO}/releases/tag/${TAG}"
PUBLISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "${MANIFEST_PATH}" <<JSON
{
  "version": "${VERSION}",
  "downloadURL": "${DOWNLOAD_URL}",
  "releaseNotesURL": "${NOTES_URL}",
  "minimumSystemVersion": "13.0",
  "publishedAt": "${PUBLISHED_AT}"
}
JSON

# ── 릴리스 노트 ────────────────────────────────────────────────────────
PREVIOUS_TAG="$(gh release view --repo "${REPO}" --json tagName --jq .tagName 2>/dev/null || echo "")"
if [ -n "${PREVIOUS_TAG}" ] && git rev-parse "${PREVIOUS_TAG}" >/dev/null 2>&1; then
  CHANGES="$(git log --pretty=format:'- %s' "${PREVIOUS_TAG}..HEAD")"
else
  CHANGES="$(git log --pretty=format:'- %s' -20)"
fi

NOTES_FILE="${BUILD_DIR}/release-notes.md"
cat > "${NOTES_FILE}" <<NOTES
## 설치

\`${APP_NAME}-${VERSION}.dmg\` 를 받아서 열고, Chaff 를 Applications 로 끌어다 놓으세요.

Apple Developer ID 로 서명하고 공증까지 마쳤습니다. 경고 없이 열립니다.

설치한 뒤 **시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근** 에
Chaff 를 추가해 주세요. 이 권한이 없으면 \`~/Library\` 의 상당 부분이
빈 폴더처럼 보여서 앱이 절반만 찾습니다.

## 변경 사항

${CHANGES}

## 파일 확인

\`\`\`
shasum -a 256 ${APP_NAME}-${VERSION}.dmg
# ${CHECKSUM}
\`\`\`
NOTES

# ── 올리기 ─────────────────────────────────────────────────────────────
echo "▸ ${TAG} 릴리스 만드는 중…"
gh release create "${TAG}" \
  --repo "${REPO}" \
  --title "${APP_NAME} ${VERSION}" \
  --notes-file "${NOTES_FILE}" \
  "${DMG_PATH}" \
  "${CHECKSUM_PATH}" \
  "${MANIFEST_PATH}"

echo
echo "✓ 배포 완료"
echo "  릴리스   ${NOTES_URL}"
echo "  내려받기 ${DOWNLOAD_URL}"
echo
echo "  앱이 새 버전을 확인하는 주소 (항상 최신 릴리스를 가리킵니다):"
echo "  https://github.com/${REPO}/releases/latest/download/appcast.json"
