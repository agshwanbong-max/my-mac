import Foundation
import MacCleanCore

// 코어 로직을 GUI 없이 그대로 돌려보는 CLI.
// GUI 를 신뢰하기 전에 여기서 먼저 확인하는 용도다.
//
//   maccleanctl scan                    검사만 하고 표로 보여준다
//   maccleanctl plan                    지울 항목을 골라 미리보기(dry run)
//   maccleanctl clean --safe --confirm  안전 등급만 실제로 정리
//   maccleanctl rules                   등록된 규칙 전부 출력
//   maccleanctl log                     최근 작업 기록

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "scan"
let flags = Set(arguments.dropFirst())

let paths = UserPaths.current()
let hasFullDiskAccess = FullDiskAccessProbe.hasAccess(paths: paths)

func line(_ character: String = "─", _ count: Int = 72) {
    print(String(repeating: character, count: count))
}

func runScan(deepScan: Bool, findDuplicates: Bool = false) async -> ScanReport {
    let context = ScanContext(paths: paths, hasFullDiskAccess: hasFullDiskAccess)
    let coordinator = ScanCoordinator.standard(
        paths: paths, deepScan: deepScan, findDuplicates: findDuplicates
    )
    if deepScan {
        print("정밀 분석 중입니다. 홈 전체를 훑으므로 수십 초 걸릴 수 있습니다…")
    }
    if findDuplicates {
        print("중복 파일도 찾습니다. 파일을 해시하므로 더 오래 걸립니다…")
    }
    if deepScan || findDuplicates { print("") }
    return await coordinator.run(context: context)
}

func printReport(_ report: ScanReport) {
    line("━")
    print("디스크: 전체 \(ByteFormat.string(report.volume.totalCapacity))"
        + " · 여유 \(ByteFormat.string(report.volume.availableCapacity))"
        + " · 로컬 스냅샷 \(report.volume.localSnapshotCount)개")
    print("검사 시간 \(String(format: "%.1f", report.duration))초 · 후보 \(report.findings.count)건")
    print("정리 가능 합계: \(ByteFormat.string(report.totalReclaimable))")
    line("━")

    for category in report.categoriesInOrder {
        let items = report.findings(in: category)
        let subtotal = items.filter { $0.isSelectable }.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        print("\n■ \(category.localizedTitle)  (\(items.count)건, \(ByteFormat.stringOrDash(subtotal)))")
        line()

        for finding in items.prefix(15) {
            let marker: String
            switch finding.risk {
            case .safe: marker = "[안전]"
            case .review: marker = "[확인]"
            case .advisory: marker = "[안내]"
            }
            let size = ByteFormat.stringOrDash(finding.reclaimableBytes)
            print("\(marker) \(size.padded(to: 10)) \(finding.title)")
            print("        \(finding.detail.replacingOccurrences(of: "\n", with: "\n        "))")
            if let command = finding.suggestedCommand {
                print("        $ \(command.replacingOccurrences(of: "\n", with: "\n        $ "))")
            }
        }
        if items.count > 15 {
            print("        … 외 \(items.count - 15)건")
        }
    }

    if !report.warnings.isEmpty {
        print("\n⚠ 경고")
        line()
        for warning in report.warnings {
            print("  · \(warning.message)")
        }
    }
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}

switch command {
case "scan":
    if !hasFullDiskAccess {
        print("⚠ 전체 디스크 접근 권한이 없습니다. 일부 항목을 찾지 못합니다.\n\(FullDiskAccessProbe.terminalInstructions)\n")
    }
    printReport(await runScan(
        deepScan: flags.contains("--deep") || flags.contains("--large-files"),
        findDuplicates: flags.contains("--duplicates")
    ))

case "rules":
    let rules = RuleCatalog.all(paths: paths)
    print("등록된 규칙 \(rules.count)개\n")
    for rule in rules.sorted(by: { $0.category.sortOrder < $1.category.sortOrder }) {
        print("[\(rule.risk.localizedTitle)] \(rule.id)")
        print("    경로: \(rule.path)  (\(rule.mode.rawValue), \(rule.removal.localizedTitle))")
        print("    조건: \(rule.minimumAgeDays)일 이상 · \(ByteFormat.string(rule.minimumBytes)) 이상")
        print("    결과: \(rule.consequence.replacingOccurrences(of: "\n", with: " "))")
        print()
    }

case "plan", "clean":
    let report = await runScan(deepScan: false)
    let wantsSafeOnly = flags.contains("--safe")
    let confirmed = flags.contains("--confirm")

    var selected = report.findings.filter { $0.isSelectable }
    if wantsSafeOnly {
        selected = selected.filter { $0.risk == .safe }
    }
    // 완전 삭제(휴지통 비우기)는 CLI 에서 명시적으로 요청해야만 포함된다.
    if !flags.contains("--include-permanent") {
        selected = selected.filter { $0.removal != .permanentDelete }
    }

    let dryRun = (command == "plan") || !confirmed
    if dryRun {
        print("※ 미리보기 모드입니다. 실제로 지우려면: maccleanctl clean --confirm\n")
    }

    let executor = CleanupExecutor(paths: paths, dryRun: dryRun)
    let outcomes = executor.execute(selected) { current, total in
        FileHandle.standardError.write("\r\(current)/\(total)".data(using: .utf8) ?? Data())
    }
    FileHandle.standardError.write("\r".data(using: .utf8) ?? Data())

    var reclaimed: Int64 = 0
    for outcome in outcomes {
        print("\(outcome.status.localizedTitle.padded(to: 12)) \(outcome.finding.title) — \(outcome.message)")
        if outcome.status == .removed || outcome.status == .deleted || outcome.status == .simulated {
            reclaimed += outcome.bytes
        }
    }
    line("━")
    print(dryRun
        ? "확보 예상: \(ByteFormat.string(reclaimed))"
        : "확보: \(ByteFormat.string(reclaimed)) — 휴지통으로 옮긴 항목은 휴지통을 비워야 실제 용량이 늘어납니다.")

case "inspect":
    let targets = arguments.dropFirst().filter { !$0.hasPrefix("--") }
    if targets.isEmpty {
        print("경로를 지정하세요. 예: maccleanctl inspect ~/Downloads/something.dmg")
    }
    let assessor = ImportanceAssessor(paths: paths)
    for target in targets {
        let expanded = (target as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("찾을 수 없습니다: \(url.path)\n")
            continue
        }

        let assessment = assessor.assess(url)
        let mark: String
        switch assessment.verdict {
        case .safe: mark = "✅"
        case .checkFirst: mark = "⚠️ "
        case .keep: mark = "🚫"
        }

        line("━")
        print("\(mark) \(assessment.verdict.localizedTitle)")
        print("   \(assessment.headline)")
        print("   지우면: \(assessment.cost)")
        line()
        print("경로     \(paths.abbreviate(url))")
        print("중요도   \(assessment.level.localizedTitle)")
        print("복구     \(assessment.recoverability.localizedTitle)")
        if !assessment.signals.isEmpty {
            print("근거")
            for signal in assessment.signals {
                let arrow: String
                switch signal.direction {
                case .raises: arrow = "↑"
                case .lowers: arrow = "↓"
                case .context: arrow = "·"
                }
                print("  \(arrow) \(signal.title) — \(signal.detail)")
            }
        }
        print()
    }

case "restore":
    let service = RestoreService(paths: paths)
    let entries = service.restorable()

    if entries.isEmpty {
        print("되돌릴 항목이 없습니다. 이 앱이 휴지통으로 옮긴 것만 대상입니다.")
    } else if flags.contains("--all") {
        var restored = 0
        for entry in entries where entry.isRestorable {
            switch service.restore(entry) {
            case .restored(let url):
                print("✓ \(paths.abbreviate(url))")
                restored += 1
            case .failed(let reason):
                print("✗ \(paths.abbreviate(entry.originalPath)) — \(reason)")
            }
        }
        print("\n\(restored)건 되돌렸습니다.")
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        line("━")
        print("되돌릴 수 있는 항목 \(entries.filter { $0.isRestorable }.count)건 / 전체 \(entries.count)건")
        line("━")
        for entry in entries {
            let mark = entry.isRestorable ? "○" : "✗"
            print("\(mark) \(formatter.string(from: entry.removedAt)) "
                + "\(ByteFormat.stringOrDash(entry.bytes).padded(to: 10)) "
                + "\(paths.abbreviate(entry.originalPath))")
            if let reason = entry.blockedReason { print("     \(reason)") }
        }
        print("\n전부 되돌리려면: maccleanctl restore --all")
    }

case "log":
    let entries = AuditLog(paths: paths).recentEntries()
    if entries.isEmpty {
        print("기록이 없습니다.")
    }
    let formatter = ISO8601DateFormatter()
    for entry in entries {
        let mark = entry.succeeded ? "✓" : "✗"
        print("\(mark) \(formatter.string(from: entry.timestamp)) \(entry.action.padded(to: 7)) "
            + "\(ByteFormat.string(entry.bytes).padded(to: 10)) \(entry.path ?? "-")")
        if let message = entry.message { print("     \(message)") }
    }

default:
    print("""
    사용법: maccleanctl <명령>

      scan                       검사해서 결과를 보여준다 (아무것도 지우지 않음)
        --deep                   홈 전체를 훑어 용량이 어디 있는지 + 대용량 파일까지 찾는다 (느림)
        --duplicates             내용이 완전히 같은 파일을 찾는다 (가장 느림)
      rules                      등록된 정리 규칙 전부 출력
      plan                       지울 항목 미리보기 (아무것도 지우지 않음)
      clean --confirm            실제로 정리 (기본은 휴지통으로 이동)
        --safe                   안전 등급만
        --include-permanent      휴지통 비우기까지 포함 (복구 불가)
      inspect <경로> …           그 파일·폴더를 지워도 되는지 판정하고 근거를 보여준다
      restore                    이 앱이 휴지통으로 옮긴 것 목록
        --all                    전부 원래 자리로 되돌린다
      log                        최근 작업 기록
    """)
}
