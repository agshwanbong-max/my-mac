/*
 * 후원 링크 — GitHub Sponsors.
 *
 * ┌─────────────────────────────────────────────────────────────┐
 * │ 승인되면 아래 SPONSORS 한 줄만 채우면 됩니다.               │
 * └─────────────────────────────────────────────────────────────┘
 *
 *   1. github.com/sponsors 에서 신청
 *   2. 결제 계정(Stripe Connect)과 세금 정보를 등록
 *   3. 승인되면 https://github.com/sponsors/<내 아이디> 주소가 생깁니다
 *
 * 비워 두면 카드가 "승인 대기 중" 상태로 나옵니다 — 눌리지 않을 뿐
 * 자리는 그대로 있습니다. 앱의 "후원하기" 를 눌러서 온 사람이
 * 빈 페이지를 보고 되돌아가는 일이 없도록.
 *
 * 승인 전에 링크를 미리 걸어두지는 마세요. 그 주소는 아직 404 입니다.
 */

const SPONSORS = "";

(function () {
  const host = document.querySelector("[data-donate]");
  const note = document.querySelector("[data-donate-note]");
  if (!host) return;

  const card = document.createElement(SPONSORS ? "a" : "div");
  card.className = "card donate";

  if (SPONSORS) {
    card.href = SPONSORS;
    card.rel = "noopener";
    card.target = "_blank";
  } else {
    card.classList.add("pending");
    // 눌러도 아무 일 없는 걸 눌러보게 두면 고장 난 것처럼 읽힌다.
    card.setAttribute("aria-disabled", "true");
  }

  card.innerHTML =
    '<span class="donate-mark" aria-hidden="true">♥</span>' +
    '<span class="donate-text"><strong></strong><small></small></span>';

  card.querySelector("strong").textContent = SPONSORS
    ? "GitHub Sponsors 로 후원하기"
    : "GitHub Sponsors 승인 대기 중";
  card.querySelector("small").textContent = SPONSORS
    ? "한 번만도, 매달도 됩니다 · 금액은 자유"
    : "곧 열립니다. 그동안은 아래 방법이 더 도움이 됩니다";

  host.appendChild(card);

  if (note && !SPONSORS) {
    note.textContent =
      "지금은 후원을 받을 수 없습니다. 별표나 문제 신고 쪽이 훨씬 값집니다.";
  }
})();
