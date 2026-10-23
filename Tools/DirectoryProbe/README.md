# iCloud Drive 目录能力验证

这是独立开发工具，不是正式 RadioBar，也不是 iPhone 电台 App。Mac 仅在用户选择的目录下创建 `RadioBarDirectoryProbe/`，写入 UUID、随机设备标识与时间；iPhone 仅检查这些文件，不创建目录、不写入共享数据。工具不读取正式电台、播放地址或同步历史。解除关联不删除验证文件；验证完成后可由用户删除该子目录。

## 构建与运行

在仓库根目录运行：

```sh
./Tools/Tests/build-directory-probe.sh macos
./Tools/Tests/build-directory-probe.sh ios-simulator
./Tools/Tests/build-directory-probe.sh ios-device
```

三种产物分别在 `build/RadioBarDirectoryProbe-macOS.app`、`build/RadioBarDirectoryProbe-iOS-Simulator.app`、`build/RadioBarDirectoryProbe-iOS-Device.app`。Mac 与模拟器产物为 ad-hoc 签名；设备脚本只生成**未签名**产物，不能直接安装。脚本不启动、安装 App 或修改签名账户。

真机运行：在 Xcode 打开 [DirectoryProbe.xcodeproj](DirectoryProbe.xcodeproj)，选择 `RadioBarDirectoryProbe` target，在 Signing & Capabilities 中选择自己的开发团队／Personal Team，修改为自己可用的 bundle ID（必要时），连接 iPhone 后手动 Run。工具不需要 CloudKit、iCloud 专属容器或 App Groups entitlement；这是验证通过系统文件选择器访问用户文件夹的路径。真实账户、设备配置和签名结果仍以实际操作为准，不因编译成功判定可用。

Mac 14+、iPhone／模拟器 iOS 17+。iOS 17 是此隔离工具的编译基线，不决定未来正式 iPhone App 的最低版本。模拟器构建只验证平台编译，不能代替真机 iCloud 同步。

验证工具使用独立的 `local.victor.RadioBar.DirectoryProbe` 偏好域，保存本机访问书签；仅 Mac 生成随机设备标识。界面双语并列，不增加正式 App 的设置入口。

## 人工验收

1. 在同一 Apple 账户的 iCloud Drive 中准备一个普通文件夹。两端分别启动工具，通过“选择文件夹”选中同一个目录。
2. Mac 点击“写入并检查”，iPhone 点击“检查文件”。等文件提供商完成同步，确认手机读取到 Mac 写入的文件。
3. Mac 再写入一个文件，iPhone 再检查，确认读取新增文件。iPhone 没有写入按钮，也不生成设备标识或同步版本；检查前后共享目录内容应保持不变。多台 Mac 可以写入，但手机始终只读。
4. 两端退出并重新启动，不重新选择目录，点击“检查文件”，验证保存的书签可用。
5. 断网时 iPhone 尝试读取已下载目录，记录结果；Mac 可尝试离线写入，恢复网络后确认手机读取新文件。不承诺文件提供商一定允许离线读写。本工具不实现正式播放器缓存；共享核心 `StationSyncReader` 的私有缓存恢复由离线测试覆盖，正式 iPhone 接入时还须验证实际本地缓存。
6. 按系统能力撤销目录访问或使原目录不可访问，再检查；应显示失败，不能报告读取成功。非沙箱 Mac 的访问权限由系统和文件权限决定，不能把解除 App 关联等同系统撤权。
7. 重新选择目录，确认恢复。解除关联后检查应失败，云端验证文件保留。

界面中的“写入已交给文件提供商”仅证明本端写入完成，不证明上传完成或另一端已收到。文件未下载、目录不可用或权限失败都会保留已有关联，允许用户修复后重试。

验收记录需包含两端系统、工具构建源码、签名方式、Mac → iPhone 的首次和后续到达、重启读取的实际结果和未完成项。不要记录账户标识、完整路径或敏感文件内容到诊断。
