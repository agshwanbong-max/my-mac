/*
 * 후원 링크 — GitHub Sponsors.
 *
 * ┌─────────────────────────────────────────────────────────────┐
 * │ 아래 SPONSORS 한 줄만 채우면 됩니다.                        │
 * └─────────────────────────────────────────────────────────────┘
 *
 *   1. github.com/sponsors 에서 "Join the waitlist / Set up GitHub Sponsors"
 *   2. 결제 계정(Stripe Connect)과 세금 정보를 등록
 *   3. 승인되면 https://github.com/sponsors/<내 아이디> 주소가 생깁니다
 *
 * 비워 두면 후원 칸이 아예 나오지 않고 "준비 중" 안내만 남습니다.
 * (승인 전에 링크를 걸어두면 방문자가 404 를 보게 되므로 그대로 두세요.)
 */

const SPONSORS = "";

(function () {
  const host = document.querySelector("[data-donate]");
  const empty = document.querySelector("[data-donate-empty]");
  const note = document.querySelector("[data-donate-note]");
  if (!host) return;

  if (!SPONSORS) {
    host.remove();
    if (note) note.remove();
    return;
  }
  if (empty) empty.remove();

  const link = document.createElement("a");
  link.className = "card donate";
  link.href = SPONSORS;
  link.rel = "noopener";
  link.target = "_blank";
  link.innerHTML =
    '<span class="donate-mark" aria-hidden="true">♥</span>' +
    "<span class=\"donate-text\"><strong>GitHub Sponsors 로 후원하기</strong>" +
    "<small>한 번만도, 매달도 됩니다 · 금액은 자유</small></span>";
  host.appendChild(link);
})();
