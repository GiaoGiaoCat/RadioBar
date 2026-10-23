# RadioBar 开发交接

更新日期：2026-10-24（Asia/Shanghai）。当前源码 **2.0.5（112）** 已正式发布：按菜单内容自然测量结果同步复用原生窗口尺寸，保持现有配色、材质、布局和系统默认顶部间距。此前用户报告隐藏到一台时菜单错位、退出重开恢复；本地受控模型、原生按钮生命周期、预览及构建验签已通过，解锁后也已补 CUA 生产设置开关、关闭设置、菜单重新呈现及隐藏期间 7→1 的交互核对，浅深色均未见错位或灰条。隔离测试未自然重现旧版异常，根因未完全确认。修复提交 `8abee1e` 与 `v2.0.5` 已按授权推送，Actions、正式 Release 和实际发布附件核对通过；安装更新由用户自行完成。继续开发前核对 `Resources/Info.plist`、Git 状态与实际 diff，验证范围见 TESTING。

## 1. 工作入口与新仓库状态

用户指定同名重建并从 2.0.0 开始维护。当前 `/Users/victor/Github/RadioBar` 使用全新 Git，`main` 以无父提交的 2.0.0 初始化版本为基线，`origin` 为 `git@github.com:GiaoGiaoCat/RadioBar.git`。2.0.4 修复提交为 `458e4be`，包含未独立发布的 2.0.3 验证阶段；2.0.5 修复提交为 `8abee1e`，`v2.0.5` 固定指向该提交。两次提交、标签推送及正式发布均已按授权完成，用户自行安装。不再执行远端删除或重建。重建过程见 [REPOSITORY_REBUILD](REPOSITORY_REBUILD.md)。

重建前源码和完整旧 Git 仅备份一份，位于被忽略的 `private/repository-rebuild-20261023-154311/RadioBar-before-reinit/`。其他五个旧工作目录（含有未提交工作的 iOS 工程）仍关联此备份；已修复指针并核对内容。不要删除／移动备份或从旧目录向同名新仓库推送旧历史。`private/` 不进入首次提交；完整 1.x 文档也在该备份中，新仓库不再保留开发流水账。

文档分工：README 是用户入口；BUILD 维护源码编译方法；AGENTS 是工作规则；本文件维护当前状态、代码地图和未选需求；UI_GUIDELINES / STATIONS 是业务规范；TESTING 是验证入口、最近结果及缺口；CHANGELOG 和 App 内双语日志维护 2.0 起的发布说明与简要阶段汇总。

## 2. 当前产品

- 原生 SwiftUI / AppKit / AVPlayer 菜单栏电台 App，Apple Silicon、macOS 14+；bundle ID `local.victor.RadioBar`。提供 Xcode 工程和 Package.swift，正式 ZIP 由 `./build.sh` 装配。
- 默认 12 个电台，KISS / 央广为内置台，只能隐藏和排序；10 个普通台由默认／用户 JSON 管理，可添加、编辑、删除、显示或隐藏。至少保留一个显示台，变更配置或显示不擅自中断当前播放。
- 全台统一使用有序固定线路，不进行 TingFM / KISS 客户端动态取址、到期推导或计划刷新。失败沿用四次重试、2/4/8/16 秒退避；单线路重试原地址，多线路依次轮换。
- 支持独立静音、音量、2.5 秒柔和切台（先 0.8 秒淡出、静音间隔 0.5 秒、再 1.2 秒淡入，不叠音）、1–720 分钟睡眠倒计时和 6 秒睡眠渐弱；菜单栏计时按当前格式绘制，不预留小时位。默认静态天线，可选慢动画。
- 支持上次／固定／随机启动、独立启动自动播放及登录启动设置；简体／通用繁体／英文和系统语言，浅／深／系统外观。设置窗口期间显示 Dock，可选常驻，重开复用页面。
- 单台 Mac 管理并发布 v2 `RadioBarSync/current.json`，iPhone 只读；旧关联需重新确认，旧已确认事务先恢复。新版 JSON 备份保留最近五次，旧备份和恢复材料保留。两端协议见 [IPHONE_SYNC_SIMPLIFICATION](IPHONE_SYNC_SIMPLIFICATION.md)。
- 关于页提供原生签名更新、版本复制和离线许可证；诊断仅保留有界脱敏内存记录。2.0 将旧更新记录按能力合并，保留现有界面和用户偏好。

## 3. 内置地址与本机私有资料

`./build.sh` 从成对环境变量 `KISS_STREAM_URL` / `CNR_STREAM_URL`（优先）或被忽略的 `private/builtin-streams.json`（0600）读取完整输入。Actions 继续只需要原有两个地址 Secrets，禁止本地回退。

生成器每次使用独立随机 AES-256 密钥和 GCM nonce，加密原始 JSON；密钥随机置换并用随机掩码拆分，生成 `BuiltinStreamKey.swift`。密文 `builtin-streams.bin` 与源码在独占生成目录中成对原子更新，失败保留前一组；生成目录含其他文件则拒绝覆盖。CLT 构建在临时目录生成并清理，Xcode 在编译前写入 DerivedSources，SwiftPM 按 [源码编译指南](BUILD.md) 预生成被忽略的 `Sources/RadioBar/Generated/`。只有密文进入资源，密钥材料编入程序，生成源码不打包、不提交。

App 使用 CryptoKit 校验版本头和 GCM 认证后在内存解密，保持完整查询参数与线路顺序；缺失、损坏、篡改、错配均返回空地址，不回退明文或开发者文件。离线测试／预览不需要私有输入或生成密钥，联网专项另行打包真实配对产物。诊断继续脱敏；旧交接输入仅供本地追溯。

此方案提高解压／文本搜索的提取门槛，不能防止逆向或运行时提取；旧源码、安装包和缓存中的明文不会失效。地址加密与 Sparkle 私钥无关，不增加远端 Secret，不修改 RadioRelay／服务器或轮换凭据。

## 4. 代码地图

| 文件（均相对 Sources/RadioBar） | 责任与注意点 |
|---|---|
| RadioBarApp.swift | App 入口、单实例锁、菜单内容、静音/滑块、现有快捷键 |
| RadioPlayer.swift | 主线程播放协调、取消与 generation、防迟到结果、两路 Deck、过渡/重试/睡眠停止 |
| AudioPlayback.swift | 可注入播放接口及真正 NativeAudioPlayback/AVPlayer，测试使用假传输 |
| StationCatalog.swift | Station 数据模型、两个内置台、JSON 校验/初始化/启动加载/手动加载候选与发布、内置 ID 偏好迁移；普通台由 JSON 提供，按 ID 相等 |
| BuiltinStreams.swift | 内置私有资源解码及打包加载；离线测试使用假地址，正式 App 只读包内资源 |
| StreamResolver.swift | 全台统一固定列表选址、取消检查及独立的线路位置/重试预算 |
| AppLanguage.swift | RadioText 简体/通用繁体/英文、菜单名/完整名/分类风格与错误翻译 |
| AppSettings.swift / PlaybackPreferences.swift | UserDefaults、登录项、启动快照、排序修复、统一有序可见集合 |
| SettingsView.swift | 设置侧栏/通用/播放/电台配置，窗口外观桥接、设置窗口生命周期与 Dock 策略、AppKit delegate |
| ChannelReordering.swift | AppKit 源手柄及原生接收行、纯会话预览、有效 drop 才提交 |
| SleepTimer.swift / SleepTimerView.swift | ContinuousClock 倒计时、唤醒刷新、倒计时 UI；运行中的期限不持久化 |
| RadioDiagnostics.swift / DiagnosticsView.swift | 有界内存事件、脱敏报告、复制/清空 |
| MenuBarSignal.swift | 默认静态两圈天线，可选 0/1/2 圈慢动画，支持减少动态效果 |
| AppUpdater.swift | 进程唯一 Sparkle 控制器，启动、检查按钮状态与按 App 语言选择更新源；离线预览不加载更新组件 |
| SingleInstanceLock.swift / ReleaseNotesView.swift | 实例文件锁；打包内置双语版本历史 |

不要重复维护一份播放源表：普通台资料和 URL 以默认/用户 JSON 为准，两个内置台资料在 StationCatalog，内置身份只控制管理权限，选址不分电台。新 ID 不再要求新增枚举或修改名称/地址 switch。

## 5. 播放及网络关键约束

- 新台 URL 解析、readyToPlay 或 HTTP 200 都不等于真正播放。只有 ready + playing + 时间推进才触发双路过渡。
- 切台依次执行淡出、静音、淡入：旧台在 0.8 秒内以原增益×cos(πs/2) 淡出，新台保持 gain=0；随后两路保持 gain=0 静音 0.5 秒；最后旧台保持 gain=0，新台在 1.2 秒内以 sin(πs/2) 淡入。淡入、淡出各段独立使用 p∈[0,1]、s=p²(3−2p)，起止斜率为零，不补偿交接处的静音。静音从旧台实际归零时计满 0.5 秒，回调延迟时总时长相应顺延，不跳过间隔。音量写入先归零另一台，不叠音；过渡完成释放旧实例。正常交接 2.5 秒，不含网络连接与缓冲。
- 新台失败时旧台保持；缓冲中断过渡时恢复旧台。重试 4 次，延迟 2/4/8/16 秒。所有电台随 sourceAttempt 顺序轮换固定主备，健康重置 retryCount 不应错误重置线路位置。
- 快速切台最多两路，保留较响且真正播放的实例；处于两路 gain=0 的静音间隔时，保留已经确认时间推进的新台。暂停、重连、睡眠和新选择必须取消过期任务/计时器，旧回调不能复活音频。
- 全台固定地址选址不访问取址网页、API 或 token 服务；不解析 URL 的 expires/time 等参数，不设置到期或 30 分钟刷新任务。正常 HLS 列表/分片刷新由 AVPlayer 管理。
- KISS 和央广地址按用户确认的数据内置，当前均为单线路，失败重试原地址；普通台继续使用默认/用户 JSON 的完整地址及顺序。多线路健康后失败继续下一条，不自动切回主线。
- 25 秒无进展处理和原有有界恢复由当前实现决定，不为“更快”随意缩短。ATS 仅必要主机例外。
- 静音门控独立于增益和保存音量，过渡中的新实例也要保持静音；定时渐弱不能把用户 volume 偏好写为 0。
- 诊断只保留本次运行 100 事件 / 64 KiB，不写持续日志文件。不输出完整播放 URL、token、HTTP 头或正文；保留尝试号、主备/线路索引和错误类别等脱敏信息。

## 6. 用户偏好与数据兼容

稳定 ID 当前为：

```text
builtin.kiss, builtin.music-radio, bcc, ufo, asiaFM, guangdong, shanghai,
loveRadio, classic947, radioParadise, grooveSalad, swissJazz
```

| UserDefaults 键 | 语义 |
|---|---|
| station | 上次实际选中的 Station ID |
| volume | 0–1 滑块值；默认 0.65；静音开关不持久化 |
| defaultStation | 固定 ID 或 random；缺省/移除键表示 lastListened |
| autoPlayOnLaunch | 启动自动播放，默认关闭 |
| stationOrderIDs | 自定义 ID 排列；忽略重复/未知，缺失/新台追加 |
| hiddenStationIDs | 隐藏 ID 列表；不改变播放会话 |
| stationVisibilityOverrides | 按稳定 ID 保存用户明确的显示/隐藏选择；优先于旧隐藏记录和 JSON defaultVisible，仅保存用户选择，不把 JSON 初始值固化为偏好 |
| appLanguage | system / chinese / traditionalChinese / english；旧值不变 |
| appAppearance | system / light / dark |
| menuBarDisplay | iconOnly / iconAndStation |
| alwaysShowDockIcon | 默认 false；true 始终显示 Dock，false 仅设置窗口打开期间显示 |
| animateMenuBarIcon | 默认 false；播放动画帧间隔 0.8 秒 |
| SUEnableAutomaticChecks | Sparkle 管理的自动检查偏好；未保存时取 Info.plist 的 true，用户取消后保留 false |
| showSleepTimerInMenuBar | 默认 true；只控制菜单栏剩余时间显示，独立于电台名称与计时运行状态 |
| sleepTimerMinutes | 输入时长，运行中的倒计时不跨 App 重启恢复 |

`kiss` → `builtin.kiss`、`musicRadio` → `builtin.music-radio` 自动迁移上述四项电台偏好；保留旧键和其余十台 ID。普通台的新 ID 建议 `custom.<分组>.<名称>`，禁止保留前缀 `builtin.`。

显示/随机/默认下拉从同一排序后的 visibleStations 派生。隐藏固定默认时改回上次收听；启动时上次已隐藏则选当前首个可见台。随机每次启动只抽一次，暂停/重连不重抽。恢复默认顺序只改排列，不改变隐藏、固定默认或当前播放。排序/改名不能重建稳定身份。

## 7. 界面与待验收方向

复用 [UI_GUIDELINES](UI_GUIDELINES.md) 的现有组件、尺寸、字重、快捷键、布局和反馈。电台列表的标题、说明、排序和添加共用卡片；设置提示按需显示；关于页保持居中布局与默认折叠日志。主菜单紧凑且状态切换保持自然高度，详细失败原因位于诊断页。

2.0.3 更新菜单场景观察和可见电台集合对应的内容身份，用户曾确认短列表灰色空白恢复；2.0.4 补全窗口重开／激活及原生外观覆盖变化后的同步。但用户在 2.0.4 再次报告隐藏到一台时错位、退出重开恢复，前次确认不能视为完整验收。旧诊断中 424 pt 窗口容纳 328 pt 内容、上下各空 48 pt 仍是历史证据，不代表本轮已自然复现。此前肉眼偏暗、截图正常也仅确认退出重开可恢复，未完全确认根因。

2.0.5 修复通过 background GeometryReader 测量最终 fixed-size 菜单内容，在测量变化及原生窗口挂接、重新显示、成为 key、resize 时异步核对，用公开 `setContentSize` 同步实际内容尺寸。目标按屏幕像素对齐；无屏幕或自然尺寸超出当前可见屏幕时不干预原生呈现，避免反复争抢尺寸。换窗和销毁取消旧回调。保留菜单材质、间距、行高、外观与 Dock 策略，不使用私有 API，不硬设窗口 origin；当前交互验证见 TESTING，实际安装版仍由用户复验。

直播源主观响度差异尚未确认为 bug。现有增益证据见 [volume-audit](evidence/volume-audit-1.0.47.txt)，不据此推断直播响度；保留现有曲线，不增加补偿。实机交互、长期播放和双端同步边界统一见 TESTING。

## 8. 构建、验证与交付

从仓库根目录按 [源码编译指南](BUILD.md) 准备私有输入后运行 `./build.sh`，产物为 `build/RadioBar-macOS-arm64.zip`。App 在普通临时目录装配并 ad-hoc 签名；交付前必须从最终 ZIP 解压并执行 `codesign --verify --deep --strict`。这不是 Developer ID 公证发布。

按 [TESTING](TESTING.md#按改动选择验证) 选择专项；完整离线入口是 `./test.sh`，不是 `swift test`。新增／移动生产源码同步 Xcode Sources 和显式测试清单。图形会话、宏插件、文件协调或回环服务受限时，报告实际通过的范围与环境边界。

用户指定初始化版本为 2.0.0，构建号延续为 107，不重置；后续默认递增 2.0.X 和构建号。当前源码为 2.0.5（112），已同步 Info.plist、双语日志与 CHANGELOG，并完成本地构建和最终 ZIP 验签；用户已授权提交、推送 `main` 及 `v2.0.5` 并由 Actions 发布，自行安装更新。2.0.4（111）已通过 `main` 提交 `458e4be` 与标签 `v2.0.4` 正式发布，包含未独立发布的 2.0.3 修复。此前 2.0.2 最终发布结果按用户要求由其自行核对。不要恢复旧标签或镜像推送旧 Git。

Actions 的 tag 工作流校验版本、构建、解压验签、生成校验文件与四份签名 appcast，上传草稿后再正式发布。使用自动 `GITHUB_TOKEN` 和以下三个 Repository Secrets，无需额外 PAT：

- `KISS_STREAM_URL`、`CNR_STREAM_URL`：完整固定地址。
- `SPARKLE_PRIVATE_KEY`：原更新私钥，本机登录钥匙串 account 为 `local.victor.RadioBar`；对应公钥保留在 Info.plist。旧仓库 Secret 不可读回，同名新仓库需重新配置。不要输出、提交、重新生成或擅自更换密钥。

更新组件仍为 Sparkle 2.10.0；生产源为 `https://github.com/GiaoGiaoCat/RadioBar/releases/latest/download/appcast.xml` 及语言变体。签名验证涵盖 feed、说明及 ZIP。按需运行本地签名／更新专项，配置远端 Secret 不是日常测试步骤。推送成功不代表 Actions 或发布成功；交付需核对远端附件和更新源。已确认 [v2.0.5 Actions](https://github.com/GiaoGiaoCat/RadioBar/actions/runs/39994736057) 成功、[正式 Release](https://github.com/GiaoGiaoCat/RadioBar/releases/tag/v2.0.5) 于 2026-10-24 01:25:53（Asia/Shanghai）发布，为 latest 且非草稿。六份附件齐全；实际 ZIP 为 3,065,980 字节，SHA-256 为 `7ecb8c6211bb7220c4ba4e2ddec634f4e818445824a798ab1e1f21c6ccbe16d5`。四份 feed／ZIP 公钥签名、latest 与标签 feed 一致、当前三语说明、最终 ZIP 严格 deep codesign、版本／资源均通过，证据 `build/published-v2.0.5/verification.json`；仍为 ad-hoc 签名、未公证。安装更新由用户自行完成；此前 `v2.0.2` 最终结果由用户自行核对。

## 9. 当前验证与限制

测试、构建、资源注入和真实播放范围见 [TESTING](TESTING.md)。2.0.5 受控宿主恢复模型 19 项、原生按钮短列表流程 7 项、外观专项 15 项通过；菜单 81 张图片与旧源码对应输出完全一致，原有 108 组边界检查及设置 127 张预览通过，正式 ZIP 严格 deep codesign 和元数据／资源校验通过。旧菜单源码在受控模型同测有 17 项失败，该模型不是原生 MenuBarExtra 自然重现。解锁后的 CUA 补查生产设置逐台隐藏／显示、关闭窗口和原生菜单重开，并明确在菜单隐藏期间点击开关缩至一台；浅深色截图及九份同期几何均正常，全程未重启，证据 `build/short-list-mouse/`。菜单呈现由测试控制窗口调用原生状态栏按钮，未直接鼠标点击系统状态栏图标。实际安装版及肉眼偏暗仍由用户复验，旧版异常根因未完全确认。2.0.4 的旧结果不能代替本轮验证。

2.0.2 加密及 2.0.1 切台逻辑未因本轮修改而变化，不据此扩展为已验证本轮切台听感、全部电台、长时间稳定性、真实鼠标或双端同步。iPhone 需求文档中的 8 秒行为仍描述其原有基线，本轮未修改 iPhone 工作目录。

## 10. 未选定需求

以下需用户另选目标，不自动执行：

- 独立“参与随机”及空候选处理；收藏、线路信息与手动切换的交互规则。
- 地址验证／试播、JSON 导入导出及明确的合并／替换预览。
- 错误反馈、编辑填写说明和睡眠预设的交互优化。
- Developer ID／公证；真实后台更新、失败取消重试和当前 2.0 安装升级验收。
- 与 iPhone v2 读取端真实联调；本轮不修改其工作目录，不代发消息，不重新引入已取消的多 Mac 历史管理或同步诊断方案。
