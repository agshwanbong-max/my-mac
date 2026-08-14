/*
 * 최신 배포본 정보를 채운다.
 *
 * appcast.json 은 앱이 새 버전을 확인할 때 쓰는 것과 **같은 파일**이다.
 * (`releases/latest/download/appcast.json` — 항상 최신 릴리스를 가리킨다.)
 * 이 페이지도 같은 걸 읽으므로, 릴리스를 하나 올리면 앱과 웹이 같이 갱신된다.
 * 페이지를 손댈 일이 없다.
 *
 * 못 읽어도 화면은 그대로 동작한다 — 단추의 기본 링크가 릴리스 목록이라
 * 받는 데는 지장이 없고, 버전 표시만 비워둔다.
 */

const MANIFEST =
  "https://github.com/agshwanbong-max/my-mac/releases/latest/download/appcast.json";

(async function () {
  const button = document.querySelector("[data-download]");
  const meta = document.querySelector("[data-release-meta]");
  if (!button) return;

  try {
    const response = await fetch(MANIFEST, { cache: "no-store" });
    if (!response.ok) throw new Error(String(response.status));

    const manifest = await response.json();
    if (!manifest.downloadURL || !manifest.version) throw new Error("모양이 다릅니다");

    button.href = manifest.downloadURL;

    if (meta) {
      const parts = [`버전 ${manifest.version}`];
      if (manifest.publishedAt) {
        const date = new Date(manifest.publishedAt);
        if (!Number.isNaN(date.getTime())) {
          parts.push(
            date.toLocaleDateString("ko-KR", {
              year: "numeric",
              month: "long",
              day: "numeric",
            })
          );
        }
      }
      if (manifest.minimumSystemVersion) {
        parts.push(`macOS ${manifest.minimumSystemVersion} 이상`);
      }
      meta.textContent = parts.join(" · ");
    }
  } catch (error) {
    // 아직 릴리스가 없거나 네트워크가 막힌 경우. 기본 링크로 둔다.
    if (meta) meta.textContent = "macOS 13 이상 · Apple 공증 완료";
  }
})();
