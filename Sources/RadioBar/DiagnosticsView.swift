import SwiftUI
import AppKit

private typealias DiagnosticViewState<Value> = SwiftUI.State<Value>

@MainActor
struct DiagnosticsView: View {
    let store: RadioDiagnostics
    let language: AppLanguage
    @DiagnosticViewState private var snapshot: DiagnosticSnapshot
    @DiagnosticViewState private var copied = false

    init(store: RadioDiagnostics = .shared, language: AppLanguage) {
        self.store = store
        self.language = language
        _snapshot = DiagnosticViewState(initialValue: store.snapshot())
    }

    private func text(_ zh: String, _ en: String) -> String { RadioText(zh, en).value(language) }
    private func refresh() { snapshot = store.snapshot(); copied = false }

    var body: some View {
        SettingsCard {
            SettingsRowTitle(title: text("连接诊断", "Connection diagnostics"),
                             subtitle: text("复制后可交给 AI 排查连接与重试问题。", "Copy the report to help investigate stream and reconnection problems."),
                             titleWeight: .medium)
            VStack(alignment: .leading, spacing: 9) {
                row(text("电台", "Station"), Station(rawValue: snapshot.station)?.displayName.value(language) ?? "—")
                row(text("状态", "State"), phaseTitle)
                row(text("线路 / 重试", "Source / retries"), "\(sourceTitle) · \(snapshot.retries)/4")
                row(text("最近错误", "Last error"), snapshot.lastError)
            }
            Divider()
            HStack(spacing: 8) {
                Button {
                    let report = store.report()
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(report, forType: .string)
                    snapshot = store.snapshot()
                } label: {
                    SettingsActionLabel(title: copied ? text("已复制", "Copied") : text("复制诊断信息", "Copy diagnostics"),
                                        systemImage: copied ? "checkmark" : "doc.on.doc")
                }.buttonStyle(.borderedProminent).controlSize(.regular)
                Button(text("刷新", "Refresh")) { refresh() }.buttonStyle(.bordered).controlSize(.regular)
                Spacer(minLength: 0)
                Button(text("清空", "Clear")) { store.clear(); refresh() }.buttonStyle(.link).font(.system(size: 12))
            }
            Text(text("\(snapshot.lines.count)/100 条 · \(snapshot.bytes/1024) KB · 复制时获取最新记录",
                      "\(snapshot.lines.count)/100 events · \(snapshot.bytes/1024) KB · Copy includes the latest events"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        SettingsHint(text: text("仅保留本次运行最近的记录，最多 100 条 / 64 KB；不写日志文件，退出即清除。不包含播放地址、token 或响应正文。",
                                "Memory only: up to 100 events / 64 KB, cleared on exit. No log files, stream URLs, tokens or response bodies."))
        DisclosureGroup(text("最近事件", "Recent events")) {
            Text(snapshot.lines.suffix(10).joined(separator: "\n"))
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.disclosureGroupStyle(SettingsDisclosureStyle(language: language))
        .onAppear { refresh() }
    }

    private var phaseTitle: String {
        let chinese: [String: String] = ["Stopped": "已停止", "Connecting": "连接中",
            "Buffering": "缓冲中", "Playing": "播放中", "Paused": "已暂停", "Retrying": "等待重试",
            "Failed": "连接失败", "Error": "连接失败", "Sleep timer ended": "倒计时已结束"]
        return RadioText(chinese[snapshot.phase] ?? snapshot.phase, snapshot.phase).value(language)
    }
    private var sourceTitle: String {
        let chinese = ["primary": "主线路", "backup": "备用线路"]
        return RadioText(chinese[snapshot.source] ?? snapshot.source, snapshot.source).value(language)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12))
    }
}
