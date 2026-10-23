import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DirectoryProbeModel: ObservableObject {
    private let defaults = UserDefaults(suiteName: "local.victor.RadioBar.DirectoryProbe")!
    @Published var status = "选择同一个 iCloud Drive 文件夹开始验证。 / Select the same iCloud Drive folder on both devices."
    @Published var selecting = false
    @Published var markerCount = 0

    private struct Marker: Codable {
        let schemaVersion: Int
        let id: UUID
        let device: UUID
        let createdAt: Date
    }

    #if os(macOS)
    private var device: UUID {
        if let string = defaults.string(forKey: "device"), let id = UUID(uuidString: string) { return id }
        let id = UUID(); defaults.set(id.uuidString, forKey: "device"); return id
    }
    #endif

    func select(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let directory = try StationSyncDirectory(selecting: url)
            try directory.withAccess { _ in }
            defaults.set(directory.bookmark, forKey: "bookmark")
            #if os(macOS)
            status = "已保存授权，请写入验证文件。 / Access saved. Write a probe file next."
            #else
            status = "已保存授权，请检查 Mac 写入的文件。 / Access saved. Check files written by your Mac."
            #endif
        } catch { fail() }
    }

    private func fail() {
        status = "无法访问或读取文件。请检查下载状态、权限，必要时重新选择。 / Unable to access or read files. Check download status and permissions, or select the folder again."
    }

    #if os(macOS)
    func writeAndCheck() { inspect(write: true) }
    #endif

    func check() { inspect(write: false) }

    private func inspect(write: Bool) {
        do {
            guard let bookmark = defaults.data(forKey: "bookmark") else { throw CocoaError(.fileReadNoPermission) }
            try StationSyncDirectory(bookmark: bookmark).withAccess { selected in
                // Dedicated probe namespace; no production stations.json or RadioBarSync data is touched.
                let root = selected.appendingPathComponent("RadioBarDirectoryProbe", isDirectory: true)
                #if os(macOS)
                if write { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
                #endif
                let info = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard info.isDirectory == true, info.isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
                var coordinatorError: NSError?, operationError: Error?
                #if os(macOS)
                if write {
                    let marker = Marker(schemaVersion: 1, id: UUID(), device: device, createdAt: Date())
                    let file = root.appendingPathComponent(marker.id.uuidString.lowercased() + ".json")
                    NSFileCoordinator().coordinate(writingItemAt: file, options: [], error: &coordinatorError) { url in
                        do { try JSONEncoder().encode(marker).write(to: url, options: .withoutOverwriting) }
                        catch { operationError = error }
                    }
                    if let error = operationError ?? coordinatorError { throw error }
                }
                #endif
                var devices = Set<UUID>(), count = 0
                let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                for file in files where file.pathExtension == "json" && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
                    coordinatorError = nil; operationError = nil
                    NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinatorError) { url in
                        do {
                            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                            guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) < 4096 else {
                                throw CocoaError(.fileReadCorruptFile)
                            }
                            let marker = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: url))
                            guard marker.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
                            devices.insert(marker.device); count += 1
                        } catch { operationError = error }
                    }
                    if let error = operationError ?? coordinatorError { throw error }
                }
                markerCount = count
                status = "已读取 \(count) 个文件、\(devices.count) 个设备标识。 / Read \(count) files from \(devices.count) device IDs."
                    + (write ? "\n写入已交给文件提供商；请在另一设备检查。 / Write handed to the file provider; check on the other device." : "")
            }
        } catch { fail() }
    }

    func forget() {
        defaults.removeObject(forKey: "bookmark")
        markerCount = 0
        status = "已解除本机关联，验证文件保留。 / Local association removed. Probe files were kept."
    }
}

struct DirectoryProbeView: View {
    @StateObject private var model = DirectoryProbeModel()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("RadioBar 目录验证 / Directory Probe").font(.headline)
                Text("隔离工具，不修改正式电台配置。 / Isolated tool; does not modify your station configuration.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("选择文件夹 / Select folder") { model.selecting = true }
                #if os(macOS)
                Button("写入并检查 / Write and check") { model.writeAndCheck() }
                #else
                Text("iPhone 只读：不写入或创建共享文件。 / iPhone is read-only: no shared files are written or created.")
                    .font(.callout).foregroundStyle(.secondary)
                #endif
                Button("检查文件（含重启后授权） / Check files (including after relaunch)") { model.check() }
                Button("解除关联 / Disconnect") { model.forget() }
                Divider()
                Text(model.status).textSelection(.enabled)
                Text("验收：Mac 写入 → iPhone 检查到相同文件 → Mac 再写入后 iPhone 读取更新 → 退出重开后再次检查 → 撤销访问或移走目录后检查失败 → 重新选择后恢复。iPhone 不上传配置。 / Verify: write on Mac, read the same files on iPhone, write another file on Mac and read the update on iPhone, relaunch and check, revoke access or move the folder and check failure, then reselect. iPhone never uploads configuration.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }
        .fileImporter(isPresented: $model.selecting, allowedContentTypes: [.folder], allowsMultipleSelection: false, onCompletion: model.select)
        #if os(macOS)
        .frame(minWidth: 580, minHeight: 480)
        #endif
    }
}

@main
struct DirectoryProbeApp: App {
    var body: some Scene { WindowGroup { DirectoryProbeView() } }
}
