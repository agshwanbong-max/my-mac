/*
 * 최신 배포본 정보를 채운다.
 *
 * **왜 appcast.json 을 안 읽는가**
 * 앱은 `releases/latest/download/appcast.json` 을 읽는다. 그런데 그 주소는
 * 브라우저에서 쓸 수 없다 — GitHub 이 302 리다이렉트를 **CORS 헤더 없이**
 * 돌려주기 때문에, 브라우저는 리다이렉트를 따라가기도 전에 요청을 막는다.
 * (앱의 URLSession 에는 CORS 제약이 없어서 같은 주소가 잘 동작한다.)
 *
 * `api.github.com` 은 `Access-Control-Allow-Origin: *` 를 보낸다. 그래서
 * 페이지는 API 를, 앱은 appcast.json 을 본다. 둘 다 같은 릴리스를 가리킨다.
 *
 * 못 읽어도 화면은 그대로 동작한다 — 단추의 기본 링크가 릴리스 목록이라
 * 받는 데는 지장이 없고, 버전 표시만 비워둔다.
 */

const LATEST_RELEASE =
  "https://api.github.com/repos/agshwanbong-max/my-mac/releases/latest";

(async function () {
  const button = document.querySelector("[data-download]");
  const meta = document.querySelector("[data-release-meta]");
  if (!button) return;

  try {
    const response = await fetch(LATEST_RELEASE, {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!response.ok) throw new Error(String(response.status));

    const release = await response.json();
    const dmg = (release.assets || []).find((asset) =>
      asset.name.toLowerCase().endsWith(".dmg")
    );
    if (!dmg) throw new Error("DMG 가 릴리스에 없습니다");

    button.href = dmg.browser_download_url;

    if (meta) {
      const version = (release.tag_name || "").replace(/^v/, "");
      const parts = [];
      if (version) parts.push(`버전 ${version}`);

      const date = new Date(release.published_at);
      if (!Number.isNaN(date.getTime())) {
        parts.push(
          date.toLocaleDateString("ko-KR", {
            year: "numeric",
            month: "long",
            day: "numeric",
          })
        );
      }
      parts.push("macOS 13 이상");
      meta.textContent = parts.join(" · ");
    }
  } catch (error) {
    // 아직 릴리스가 없거나, 네트워크가 막혔거나, API 한도에 걸린 경우.
    // 기본 링크(릴리스 목록)로 두면 받는 데는 문제가 없다.
    if (meta) meta.textContent = "macOS 13 이상 · Apple 공증 완료";
  }
})();
