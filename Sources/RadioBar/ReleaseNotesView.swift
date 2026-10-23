import SwiftUI

struct RadioReleaseNote: Identifiable {
    let version: String
    let title: RadioText
    let changes: [RadioText]
    var id: String { version }
}

/// Bundled release history starts at the 2.0 baseline; keep Chinese in sync with CHANGELOG.md.
/// Detailed 1.x records remain only in the local pre-reinitialization backup.
enum RadioReleaseNotes {
    static let entries: [RadioReleaseNote] = [
        RadioReleaseNote(version: "2.0.1", title: RadioText("2.0.1", "2.0.1"), changes: [
            RadioText("切台缩短为 2.5 秒：先用 0.8 秒淡出原电台，静音间隔 0.5 秒，再用 1.2 秒淡入新电台，避免两个电台声音重叠。", "Shorten station transitions to 2.5 seconds: fade out the previous station over 0.8 seconds, leave 0.5 seconds of silence, then fade in the new station over 1.2 seconds, without overlapping audio."),
        ]),
        RadioReleaseNote(version: "2.0.0", title: RadioText("2.0.0", "2.0.0"), changes: [
            RadioText("以现有功能为基础开启 2.0 版本，合并历史更新说明，保留用户电台、排序、音量、语言及其他偏好。", "Start the 2.0 release series with consolidated updates, preserving stations, ordering, volume, language and other preferences."),
            RadioText("所有电台统一使用固定播放线路，失败后按已配置顺序重试；KISS 与央广地址随 App 构建打包，公开源码不包含完整地址。", "Use fixed streams for all stations and retry configured streams in order. Bundle KISS and CNR addresses during builds, keeping full addresses out of public source."),
            RadioText("整合电台添加、编辑、隐藏、排序和安全备份，保留独立静音、8 秒柔和切台与 6 秒睡眠渐弱。", "Bring together station editing, visibility, ordering and safe backups, with independent mute, 8-second transitions and a 6-second sleep fade."),
            RadioText("保留单台 Mac 管理和发布配置、iPhone 只读的 iCloud 同步，以及简繁中文与英文、浅深色外观、Dock 控制和签名更新。", "Keep one Mac publishing configuration to iPhone through iCloud, alongside Simplified and Traditional Chinese, English, light and dark appearance, Dock controls and signed updates."),
        ]),
    ]
}

struct ReleaseNotesView: View {
    let language: AppLanguage
    let currentVersion: String?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text(RadioText("按版本从新到旧排列，历史记录以当时的版本为准。",
                           "Newest first. Historical entries describe each release at that time.").value(language))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2).padding(.bottom, 2)
            ForEach(RadioReleaseNotes.entries) { entry in
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Text(entry.title.value(language))
                                .font(.system(size: 13, weight: .medium))
                                .accessibilityAddTraits(.isHeader)
                            if entry.version == currentVersion {
                                Text(RadioText("当前版本", "Current").value(language))
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.primary.opacity(0.055), in: Capsule())
                            }
                            Spacer(minLength: 0)
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(entry.changes.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•").foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                    Text(entry.changes[index].value(language))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.system(size: 12)).lineSpacing(3)
                            }
                        }
                    }
                }
                .id(entry.version)
            }
        }
        .textSelection(.enabled)
    }
}
