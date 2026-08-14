/*
 * 광고 삽입.
 *
 * 켜는 법: 아래 CLIENT 에 애드센스 게시자 ID 를, SLOTS 에 광고 단위 ID 를 넣는다.
 * 비어 있으면 애드센스 스크립트를 아예 불러오지 않고 광고 자리도 숨긴다.
 * (설정 전에는 페이지에 외부 요청이 하나도 나가지 않는다.)
 *
 *   CLIENT = "ca-pub-0000000000000000"
 *   SLOTS  = { top: "1234567890", inline: "0987654321" }
 *
 * 광고 단위는 애드센스 → 광고 → 광고 단위 기준 → 디스플레이 광고 에서 만든다.
 * 만들면 코드 조각에 data-ad-client 와 data-ad-slot 이 보인다. 그 두 값이다.
 */

const CLIENT = "";
const SLOTS = { top: "", inline: "" };

(function () {
  if (!CLIENT) return;

  const boxes = Array.from(document.querySelectorAll(".ad[data-slot]")).filter(
    (box) => SLOTS[box.dataset.slot]
  );
  if (boxes.length === 0) return;

  const script = document.createElement("script");
  script.async = true;
  script.crossOrigin = "anonymous";
  script.src =
    "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=" +
    encodeURIComponent(CLIENT);
  document.head.appendChild(script);

  for (const box of boxes) {
    const ins = document.createElement("ins");
    ins.className = "adsbygoogle";
    ins.style.display = "block";
    ins.dataset.adClient = CLIENT;
    ins.dataset.adSlot = SLOTS[box.dataset.slot];
    ins.dataset.adFormat = "auto";
    ins.dataset.fullWidthResponsive = "true";

    const label = document.createElement("div");
    label.className = "ad-label";
    label.textContent = "광고";

    box.append(label, ins);
    box.classList.add("on");

    (window.adsbygoogle = window.adsbygoogle || []).push({});
  }
})();
