#!/usr/bin/env python3
"""앱 아이콘을 만든다.

맥 없이도 `.icns` 를 만들 수 있게 직접 조립한다.
(`iconutil` 은 macOS 전용이라 개발 환경에 따라 못 쓰는 경우가 있다.)

디자인 의도
-----------
이 앱의 정체성은 "용량이 어디에 있는지 보여주고, 되찾을 몫을 알려준다" 다.
그래서 화면에서 쓰는 시각 언어를 그대로 아이콘으로 옮겼다 — **분절된 고리 게이지**.
회색 호는 그냥 쓰는 중인 공간, 밝은 민트 호는 오늘 되찾을 수 있는 몫이다.

빗자루나 휴지통은 정리 앱의 상투적 표현이라 피했다.
게이지는 32px 에서도 형태가 뭉개지지 않고, macOS 저장 공간 설정과 같은 계열로 읽힌다.

    python3 Scripts/make_icon.py
"""

from __future__ import annotations

import math
import pathlib
import struct
import zlib

from PIL import Image, ImageDraw, ImageFilter

# 고해상도로 그린 뒤 줄인다. 곡선과 호의 가장자리를 부드럽게 만드는 가장 간단한 방법.
MASTER = 4096
SUPERSAMPLE = MASTER // 1024

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT_ICNS = ROOT / "Sources/MacCleanApp/Resources/AppIcon.icns"
OUTPUT_PNG = ROOT / "Sources/MacCleanApp/Resources/AppIcon-1024.png"


def superellipse(cx: float, cy: float, half: float, exponent: float = 5.0, steps: int = 720):
    """macOS 아이콘의 모서리 모양.

    단순한 둥근 사각형이 아니라 초타원(squircle)이다. 곡률이 끊기지 않고 이어져서
    애플 아이콘 특유의 부드러운 실루엣이 나온다.
    """
    points = []
    for index in range(steps):
        theta = 2 * math.pi * index / steps
        cos_t, sin_t = math.cos(theta), math.sin(theta)
        x = half * math.copysign(abs(cos_t) ** (2 / exponent), cos_t)
        y = half * math.copysign(abs(sin_t) ** (2 / exponent), sin_t)
        points.append((cx + x, cy + y))
    return points


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    """위에서 아래로 흐르는 그라디언트. 한 픽셀 폭으로 만들고 늘린다."""
    strip = Image.new("RGB", (1, size))
    for y in range(size):
        ratio = y / max(size - 1, 1)
        # 살짝 이징을 준다. 선형 그라디언트는 가운데가 탁해 보인다.
        eased = ratio * ratio * (3 - 2 * ratio)
        strip.putpixel((0, y), tuple(
            round(top[i] + (bottom[i] - top[i]) * eased) for i in range(3)
        ))
    return strip.resize((size, size), Image.Resampling.BILINEAR)


def render_master() -> Image.Image:
    size = MASTER
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # ── 바탕 ──────────────────────────────────────────────────────────
    # 애플 아이콘 격자: 1024 캔버스에서 실제 도형은 824. 나머지는 여백과 그림자 몫이다.
    body = round(size * 824 / 1024)
    half = body / 2
    center = size / 2

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon(superellipse(center, center, half), fill=255)

    gradient = vertical_gradient(size, (46, 82, 168), (26, 188, 196)).convert("RGBA")
    canvas.paste(gradient, (0, 0), mask)

    # 위쪽 가장자리에 옅은 빛. 평평한 색면에 깊이를 준다.
    gloss = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse(
        [center - half * 1.1, center - half * 1.9, center + half * 1.1, center + half * 0.15],
        fill=(255, 255, 255, 38),
    )
    gloss = gloss.filter(ImageFilter.GaussianBlur(size * 0.05))
    canvas = Image.alpha_composite(canvas, Image.composite(gloss, Image.new("RGBA", (size, size)), mask))

    # ── 고리 게이지 ───────────────────────────────────────────────────
    draw = ImageDraw.Draw(canvas)
    radius = size * 0.245
    stroke = round(size * 0.105)
    box = [center - radius, center - radius, center + radius, center + radius]

    # 트랙: 전체 용량.
    draw.arc(box, 0, 360, fill=(255, 255, 255, 58), width=stroke)

    # 쓰는 중인 공간. 위(-90°)에서 시계 방향으로.
    draw.arc(box, -90, 158, fill=(255, 255, 255, 242), width=stroke)

    # 되찾을 수 있는 몫. 이 아이콘이 말하려는 게 이 조각이다.
    draw.arc(box, 172, 262, fill=(94, 234, 212, 255), width=stroke)

    # ── 가운데 반짝임 ─────────────────────────────────────────────────
    # 네 갈래 별. 작은 크기에서는 점 하나로 뭉개지지만 그래도 중심을 잡아준다.
    spark = size * 0.072
    waist = spark * 0.26
    draw.polygon(
        [
            (center, center - spark),
            (center + waist, center - waist),
            (center + spark, center),
            (center + waist, center + waist),
            (center, center + spark),
            (center - waist, center + waist),
            (center - spark, center),
            (center - waist, center - waist),
        ],
        fill=(255, 255, 255, 235),
    )

    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


def png_bytes(image: Image.Image, size: int) -> bytes:
    from io import BytesIO

    buffer = BytesIO()
    image.resize((size, size), Image.Resampling.LANCZOS).save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


# icns 안에서 각 크기가 갖는 이름표.
# 같은 픽셀 크기가 두 번 나오는 건 정상이다 — 일반 화면용과 레티나용이 따로 있다.
ICNS_ENTRIES = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
    ("ic11", 32),
    ("ic12", 64),
    ("ic13", 256),
    ("ic14", 512),
]


def build_icns(master: Image.Image) -> bytes:
    chunks = b""
    for kind, size in ICNS_ENTRIES:
        data = png_bytes(master, size)
        chunks += kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    return b"icns" + struct.pack(">I", len(chunks) + 8) + chunks


def main() -> None:
    OUTPUT_ICNS.parent.mkdir(parents=True, exist_ok=True)

    master = render_master()
    master.save(OUTPUT_PNG, format="PNG", optimize=True)
    OUTPUT_ICNS.write_bytes(build_icns(master))

    print(f"✓ {OUTPUT_ICNS.relative_to(ROOT)} ({OUTPUT_ICNS.stat().st_size // 1024}KB)")
    print(f"✓ {OUTPUT_PNG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
