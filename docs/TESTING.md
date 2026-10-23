# 验证入口与当前覆盖

本文维护可执行入口、最新结果和验收缺口；旧逐次版本流水账已合并，完整记录保存在本地被 Git 忽略的重建前源码备份中。版本说明见 [CHANGELOG](../CHANGELOG.md)，当前状态见 [HANDOFF](HANDOFF.md)。

## 2.0.2（109）本轮验证

内置地址资源改为 AES-256-GCM 密文，构建生成随机密钥及混淆 Swift 源码，App 在内存校验解密。输入来源、固定选址、完整查询参数、播放过渡、配置和诊断规则保持。以下为本地验证结果；用户随后授权提交、推送 `main` 与 `v2.0.2`，由 Actions 构建发布。按用户要求不跟踪最终远端结果或代为安装。

- 内置地址专项通过：14 类无效输入、13 项来源／脱敏／原子配对生成检查；验证每次生成不同密文和密钥材料、完整查询及线路顺序保留、头／nonce／密文／tag 篡改、错误密钥、截断及超限拒绝、禁止明文回退。将实际生成密钥编入隔离 App，生产 Bundle.main 加载验证本地与 Secrets 优先级，缺失、损坏及跨构建错配安全失败。日志 `build/encrypted-stream-tests.log`。
- 完整 `./test.sh` 通过，日志 `build/encrypted-full-tests.log`。初次沙箱中的现有配置文件协调断言失败后，在允许的本机环境完整复验通过；包括诊断脱敏、配置／偏好、音频、同步、原生拖放和 Dock。未重复实际计时音频专项，播放过渡实现未改。
- `./build.sh`、Xcode Release 增量构建、SwiftPM Release 均通过，日志分别为 `build/encrypted-build.log`、`build/encrypted-xcode.log`、`build/encrypted-spm.log`。Xcode 移除旧包内明文资源，并用本轮生成密钥验证包内两台地址与私有输入完全一致、主二进制不含连续原始密钥，记录 `build/encrypted-xcode-resource-verification.log`。Xcode 保留现有 headermap / AppIntents 提示，未扩展修改。
- 缺失 Secrets 的真实构建保留旧 ZIP，记录 `build/encrypted-missing-input.log`。最终 ZIP 独立解压后严格 deep codesign、完整 Info.plist、2.0.2 / 109、arm64、macOS 14、默认 JSON 及资源权限通过；所有包内文件未检出两条完整地址、长查询凭据、明文地址 JSON 或生成源码。源码／本轮日志扫描及 private／生成文件忽略检查通过。证据 `build/encrypted-zip-verification.json`、`build/encrypted-codesign.log`；ZIP SHA-256 `43878cfe808e5acfa1dd2158a75d2185671ce35041d0e09e77de122a7d2973ed`。
- 更新说明设置预览生成 127 张，日志 `build/encrypted-settings.log`，图片 `build/encrypted-settings/`；实际检查简繁中文／英文、浅深色的六张展开日志图，新说明和 2.0.2（109）标记完整、无截断。文档本地链接与 `git diff --check` 通过。本轮未联网播放、未安装，未读取更新私钥、签署更新源或执行 Sparkle 安装升级。当前仍为 ad-hoc 签名、未公证；包内混淆不能证明无法逆向提取。

## 2.0.1（108）验证记录

Mac 切台改为 0.8 秒淡出旧台、0.5 秒双路静音、1.2 秒淡入新台，正常交接共 2.5 秒；静音从旧台实际归零时开始计时，回调延迟不跳过间隔，总时长相应顺延。本轮完成 2.0.1（108），同步双语日志和行为文档；用户随后授权提交并推送 `main` 与 `v2.0.1` 标签。GitHub 发布由标签工作流执行，结果另行核对，本机不安装。

- 最终源码的音频逻辑专项通过，日志 `build/gapped-audio-tests.log`。2501 个毫秒采样点验证两段曲线、中间完整静音及正常 2.5 秒释放旧实例；每次独立音量写入检查至多一路非零、最多两路加载。覆盖延迟回调后仍计满 0.5 秒静音、间隔起止／中段的缓冲与失败恢复、快速切台、暂停取消、静音解除／音量调整及睡眠到期，均不意外启动待执行的淡入。
- 最终源码重新编译的真实 AVPlayer 本地静音专项通过，日志 `build/native-audio-transitions.log`（执行日志 `build/gapped-native-test-run.log`）。总过渡实测约 2.531 秒、连续双路零音量约 0.533 秒；每次音量写入均无两路非零，6 秒睡眠渐弱及保存音量保持通过。按 30 Hz 计时允许回调帧间隔误差，在允许 SwiftUI 宏和图形服务的本机环境运行。
- 最终源码的完整 `./test.sh` 在允许的本机环境通过，日志 `build/gapped-full-tests.log`；包含音频覆盖、固定线路／重试、配置／偏好、38 项 v2 协议／旧事务、69 项 Mac 发布／备份、原生拖放和 Dock 回归。
- 最终源码的 `./build.sh` 通过，日志 `build/gapped-build.log`。重建的最终 ZIP 独立解压后严格 deep codesign、2.0.1 / 108、arm64、macOS 14、完整 Info.plist 和默认电台资源比对通过；结果 `build/gapped-zip-verification.json`、`build/gapped-codesign.log`。仍为 ad-hoc 签名，未公证。
- 当前更新说明的设置预览 127 张生成通过，日志 `build/gapped-settings.log`，图片 `build/gapped-settings/`。实际检查简繁中文／英文、浅深色共六张展开日志图，2.5 秒及 0.5 秒静音说明完整显示、无截断，2.0.1（108）和当前版本标记正确。本地文档链接、版本／构建号、bundle ID／更新公钥／ATS 保持及 `git diff --check` 通过。
- 尚未实际直播试听；静音解码和音量写入检查不能替代真实出声的主观听感验收。没有运行联网、安装或更新专项。

## 2.0.0（107）本轮验证

本轮修改版本元数据、合并双语更新说明及历史文档，更新设置预览的日志定位；不改变播放、配置、偏好、拖放或 Dock 的生产逻辑。首次提交保留为无父提交的 2.0.0 基线；以下为当时的本地验证记录，其后的远端发布状态见 HANDOFF。

- `./build.sh` 通过，日志 `build/v2-build.log`。最终 ZIP 独立解压严格 codesign、arm64、最低 macOS 14、2.0.0 / 107、完整 Info.plist 和包内资源比对通过；私有地址与输入一致且不在主 Mach-O 中。ZIP 为 3,070,995 字节，SHA-256 为 `1a34ce98c9a5f7180493c8bcd601b69f3141aaff7461c71d6718288cba81dd2e`，记录 `build/v2-verification.json` 与 `build/v2-codesign.log`；仍为 ad-hoc 签名，未公证。
- 设置预览 127 张通过，日志 `build/v2-settings.log`；实际检查三语浅深色关于页的 2.0.0（107）和完整四项合并日志，无截断，滚动定位复用版本列表首尾而不再写死 1.0.0。图片在 `build/v2-settings/`。
- 从当前源码重新编译现有 `PrepareUpdateNotes` 工具，在本地未签名测试 feed 中验证默认／三种语言的四份说明、四项条目和无旧逐版记录；跨 1.x → 2.0.0 的发布顺序、同版及倒退拒绝通过，记录 `build/v2-notes-verification.json`。未使用私钥、未生成正式签名 feed，不能据此认定真实 Sparkle 2.0 升级通过。
- 本地文档文件／标题锚点、版本／构建号与公钥保持、私有备份忽略、地址扫描和 `git diff --check` 通过。未重复完整音频／联网回归或 Xcode／SwiftPM 构建；播放、配置与偏好的生产实现未改。新 Git 的首次提交和对象排除在提交后再次核对。

## 沿用的功能覆盖与证据

以下是 2026-10-23 的 2.0.0 基线已经取得的结果；本轮变更后的验证以上方当前版本记录为准：

- 完整 `./test.sh` 通过，覆盖固定线路选址、重试预算、配置与偏好、38 项 v2 协议／旧事务和 69 项 Mac 发布／备份检查，以及音频逻辑、原生拖放、Dock；日志 `build/private-stream-tests.log`。首次文件协调／图形沙箱失败已在允许环境复验。
- 私有地址注入专项覆盖完整查询与顺序、14 类无效载荷、10 项 Secrets／本地优先级、Actions 不回退、脱敏错误、失败保留输出和包内资源权限；日志 `build/private-stream-input-tests.log`。缺少输入的真实构建保留旧 ZIP，记录 `build/private-stream-missing-input.log`。
- 生产 `BuiltinStreams.swift` 的隔离探针验证最终 ZIP 的 Bundle.main 加载和资源缺失安全路径；旧 1.x 基线的 CLT／Xcode／SwiftPM 三种构建及资源一致性通过。旧产物摘要仅供追溯，不作为 2.0 当前产物的证明。
- 2.0.0 音频基线的真实 AVPlayer 本地静音专项通过 8 秒切台和 6 秒睡眠渐弱；日志 `build/fixed-native-audio.log`。联网专项中 KISS／央广均 ready、playing 且连续五秒时间推进，日志 `build/fixed-network.log`；用户也确认实际可听，但持续时长未提供。
- 用户曾确认旧版 Sparkle 跨版本下载、替换和重启成功且偏好保持；旧签名专项验证 feed／说明／ZIP 篡改拒绝和语言选择。不能由此认定 2.0 已发布、安装或完成新仓库端到端更新。
- 本地新 Git 排除了旧提交、标签、私有地址文件和旧备份；五个旧工作目录的 HEAD、已暂存／未暂存差异及未跟踪内容保持。备份仍含旧历史，`private/` 必须持续忽略。

## 按改动选择验证

先检查 Git diff 和相关现有测试，再按下表选择。下文所有命令均从仓库根目录运行，路径大小写必须准确；旧根目录的专项脚本不再存在。需要 Apple Silicon Mac、macOS 14+ 和 Command Line Tools；Python 3 仅用于部分开发工具，App 运行不依赖它。

| 本次改动 | 复用顺序 |
|---|---|
| 纯文档、链接 | 检查本地链接、脚本引用和 `git diff --check`；不用重复音频或 UI 回归 |
| 播放、取址、偏好 | 开发中先跑相关专项，完成后 `./test.sh`；交付时 `./build.sh` |
| 过渡、取消、睡眠渐弱 | `./Tools/Tests/test-audio-transitions.sh`；必要时追加 `./Tools/Tests/test-native-audio-transitions.sh`；最终仍跑完整离线回归 |
| 电台排序、配置行控件或显示/隐藏 | `./Tools/Tests/test-native-channel-drops.sh` 覆盖源与接收端，配合设置预览；有图形环境再用 `--interactive` 实际拖放，偏好变更还需完整离线回归 |
| 设置窗口、Dock 行为 | `./Tools/Tests/test-dock-visibility.sh`，设置界面变化还需设置预览 |
| 菜单/设置视觉、简繁中文/英文或外观 | 分别运行菜单/设置预览脚本并检查图片；按涉及的逻辑补专项，不因纯视觉修改重复整套音频测试 |
| 图标母图 | `./Tools/make-icons.sh` → `./build.sh` → `./Tools/Previews/render-app-icon.sh`，检查系统处理后的图片 |
| Sparkle 或签名交付 | `./build.sh` → `./Tools/sign-release.sh` → `./Tools/Tests/test-updates.sh`；发布顺序逻辑可先单跑 `python3 Tests/ReleaseOrderTests.py` |
| 直播源连通/解码问题 | 先离线回归，再按需选下表的联网参数；不把网络探测当默认测试或实际出声验收 |

`./test.sh` 已包含 v2 配置、旧事务恢复及 Mac 单向发布、音频逻辑、原生排序和 Dock 专项，通过后无需原样重复。它不包含本地真实 AVPlayer、Sparkle 更新、预览、真实 iCloud 或外网播放。Tests 是脚本编译的独立可执行程序，当前不是常规 `swift test` 套件。不要直接运行 `build/` 中的旧测试二进制作为最新源码的验证。

配置模型与迁移覆盖复用 `Tests/ResolverTests.swift` 和 `Tests/SettingsTests.swift`，使用临时目录与隔离 UserDefaults，不写正式用户配置。测试/预览编译使用 `RADIOBAR_TESTING`，允许从源码资源读取默认 JSON；正式 App 仅从包内读取，SwiftPM 使用 `Bundle.module`。显式源文件列表已加入 `BuiltinStreams.swift` / `StationCatalog.swift`，构建与更新测试 App 同步打包默认 JSON。

## 脚本索引与使用方法

### 构建、测试和联网探测

内置地址注入使用 `Tools/prepare-builtin-streams.sh OUTPUT_DIRECTORY`，由 `build.sh`、Xcode、联网和更新专项复用；用 Swift / CryptoKit 编译生成器及生产 `BuiltinStreams.swift`，不需要额外 Python 依赖。成对环境变量优先，否则读取 `private/builtin-streams.json`；Actions 禁止本地回退。输出目录专用于随机 AES-256-GCM 密文 `builtin-streams.bin` 与混淆密钥 `BuiltinStreamKey.swift`，目录原子替换保证配对，含无关文件时拒绝覆盖。密文 0644、源码 0600，不生成磁盘明文副本；CLT 临时产物退出清理。Xcode 编译前生成并在原生 Sources 阶段编译密钥，SwiftPM 预生成到忽略的 Generated 目录；密钥源码不打包。参数仅为输出目录，禁止输出地址、密钥或解析错误正文。SwiftPM 步骤见 [源码编译指南](BUILD.md#xcode-与-swiftpm)。

离线测试／预览的 `RADIOBAR_TESTING` 使用 `.invalid` 假地址，无需生成密钥；生成器／解码测试用 `RADIOBAR_STREAM_TOOL` 排除包内静态加载。联网专项另加 `RADIOBAR_LIVE_STREAMS` 并在隔离 App 中注入配对密文／编译密钥，不得用普通离线假地址声称真实播放通过。正式 App 缺失／损坏／篡改／错配资源时安全返回空地址，禁止明文回退并由既有连接失败路径处理，不从开发者目录读取私有数据。

| 可执行入口 | 前置条件、输出与边界 |
|---|---|
| `./build.sh` | CLT Release arm64/macOS 14 构建、组装、ad-hoc 签名；自动调用 SDK 获取脚本，首次或缓存损坏时需要网络。App 与新 ZIP 均检查无隔离属性后替换 `build/RadioBar-macOS-arm64.zip`，失败保留旧包；不等于 Xcode 构建 |
| `./test.sh` | 全部离线回归，编译并运行 `Tests/` 中的测试；含v2 配置、旧事务恢复及 Mac 单向发布、音频逻辑、原生排序、Dock 专项。输出可执行程序到 `build/`，不发声；最后 Dock 阶段需图形会话 |
| `./Tools/Tests/test-builtin-streams.sh` | 内置地址解码／加密与构建输入专项，已纳入 `./test.sh`；检查完整查询参数和顺序、AES-GCM 认证／错误密钥／截断拒绝、随机生成、生产 Bundle 加载、缺失／损坏／错配及明文不回退、环境变量优先级、Actions 禁止本地回退、错误脱敏、失败保留配对产物和输出权限（密文 0644、密钥源码／本地私有输入 0600）。使用临时假地址，不读取私有文件或访问网络 |
| `./Tools/Tests/test-mac-station-sync.sh` | 编译当前 Mac 单向发布控制器及设置；隔离目录／偏好验证序号、重试、重新关联、外部修改、旧版迁移、自动发布及备份轮替，输出 `build/MacStationSyncTests`，已接入 `./test.sh`；不访问用户 iCloud 或正式配置 |
| `./Tools/Tests/test-station-sync.sh` | 编译当前 v2 文件格式、共享配置、文件安全及旧事务恢复源码，输出 `build/StationSyncTests` 后运行；使用隔离临时目录和偏好，无云端、网络、正式配置及音频操作，已接入 `./test.sh` |
| `./Tools/Tests/test-station-sync.sh --typecheck-ios` | 需完整 Xcode 与 iOS SDK；对共享基础及其既有 Foundation 依赖分别检查真机／模拟器类型兼容，只使用模块缓存，不安装或进行 iCloud 验收 |
| `./Tools/Tests/build-directory-probe.sh [macos\|ios-simulator\|ios-device]` | 默认 macos；在 `build/` 生成对应隔离 App，Mac／模拟器 ad-hoc 签名，真机未签名；不启动或安装。UI 交互须人工完成，不纳入无人值守 `./test.sh`，签名／目录授权步骤见工具说明 |
| `./Tools/Tests/test-audio-transitions.sh` | 假播放器/可控时钟及真实 run loop，验证 0.8 秒淡出＋0.5 秒静音＋1.2 秒淡入、逐次音量写入无叠音、竞态与取消；不访问直播源 |
| `./Tools/Tests/test-native-channel-drops.sh` | 生产标题栏/背景拖动配置，验证手柄禁止窗口移动、真实视图事件命中及原生接收/提交/取消；OS 事件封装和载荷读取有适配，不等于实际鼠标拖放 |
| `./Tools/Tests/test-native-channel-drops.sh --interactive` | 编译并组装 `build/RadioBarDragTests.app`；打开后以隔离偏好和临时配置目录显示真实设置页，无网络/音频。用鼠标向上/向下拖动普通台和内置台，验证取消不改序；滚动到底部先点击“重新加载”，确认中广显示为 Reloaded BCC，再点击“恢复内置电台列表”，确认名称立即恢复、成功提示约 5 秒后消失，再关闭窗口。程序检查窗口原点未变、排序已改变且新 AppSettings 读取一致，以及加载已发生、原配置备份内容、恢复后的 JSON 和内存列表；成功写入 `build/native-channel-drag-result.txt`。不修改正式 App、用户配置或偏好；隔离 App 同步打包许可证，可切换关于页检查许可入口 |
| `./Tools/Tests/test-native-channel-drops.sh --interactive-visibility` | 复用同一隔离测试 App，准备仅 KISS 显示且作为固定默认的场景。打开 App 后点击隐藏 KISS，关闭“至少一个”提示并确认开关仍开启；开启 CNR Music Radio，再隐藏 KISS，确认默认台提示；关闭窗口。程序检查两种反馈事件、提示清除、默认回退和可见台跨 AppSettings 实例持久化，写入 `build/native-station-visibility-result.txt`。不要求此模式执行拖放或重新加载，临时配置与偏好独立于正式 App |
| `./Tools/Tests/test-native-channel-drops.sh --interactive-editor` | 复用隔离测试 App 与临时 JSON；添加中英文名称且英文为 Editor Test 的台、编辑中广英文名为 Edited BCC、确认删除 UFO，关闭设置窗口。程序验证 JSON 与列表立即更新、ID 保留、偏好读取一致、至少三份原字节备份及窗口未移动，成功写入 `build/native-station-editor-result.txt`。可先练习取消、无效地址、外部冲突，错误不会写入；该模式无需重新加载、恢复或执行拖放，完整鼠标排序另用 `--interactive` |
| `./Tools/Tests/test-dock-visibility.sh` | 原生窗口生命周期、激活策略、Dock reopen 与启动偏好；需 macOS 图形会话，会短暂显示测试窗口，不等同真实鼠标/Dock 像素验收 |
| `./Tools/Tests/test-native-audio-transitions.sh` | 两个真 AVPlayer + 本地静音 PCM，验证 2.5 秒分段时序与 0.5 秒静音间隔、逐次音量写入无叠音、完成后释放旧实例及 6 秒睡眠渐弱；无需直播网络。结果在终端及 `build/native-audio-transitions.log`，不代表真实出声验收 |
| `./Tools/Tests/test-updates.sh` | 先完成构建和签名，需 `build/updates/appcast*.xml` 四份签名源、Python 3、SDK、本地回环监听和图形服务；临时 App 验证无更新/发现更新、语言选择、feed/说明/ZIP 篡改拒绝和发布顺序，原生弹窗视图预览在 `build/update-previews/`，不下载或替换正式 App |
| `./test.sh --network` | 先完整离线回归，再静音探测 KISS、央广、中广、飞碟和广东已配置线路；不是全部 12 个电台验收 |
| `./test.sh --network-fixed` | 先完整离线回归，再静音探测 KISS 与央广固定源 |
| `./test.sh --network-ufo`、`./test.sh --network-guangdong` | 同样先完整离线回归，再只探测指定台主备源；不是跳过离线阶段的快捷命令 |
| `./Tools/Tests/test-playback.sh [--network-fixed\|--network\|--network-ufo\|--network-guangdong]` | 独立编译当前源码、组装临时隔离 bundle，默认只探测 KISS 与央广；生产 RadioPlayer/固定 resolver/静音 AVPlayer 每条线路最多观察 30 秒，要求连续 5 秒时间推进。任一线路首次失败即判该线路未通过，不以备用成功代替；使用隔离偏好，不碰正式配置，不证明真实出声或长期稳定性 |

旧 TingFM 页面/token/签名解析和重定向提供器已删除，对应 `TingFMTests`、`RedirectTests`、`CNRedirectIntegrationTests` 及 MusicRadioCheck 取址工具不再是当前入口。仍有价值的切台/暂停迟到结果覆盖已迁入 `AudioTransitionTests`，固定源选址、预算、无计划刷新及隐私覆盖由 Resolver/AudioTransition/Diagnostics 测试维护。相关测试能力保留；旧逐次执行记录仅留在本地备份。

### 界面预览

三项脚本均重新编译对应预览工具，需可用的 macOS 图形服务。可选第一个参数为输出目录，例如 `./Tools/Previews/render-menu.sh build/menu-review`；相对路径按仓库根目录解析。

| 可执行入口 | 输入与默认输出 |
|---|---|
| `./Tools/Previews/render-menu.sh` | 从生产菜单提取测试副本，需 Python 3；含播放状态切换、显示电台数量变化时的自然尺寸及上下边界断言；图片输出 `build/menu-previews/`，生成 Swift 在 `build/` |
| `./Tools/Previews/render-menu.sh --interactive` | 编译并组装 `build/RadioBarMenuPreview.app`；打开后显示生产菜单栏标签，复用生产菜单、7 个电台和隔离偏好；测试 App 的 Preview Appearance 菜单可切换 Light / Dark / System（⌘⌥1 / ⌘⌥2 / ⌘⌥0），仅改变隔离偏好。播放入口约 2 秒后模拟 Playing，无直播音频。将现有有界诊断报告写入 `build/menu-live-diagnostics.txt`。开发自动运行可从根目录执行 `RADIOBAR_MENU_AUTORUN=1 ./build/RadioBarMenuPreview.app/Contents/MacOS/MenuSnapshots`，约 14 秒内由原生按钮方法初次展开，等待启动事件跟踪稳定后，通过原生窗口方法隐藏和显示，再模拟重试/取址/失败/播放、切台及深/浅/系统外观；11 项窗口/呈现图层高度、边界、外观、背景覆盖与事件穿透断言写入 `build/menu-retry-result.txt`，失败时保留报告并返回退出码 1（不触发崩溃），成功退出 0。可在同一自动运行命令前额外设置 `RADIOBAR_MENU_TEST_EARLY_DISMISS=1`，主动提前隐藏隔离菜单来验证失败退出路径；该模式预期为 INCOMPLETE / 退出 1，不计为布局通过。五张内容缓存图为 `build/menu-retry-step-{13,27,31,37,39}.png`；缓存图不验证系统玻璃合成，此方法不是鼠标端到端验收，需允许图形会话 |
| 菜单栏倒计时原生专项 | 先运行 `./Tools/Previews/render-menu.sh --interactive`，再从根目录执行 `RADIOBAR_MENU_LABEL_AUTORUN=1 ./build/RadioBarMenuPreview.app/Contents/MacOS/MenuSnapshots`。用隔离偏好、生产标签与可控单调时钟，约 8 秒内比较两种名称模式的 18 组真实 NSStatusBarButton 状态，覆盖分钟、一位小时、两位小时格式；同一格式内宽度固定，画布超出实际内容不足 1 pt，并确认无比例文字标题、图片保持 template。报告 `build/menu-label-result.txt`，原生按钮缓存图 `build/menu-label-step-偶数.png`（2–36）；失败退出 1，不操作正式 App，不验证真实鼠标或直播声音 |
| `./Tools/Previews/render-station-sync.sh [输出目录]` | 默认 `build/station-sync-previews/`；编译正式单向发布卡片及确认 sheet，生成 48 张简繁中文／英文、浅深色的未设置／首次确认／替换确认／已发布／待发布／云端变化／损坏／停止状态图，不启动正式 App、无 iCloud／音频操作 |
| `./Tools/Previews/render-settings.sh` | 编译生产设置视图，复制 Info.plist/图标/许可证到测试资源 bundle；覆盖关于页、许可 sheet 的简繁中文/英文浅深色、正文末尾与资源缺失，及添加/编辑窗口及冲突提示、默认/自定义/仅内置台的列表与默认下拉、简繁中文/英文、浅深色和外观切换，图片输出 `build/settings-previews/` |
| `./Tools/Previews/render-app-icon.sh` | 先运行 `./build.sh`；从最终 ZIP 解压并严格验签，经 macOS 图标服务输出 64/128/256 像素图片到 `build/app-icon-previews/` |

菜单/设置预览使用 `RADIOBAR_TESTING` 排除真实更新组件。检查相关中英文与浅深色图片及脚本断言；生成成功不等于人工检查，更不等于鼠标/键盘交互验收。不要修改 `build/` 中生成的 Swift 来修复产品问题，应修改生产源码或对应预览工具。README 的入库图片在 `docs/images/`，不会随预览自动更新，只有需要更新 README 时才选取相应图片替换。

### 资源、SDK 与更新交付辅助工具

| 入口/配置 | 用法与副作用 |
|---|---|
| `./Tools/make-icons.sh` | 读取 `Artwork/AppIcon.png`，生成 `build/RadioBar.iconset/` 等中间文件并更新入库资源 `Resources/RadioBar.icns`；不能只预览母图就交付 |
| `./Tools/fetch-sparkle.sh` | 由构建/签名工具按需调用；校验固定 SHA-256 的 SDK 压缩包，再重新解压到 `build/Sparkle-版本/`，不使用未经验证的旧解压目录 |
| `Tools/sparkle-config.sh` | 供脚本从根目录 `source` 的版本、摘要及 SDK 路径配置，不是独立测试入口；改 Sparkle 版本时还要同步 Package.swift、Xcode 引用与许可证 |
| `./Tools/sign-release.sh` | 先构建 ZIP；使用专用钥匙串密钥或环境变量 `SPARKLE_PRIVATE_KEY`，重建 `build/updates/`，从内置当前版本日志生成默认/简体/繁体/英文四份带说明的 feed，逐份签名并独立验证 feed/ZIP，编译 `build/PrepareUpdateNotes` 与 `build/VerifyUpdate`；本命令不上传或发布 |
| `./Tools/configure-update-secret.sh` | 可选的一次性远端配置工具，需已认证 GitHub CLI 和本机专用更新密钥，会写入 Repository Secret。用户已通过网页完成配置，日常构建/测试无需运行或安装 gh，不要重复生成密钥 |

正式发布由 `.github/workflows/release.yml` 调用现有构建/签名工具，另调用 `Tools/check-release-order.py` 校验 Release 顺序。tag、Secret、签名和发布流程见 [HANDOFF 第 8 节](HANDOFF.md#8-构建验证与交付)。交付 ZIP 解压后再运行 `codesign --verify --deep --strict /实际解压位置/RadioBar.app`，App 的 ad-hoc 签名与 Sparkle 的 EdDSA 更新签名分别验证。

### 修改工具时到哪里找实现

| 工具类型 | 对应源码（相对仓库根目录） |
|---|---|
| 离线与原生专项 | `Tests/*.swift`；本地 AVPlayer 专项另用 `Tools/NativeAudioTransitionProbe.swift` |
| 菜单预览 | `Tools/PrepareMenuPreview.py` 提取生产视图，组合 `Tools/RenderMenu.swift`；仅生成副本供预览 |
| 设置/图标预览 | `Tools/RenderSettings.swift`、`Tools/RenderAppIcon.swift` |
| 图标生成 | `Tools/MakeAppIcon.swift`；`iconutil` 不可用时由 `Tools/pack-icns.py` 回退打包 |
| 直播探测 | `Tools/PlaybackProbe.swift`，通过 `Tools/Tests/test-playback.sh` 编译运行；`test.sh` 的联网参数也复用此入口 |
| 更新验证 | `Tools/PrepareUpdateNotes.swift`、`Tools/VerifyUpdate.swift`、`Tests/SparkleProbe.swift`、`Tools/serve-update-fixtures.py` |
| 发布顺序 | `Tools/check-release-order.py`；独立回归 `python3 Tests/ReleaseOrderTests.py`，也由更新专项调用 |

这些辅助实现优先通过已有入口使用。新增生产源码时检查 Xcode Sources、`build.sh` 与显式列举源文件的测试脚本；移动工具或变更参数后更新本索引及所有调用方。`build/` 是可重新生成的产物目录，不入库；不要为文档更新生成重复历史附件。

## 必须区分的验证范围与剩余项

- 编译、离线逻辑、原生静音解码、离屏 UI、联网解码和真实交互／出声分别报告。HTTP 200、ready、模拟回调或截图不能代替播放时间推进、鼠标端到端或持续收听。
- 原生拖放专项使用真实视图和回调，载荷读取及 OS 事件有适配；真实鼠标拖放／取消／重启持久化、菜单桌面材质、Dock／键盘交互按变更范围另验。
- 全部电台及主备线路、长时间收听、断网恢复、睡眠唤醒和登录启动尚未完整覆盖；新台响度差异先记录组合及发生阶段，不擅自改增益。
- Mac → iPhone 的真实 iCloud 到达、权限撤销、离线缓存和设备播放仍需双端联调。本地文件夹模拟不能证明云端到达。
- 同名新仓库的 Secrets、Actions、发布附件、2.0 安装升级和实际后台更新须在后续获准重建／发布后验证。本轮不读取／导出私钥，不修改远端或服务器。
- 沙箱可能限制 SwiftUI 宏、原生文件协调、图形服务或回环监听；缺少许可时记录阻塞阶段，在相应允许环境复验，避免修改无关生产逻辑。
- 全新 Git 首次提交的全量 diff 检查曾发现第三方 Sparkle 许可证尾空格及 ChannelReordering 文件末空行；它们沿用原文件，本轮不清洗第三方许可证或无关生产代码。已修改文档保持无新增空白问题。
