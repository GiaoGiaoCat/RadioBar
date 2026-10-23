import SwiftUI
import AppKit

private func publicationDate(_ date: Date, language: AppLanguage) -> String {
    let resolved = language.resolved()
    let locale = Locale(identifier: resolved == .english ? "en_US" : resolved == .traditionalChinese ? "zh_Hant" : "zh_Hans")
    return date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(locale))
}

struct StationSyncSettingsCard: View {
    @ObservedObject var sync: MacStationSyncController
    @ObservedObject var settings: AppSettings
    @State private var folderPicker: NSOpenPanel?
    @State private var setupTask: Task<Void, Never>?
    @State private var manualSync = false
    @State private var openError: RadioText?

    var body: some View {
        SettingsCard {
            HStack(spacing: 8) {
                Text(settings.text("电台配置同步", "Station configuration sync")).font(.system(size: 13, weight: .medium))
                Spacer()
                ProgressView().controlSize(.small).frame(width: 16, height: 16)
                    .opacity(manualSync ? 1 : 0).accessibilityHidden(!manualSync)
                    .accessibilityLabel(settings.text("正在发布配置", "Publishing configuration"))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(sync.status.text.value(settings.language)).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("stationSyncStatus")
                if sync.isLinked, let folder = sync.folderURL {
                    Text(folder.path).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(folder.path)
                }
                if let date = sync.lastChecked {
                    Text(settings.text("最近检查：", "Last checked: ") + publicationDate(date, language: settings.language))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let error = sync.errorText {
                    Text(error.value(settings.language)).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("stationSyncError")
                }
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(alignment: .leading, spacing: 10) { actions }
            }
            if sync.isLinked {
                Button {
                    do { try sync.openSyncFolder(); openError = nil }
                    catch { openError = RadioText("无法打开 iCloud 同步文件夹。请确认所选目录位于 iCloud Drive，并检查访问权限。", "Cannot open the iCloud sync folder. Make sure the selected folder is in iCloud Drive and check access permissions.") }
                } label: {
                    SettingsActionLabel(title: settings.text("打开 iCloud 同步文件夹", "Open iCloud sync folder"), systemImage: "folder")
                }.buttonStyle(.link).accessibilityIdentifier("openStationSyncFolder")
            }
            if let openError {
                Text(openError.value(settings.language))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .sheet(item: Binding(get: { sync.review }, set: { if $0 == nil { sync.cancelReview() } })) { review in
            StationSyncReviewSheet(sync: sync, review: review, language: settings.language)
                .radioAppearance(settings.appearance)
        }
        .onDisappear {
            folderPicker?.cancel(nil); folderPicker = nil
            setupTask?.cancel(); setupTask = nil
            manualSync = false
        }
    }
    @ViewBuilder private var actions: some View {
        if !sync.isLinked {
            Button(settings.text("设置 iCloud 同步…", "Set up iCloud sync…")) {
                setupTask = Task { @MainActor in
                    let needsPicker = await sync.prepareICloudAssociation()
                    guard !Task.isCancelled else { return }
                    setupTask = nil
                    if needsPicker { chooseFolder() }
                }
            }.disabled(busy).accessibilityIdentifier("setupICloudStationSync")
        }
        Button(settings.text(sync.isLinked ? "更改文件夹…" : "选择文件夹…", sync.isLinked ? "Change folder…" : "Choose folder…")) {
            chooseFolder()
        }.disabled(busy).accessibilityIdentifier("connectStationSync")
        if sync.isLinked {
            Button(settings.text("立即同步", "Sync now")) {
                manualSync = true
                Task { @MainActor in await sync.synchronize(); manualSync = false }
            }.disabled(busy || manualSync).accessibilityIdentifier("checkStationSync")
            Button(settings.text("停止同步", "Stop syncing")) { sync.disconnect() }
                .accessibilityIdentifier("disconnectStationSync")
        }
    }
    private var busy: Bool {
        folderPicker != nil || setupTask != nil || sync.isBusy || sync.review != nil || settings.stationChangesBlocked
    }
    private func chooseFolder() {
        guard folderPicker == nil else { return }
        let panel = NSOpenPanel(); folderPicker = panel
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.prompt = settings.text("选择", "Choose")
        panel.message = settings.text("选择 iCloud Drive 中的同步文件夹；本机配置保持原位。",
                                      "Choose a sync folder in iCloud Drive. Local configuration stays in place.")
        panel.begin { result in
            Task { @MainActor in
                guard folderPicker === panel else { return }
                folderPicker = nil
                if result == .OK, let url = panel.url { await sync.prepareAssociation(to: url) }
            }
        }
    }
}

struct StationSyncReviewSheet: View {
    @ObservedObject var sync: MacStationSyncController
    let review: StationSyncReview
    let language: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(RadioText("发布本机电台配置", "Publish local station configuration").value(language))
                .font(.system(size: 15, weight: .medium))
            Text(RadioText("此 Mac 管理电台，iPhone 从所选文件夹读取配置。", "This Mac manages stations. iPhone reads the configuration from the selected folder.").value(language))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(review.folderName).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(3).truncationMode(.middle).textSelection(.enabled)
            if review.existing != nil {
                Text(RadioText("文件夹中的现有配置将由本机配置接替，替换前会保存在本机备份。", "The local configuration will replace the existing configuration in this folder. A local backup is saved before replacement.").value(language))
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            if let error = sync.errorText {
                Text(error.value(language)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(RadioText("取消", "Cancel").value(language)) { sync.cancelReview() }
                    .keyboardShortcut(.cancelAction).disabled(sync.isBusy)
                Button(RadioText("发布", "Publish").value(language)) { Task { await sync.confirmReview() } }
                    .keyboardShortcut(.defaultAction).disabled(sync.isBusy)
            }
        }.padding(24).frame(width: 440).fixedSize(horizontal: false, vertical: true)
    }
}
