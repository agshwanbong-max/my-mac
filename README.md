# MacClean

256GB MacBook Air 를 위한 저장 공간 정리 도구.

**설계 원칙: 못 지우는 실패는 허용한다. 잘못 지우는 실패는 허용하지 않는다.**

- 기본 처리 방식은 **휴지통 이동**이다. 되돌릴 수 있다.
- `RuleCatalog` 에 명시된 경로만 후보가 된다. "오래된 파일을 찾아 지운다" 같은 휴리스틱은 없다.
- 관리자 권한(`sudo`)을 요구하지 않는다.
- 사용자 문서·사진·iCloud·자격 증명은 코드 레벨에서 차단된다.

자세한 설계는 [`docs/DESIGN.md`](docs/DESIGN.md).

---

## 먼저 알아둘 것: "시스템 데이터"가 큰 진짜 이유

macOS 의 "시스템 데이터"는 폴더가 아니라 **분류되지 않은 모든 것의 합계**다.
그리고 그 안에서 가장 다루기 까다로운 게 **로컬 스냅샷**이다.

> 스냅샷이 남아 있는 동안에는 파일을 지워도 여유 공간이 늘지 않는다.
> 지운 만큼이 그대로 "시스템 데이터"로 옮겨 갈 뿐이다.

스냅샷은 두 종류이고 **둘 다 공간을 잡는다.**

| 접두사 | 정체 | 대응 |
|---|---|---|
| `com.apple.TimeMachine.` | Time Machine 로컬 스냅샷 | macOS 가 공간이 급하면 알아서 지운다 |
| `com.apple.os.update-` | macOS 업데이트 스냅샷. Time Machine 을 안 써도 생긴다 | 업데이트를 끝내면 대개 정리된다 |

특히 이름에 `MSUPrepareUpdate` 가 들어 있으면 **받아놓고 설치하다 만 업데이트**다.
설치도 안 된 채 몇 GB 를 잡고 있는 상태이고, 가장 확실한 정리는
**시스템 설정 → 일반 → 소프트웨어 업데이트** 에서 설치를 끝내는 것이다.

직접 확인해보려면:

```bash
tmutil listlocalsnapshots /
```

이 앱은 **정리 전에 이 상황부터 진단해서 보여준다.**
스냅샷 삭제는 `sudo` 가 필요해서 앱이 직접 실행하지는 않는다.

---

## UI

macOS 26 (Tahoe) 의 **Liquid Glass** 디자인 언어를 쓴다.

- 사이드바에서 분류를 고르고, 오른쪽에서 항목을 검토하는 표준 Mac 3단 구조
- 디스크 막대를 **분류별 색으로 쪼개서** 무엇이 용량을 먹는지 한눈에
- 정리 버튼은 목록 위에 떠 있는 유리 패널 — 목록이 길어도 항상 손에 닿는다
- 기본 화면은 조용하게. "지우면 어떻게 되는지"는 항목을 펼쳤을 때만 나온다

**macOS 26 미만에서도 그대로 동작한다.** 유리 재질 대신 머티리얼로 자동 폴백한다.
macOS 26 전용 API 는 전부 [`DesignSystem.swift`](Sources/MacCleanApp/DesignSystem.swift)
한 파일에만 있다 — 문제가 생기면 그 파일만 고치면 된다.

## 빌드

Xcode 프로젝트 없이 SPM 만으로 만든다. Xcode 15 이상 (또는 Command Line Tools) 필요.

```bash
# 앱 만들기 → build/MacClean.app
./Scripts/build_app.sh

# 만들고 바로 실행
./Scripts/build_app.sh --run

# 테스트
swift test
```

만든 뒤 **시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근**에
`build/MacClean.app` 을 추가하세요. 이 권한이 없으면 iPhone 백업, 메일 첨부 임시본,
샌드박스 앱 캐시를 찾지 못합니다.

---

## CLI 로 먼저 확인하기

GUI 를 믿기 전에 같은 엔진을 터미널에서 돌려볼 수 있습니다.

```bash
swift build -c release --product maccleanctl
BIN=$(swift build -c release --show-bin-path)

$BIN/maccleanctl scan     # 검사만 (아무것도 지우지 않음)
$BIN/maccleanctl rules    # 등록된 정리 규칙 전부 출력
$BIN/maccleanctl plan     # 지울 항목 미리보기 (아무것도 지우지 않음)
$BIN/maccleanctl log      # 최근 작업 기록
```

실제로 정리하려면 명시적으로 확인해야 합니다.

```bash
$BIN/maccleanctl clean --safe --confirm    # 안전 등급만 휴지통으로
```

---

## 무엇을 정리하는가

### 안전 — 지워도 자동으로 다시 만들어짐

| 항목 | 지우면 |
|---|---|
| Xcode DerivedData | 다음 빌드 때 재생성 (첫 빌드가 느려짐) |
| iOS 복원 이미지 (.ipsw) | 필요할 때 다시 받음 |
| npm / pip / Homebrew / SPM / CocoaPods 캐시 | 다음 설치 때 다시 받음 |
| 앱 캐시 (`~/Library/Caches`) | 각 앱이 다시 만듦 |
| 브라우저 캐시 | 첫 로딩만 느려짐 · **로그아웃되지 않음** |
| 로그 · 크래시 리포트 | 영향 없음 |
| 메일 첨부 임시본 | 첨부를 다시 열면 재생성 · **메일은 그대로** |
| 사용할 수 없는 시뮬레이터 기기 | `xcrun simctl delete` 로 정상 삭제 |

### 확인 필요 — 골라서 휴지통으로

| 항목 | 주의할 점 |
|---|---|
| iPhone · iPad 백업 | ⚠️ 유일한 백업이면 복원 불가 |
| Xcode 아카이브 | ⚠️ 배포한 버전의 크래시 해석용 dSYM 이 들어 있음 |
| iOS 기기 지원 파일 | 기기를 다시 연결하면 재다운로드 |
| pnpm 저장소 | ⚠️ 기존 프로젝트의 node_modules 링크가 깨짐 |
| 오래된 node_modules (90일+) | `npm install` 로 복구 |
| 오래된 설치 파일 (.dmg/.pkg) | 휴지통에서 되돌릴 수 있음 |
| 휴지통 비우기 | ⚠️ **되돌릴 수 없음** |

### 안내 전용 — 앱이 손대지 않음

| 항목 | 왜 |
|---|---|
| Time Machine 로컬 스냅샷 | `sudo` 필요 · 명령어만 안내 |
| 시뮬레이터 런타임 | Xcode 설정에서 지우는 게 정석 |
| 대용량 파일 목록 | 사용자 파일 · 판단은 사용자 몫 |
| Quick Look 썸네일 캐시 | 시스템 임시 폴더 · 명령어만 안내 |

---

## 절대 건드리지 않는 것

`Sources/MacCleanCore/Safety/ProtectedPaths.swift` 에 하드코딩되어 있으며,
**정리 규칙이 이 목록을 덮어쓸 수 없습니다.**

- `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Movies`, `~/Music`
- `~/Library/Mobile Documents` (iCloud Drive), `~/Library/CloudStorage` (Dropbox/OneDrive/Google Drive)
- `~/Library/Keychains`, `~/.ssh`, `~/.aws`, `~/.gnupg`, 프로비저닝 프로파일
- `~/Library/Mail`, `~/Library/Messages`, `~/Library/Safari`
- `/System`, `/usr/bin`, `/Applications`, `/Volumes`
- 경로 어디에든 `.git` 이 있으면 차단
- `.photoslibrary`, `.fcpbundle`, `.app`, `.logicx` 번들 내부

---

## 정리한 뒤에

휴지통으로 옮긴 항목은 **휴지통을 비워야** 실제 여유 공간이 늘어납니다.
며칠 써보고 문제가 없을 때 비우세요.

그래도 용량이 안 늘었다면 로컬 스냅샷이 붙잡고 있는 것입니다. 위의 진단 항목을 확인하세요.

---

## 성능

검사는 몇 초 안에 끝나야 한다고 보고 만들었다.

- 스캐너들을 **동시에** 돌린다 (`withTaskGroup`). 대부분 디스크 대기 시간이라 병렬화 효과가 크다
- 홈 전체를 훑는 대용량 파일 검사는 **기본으로 꺼져 있다.** 도구 막대에서 켤 수 있다
- 검사 중 언제든 중단할 수 있다
- 디렉터리 순회는 40만 노드에서 끊고 "일부만 셌음"으로 표시한다

## 상태

코어 엔진 · CLI · SwiftUI 앱 · 테스트가 모두 작성되어 있습니다.
**아직 macOS 에서 컴파일·실행 검증은 되지 않았습니다** (개발 환경에 Swift 툴체인이 없었음).
`swift test` 로 안전 계층 테스트부터 돌려보고, `maccleanctl scan` 으로 검사만 해본 뒤
`maccleanctl plan` 으로 미리보기를 확인하고 나서 실제 정리를 실행하는 순서를 권합니다.
