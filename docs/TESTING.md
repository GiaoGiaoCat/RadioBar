# 验证入口与当前覆盖

本文维护可执行入口、最新结果和验收缺口；旧逐次版本流水账已合并，完整记录保存在本地被 Git 忽略的重建前源码备份中。版本说明见 [CHANGELOG](../CHANGELOG.md)，当前状态见 [HANDOFF](HANDOFF.md)。

## 2.0.7（114）本地验证

仅在共用菜单行按钮上关闭默认焦点视觉效果，保留焦点能力及原有键盘路由，菜单布局、悬停背景、原生材质和设置窗口生命周期不变。本地验证已完成；用户已授权提交并推送 `main` 及 `v2.0.7`，仅确认 Actions 触发，不等待后续结果或执行发布后验收，安装由用户自行完成。

- 当前源码重新运行生产原生菜单专项，36 项通过、0 项失败，日志 `build/menu-focus-native.log`、报告 `build/native-menu-result.txt`；覆盖既有按键、四种列表数量、三语浅深／系统、24 pt 行高、上下 9／5 pt、顶部外部间隙 1 pt 及音量／倒计时。
- 隔离焦点探针使用当前提取视图与生产 `NativeMenuBar`，只增加不绘制、不接收输入的观察视图。记录 `build/menu-focus-after/result.txt`：设置打开且原生菜单为 key 时，首行仍 `isFocused=true`，所有整行按钮 `isFocusEffectEnabled=false`。简中深色、英文浅色、繁中深色及设置关闭状态的缓存图均未见蓝框；当前电台移到第三项时勾选正常。缓存只检查内容，不能证明桌面材质或物理键盘端到端操作。
- 未激活状态的菜单缓存与修复前对应图片字节相同；激活状态的菜单缓存与诊断阶段临时清除第一响应者后的无框图片也字节相同，记录 `build/menu-focus-after/pixel-comparison.json`。产品修复没有清除焦点；与后者的比较仅用于确认去框后的内容未发生额外变化。
- 菜单参考预览 81 张与 2.0.6 对应图片全部字节相同，涵盖原有三语、播放状态和悬停效果，现有几何及受控宿主检查通过；日志 `build/menu-focus-previews.log`、比对 `build/menu-focus-preview-comparison.json`。设置预览 127 张完成，实际查看三语浅深色六张展开日志图，2.0.7（114）与当前版本标记完整；日志 `build/menu-focus-settings.log`。
- 正式构建通过，日志 `build/menu-focus-build.log`；最终 ZIP 独立解压后严格 deep codesign、版本 2.0.7／114、arm64、Info.plist、默认电台及加密资源核对通过，除版本外的 Info.plist 与 HEAD 一致，记录 `build/menu-focus-zip-verification.json`。仍为 ad-hoc 签名、未公证。未改播放／配置／Dock 逻辑，未重复完整音频、联网及长期播放回归；未安装。

## 2.0.6（113）本地验证

用户确认原生菜单预览后授权正式实现，要求保留文字行高及内部间距。生产改用 `NativeMenuBar` / NSMenu 承载原 SwiftUI 内容；本地验证已完成。用户已授权提交并推送 `main` 及 `v2.0.6`，仅确认 Actions 触发，不等待后续结果或执行发布后验收，安装由用户自行完成。

- 生产原生菜单专项 36 项通过，日志 `build/native-menu-test.log`、报告 `build/native-menu-result.txt`。实际状态栏按钮呈现单台／五台／七台／十二台，三语浅深／系统共七组外观；检查 24 pt 行高、上下内容边界 9／5 pt、总高度 232／328／376／496 pt、顶部外部间隙 1 pt。记录的是当前系统实测几何，不是生产硬编码尺寸。
- 原生 AppKit 应用内按键事件验证空格、⌘R 和 ⌘,；播放／重连保持菜单打开，设置先关闭菜单且打开生产设置窗口。本机激活的参考窗口与原生菜单中，合成鼠标事件均能操作原有静音按钮；滑块更新音量且菜单保持打开。十八组真实状态栏模板图在菜单持续打开期间覆盖两种名称模式和分钟／一位小时／两位小时格式，同格式宽度稳定、实际内容宽度匹配。⌘Q 命令映射检查，不在该进程内执行退出以免截断报告。
- 当前内容参考预览 81 张、108 组自然高度／边界及旧弹窗受控模型 19 项通过；`build/native-menu-previews/` 全部 81 张与已确认前的对应图片字节相同，记录 `build/native-menu-pixel-comparison.json`。实际查看简／繁／英文浅深色六张单台图；参考图只证明内容排版，不证明原生菜单桌面材质。
- 正式构建通过，日志 `build/native-menu-build.log`；最终 ZIP 独立解压后严格 deep codesign、2.0.6／113、arm64、完整 Info.plist、默认电台及加密资源核对通过，除版本外的 Info.plist 与原提交一致，记录 `build/native-menu-zip-verification.json`。仍为 ad-hoc 签名，未公证。
- 设置预览 127 张通过，日志 `build/native-menu-settings.log`、图片 `build/native-menu-settings/`；实际查看三语浅深色六张展开日志图，2.0.6（113）及当前版本标记完整。Dock 六组、原生拖放七组通过，日志 `build/native-menu-dock.log`、`build/native-menu-drops.log`。
- CUA 使用当前生产控制器的隔离 App，通过生产设置开关 7→1→7、关闭设置、控制窗口调用原生状态栏按钮重开；同期几何 `build/native-menu-cua-one.txt` 与 `build/native-menu-cua-seven.txt` 显示 256×232／376、上下 9／5 pt、外部间隙 1 pt，菜单栏按钮宽度仍为 34 pt。展开菜单后发送 ⌘Q，工具确认隔离 App 已退出，未安装或替换正式 App。
- 单窗口截图不能同时包含菜单栏、菜单及背景，内容缓存也不包含系统材质合成；桌面通透效果沿用用户确认的预览。CUA 控制窗口的按钮不是直接点击系统状态栏图标；合成事件、参考图与界面操作不证明真实 VoiceOver、直播音频或长期播放。未改播放算法／配置持久化，未重复完整音频或联网回归。

## 2.0.5（112）本地验证

用户在 2.0.4 再次报告多台隐藏至一台后窗口错位、退出重开恢复。本轮用菜单自然测量结果同步原生窗口尺寸，保留配色、材质与布局。未在隔离原生菜单中自然复现用户现象，以下区分受控模型和原生呈现流程。

- 受控宿主模型 19 项通过：普通 NSWindow 的 NSHostingView 关闭自动尺寸传播，只在初始七台时设置一次窗口尺寸，随后逐台执行 7→1→7→1；窗口、内容与上下边界均随自然高度更新。报告 `build/short-list-menu/cached-host-size-result.txt`。以同一最终测试重新编译 Git `458e4be` 的菜单源码，2 项通过、17 项失败，预期退出 1；一台内容仍居中在 376 pt 旧窗口中。基线报告 `build/short-list-controlled-baseline/previews/cached-host-size-result.txt`。该模型验证恢复能力，不是原生 MenuBarExtra 自然重现；普通 NSWindow 的位置不作为菜单定位断言。
- 新原生短列表专项 7 项通过，日志 `build/short-list-native.log`，报告及完整几何在 `build/short-list-native/`。呈现与关闭均经真实 NSStatusBarButton 方法，生产设置窗口开关、逐台隐藏和恢复后再次展开；四次菜单检查包含高度、上下边界和相对菜单栏按钮的顶部间距，均保持初始 2 pt。没有用 orderOut / makeKeyAndOrderFront 绕过该流程；仍是自动原生动作，不是物理鼠标点击。菜单外观专项 15 项通过，日志 `build/short-list-appearance.log`，报告 `build/menu-appearance-result.txt`。
- 菜单预览 81 张、原有 108 组自然高度及边界检查通过，图片 `build/short-list-menu/`、日志 `build/short-list-menu.log`；全部 81 张与旧菜单源码对应图片字节相同，记录 `build/short-list-pixel-comparison.json`。实际查看英文深色／简体浅色的一台菜单和繁体深色五台菜单，离屏背景仅验证内容布局。
- 设置预览 127 张通过，日志 `build/short-list-settings.log`、图片 `build/short-list-settings/`；实际查看三语浅深色六张展开日志图，2.0.5（112）及当前版本标记完整。正式构建通过，日志 `build/short-list-build.log`；从最终 ZIP 用 ditto 独立解压，严格 deep codesign、arm64、完整 Info.plist、默认电台与密文资源检查通过，记录 `build/short-list-zip-verification.json`、`build/short-list-codesign.log`。仍为 ad-hoc 签名，未公证。
- 用户解锁后补充 CUA 界面交互：同一隔离进程内实际操作生产设置开关，逐台执行 7→1→7→1、关闭设置并重开菜单；另确认七台原生菜单隐藏后，坐标点击六个开关缩至一台、坐标关闭设置并重新展开。九份同期几何及汇总在 `build/short-list-mouse/`：七台 256×376、一台 256×232，内容／背景／呈现层匹配，上下边界 9／5 pt，菜单顶部相对按钮始终 2 pt。实际查看系统深色及生产设置切浅色后的一台／七台菜单，无灰条、错位或裁切；全程未重启，结束后从菜单退出测试 App。
- 菜单呈现由测试控制窗口调用真实 NSStatusBarButton，未将其称为直接鼠标点击系统状态栏图标。用户旧版异常未在隔离原生菜单中自然重现，实际安装版及肉眼偏暗仍由用户复验。未修改播放／配置／偏好或设置窗口的生产生命周期，未重复完整音频、联网与 Dock 回归；提交、推送 `main` 与 `v2.0.5` 及正式发布已按授权完成，安装更新由用户自行完成。
- 正式发布 Actions `39994736057` 成功，标签固定修复提交 `8abee1e`；六份公开附件下载核对通过。新编译 `VerifyRelease205Update` 验证四份 feed 与实际 ZIP 的 EdDSA 签名，三语说明与当前源码生成的期望精确一致，latest feed 与标签版本逐字节相同。实际 ZIP 的 checksum／GitHub 摘要、严格 deep codesign、完整 Info.plist、2.0.5／112、arm64 和资源通过；记录 `build/published-v2.0.5/verification.json`、`signatures.log`、`codesign.log`。未读取或替换私钥，未安装更新。

## 2.0.4（111）本轮验证

补全共享外观桥接的生命周期核对：菜单重开／成为 key、App 激活及宿主窗口 appearance 变化后，按最新选择恢复原生窗口并同步 SwiftUI；系统模式清除显式覆盖。保持 `.menu / .behindWindow / .active`、配色、布局及 Dock 策略。

- 原生菜单外观专项 15 项通过，报告 `build/menu-appearance-result.txt`，执行日志 `build/appearance-native.log`。覆盖菜单隐藏期间切浅深／系统、隔离 NSApp 外观变化、生产设置窗口切外观后关闭再展开、同色／异色宿主覆盖注入；同时核对窗口、材质、SwiftUI colorScheme、窗口复用、几何及输入穿透。异常注入仅是防回归测试，不代表重现用户肉眼偏暗。
- 用 Git 中修复前的 SettingsView 源码与同一专项重新编译基线，15 项中 8 项通过、7 项失败，预期退出 1；包含同色系统覆盖未释放、之后无法跟随隔离 App 外观变化。基线报告 `build/appearance-baseline/menu-appearance-result.txt`，日志 `build/appearance-baseline.log`，编译日志 `build/appearance-baseline-compile.log`。生产源码未替换，未用旧二进制作当前验证。
- 原菜单专项 17 项通过，系统模式已从跳过检查改为同时验证 nil 覆盖与继承 App 外观，日志 `build/appearance-menu-layout.log`。菜单预览 81 张及 108 组尺寸／边界检查通过，图片 `build/appearance-menu/`、日志 `build/appearance-menu.log`；12 张三语浅深色的完整／五台列表 PNG 与 2.0.3 对应图片字节完全相同，并实际查看英文深色、简体浅色及繁体深色。汇总 `build/appearance-verification.json`。
- 设置预览 127 张通过，图片 `build/appearance-settings/`、日志 `build/appearance-settings.log`；沿用四组浅→系统→深→系统的原生／内容像素断言及隔离系统变化检查，实际查看中英文切换图及繁体深色。Dock 生命周期六组检查通过，日志 `build/appearance-dock.log`，保留原窗口复用与激活策略。
- `./build.sh` 正式构建通过，日志 `build/appearance-build.log`；最终 ZIP 独立解压后严格 deep codesign、完整 Info.plist、2.0.4／111、arm64、macOS 14、默认电台资源及密文资源检查通过，除版本外的 Info.plist 与 Git 原值一致。记录 `build/appearance-zip-verification.json`、`build/appearance-codesign.log`，仍为 ad-hoc 签名、未公证。
- 发布前将短列表与外观修复合并到 2.0.4 双语更新说明，并重新构建、从最终 ZIP 解压严格验签；日志 `build/v2.0.4-release-build.log`，记录 `build/v2.0.4-release-zip-verification.json`、`build/v2.0.4-release-codesign.log`。最终包版本 2.0.4／111，元数据及默认电台资源一致，包含合并说明。设置预览再次生成 127 张，图片 `build/v2.0.4-release-settings/`、日志 `build/v2.0.4-release-settings.log`；实际查看三语浅深色六张展开日志图，说明完整、当前版本标记正确。
- 已按授权提交、推送 `main` 与 `v2.0.4`，Actions 与正式发布确认成功，实际附件、更新签名及最终 ZIP 已核对，见 HANDOFF；安装更新由用户自行完成。未重复完整音频／联网回归；缓存图片不验证桌面玻璃合成，用户此前肉眼偏暗、截图正常的现象仍需实际复验。用户后续再次报告短列表错位，不能以本节检查视为完整验收，后续处理见 2.0.5。

## 2.0.3（110）验证记录

本轮仅修改菜单场景对设置变化的观察及可见电台集合对应的内容身份，使原生菜单重新测量自然高度；不设置窗口尺寸或位置，播放、配置、偏好存储和背景材质不变。

- 在用户原安装版的诊断页读到：5 个可见电台时窗口仍为 256×424 pt，内容原点为 y=48 pt；与截图中 328 pt 内容上下各空 48 pt 一致。隔离自动预览未稳定重现该旧缓存状态，不能将其旧实现下的几何通过当作截图问题不存在。
- 菜单预览重新编译通过：`build/menu-size-previews/` 共 81 张，日志 `build/menu-size-previews.log`；三语 × 12／7／5／1 个电台 × 9 种播放状态共 108 组尺寸和上下边界断言通过。实际查看 1 个及 5 个电台的三语浅深色共 12 张图片，无额外上下留白或截断。离屏实色背景仅验证布局。
- 原生隔离菜单回归通过：17 项窗口／呈现图层尺寸、边界、外观、背景覆盖及输入穿透检查，包含隐藏期间在 12→5→1→12→5→7 个电台间变化后重新显示；5 个电台为 328 pt、1 个为 232 pt。日志 `build/menu-size-native.log`，报告 `build/menu-size-native-result.txt` 和 `build/menu-size-native-diagnostics.txt`，缓存图为 `build/menu-retry-step-{45,49,53,57,61,65}.png`。模拟播放、原生窗口方法及内容缓存图不等于鼠标端到端或桌面玻璃合成验收。
- `./build.sh` 正式构建通过，日志 `build/menu-size-build.log`。从最终 ZIP 独立解压后，严格 deep codesign、完整 Info.plist、2.0.3／110、arm64、macOS 14、默认 JSON 一致及密文资源存在／明文资源缺失检查通过；记录 `build/menu-size-zip-verification.json`、`build/menu-size-codesign.log`。仍为 ad-hoc 签名、未公证。
- 该本地版本未独立打标签或发布，修复随 2.0.4 一并交付，未运行直播／音频专项。用户后续自行安装，已确认短列表上下灰色空白修复生效；之后报告的肉眼偏暗、截图正常在退出重开 RadioBar 后恢复，具体根因尚未确定。

## 2.0.2（109）验证记录

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

预览脚本均重新编译对应工具，需可用的 macOS 图形服务。可选第一个参数为输出目录，例如 `./Tools/Previews/render-menu.sh build/menu-review`；相对路径按仓库根目录解析。

| 可执行入口 | 输入与默认输出 |
|---|---|
| `./Tools/Previews/render-menu.sh` | 从生产菜单提取保留 2.0.5 外层留白的内容参考副本，需 Python 3；含播放状态切换、12／7／5／1 个电台的自然尺寸及上下边界断言，生成 81 张图片；另用关闭宿主自动尺寸传播的普通 NSWindow 逐台验证 7→1→7→1 的 19 项尺寸恢复，报告 `cached-host-size-result.txt`，失败退出 1。图片及报告默认在 `build/menu-previews/`，生成 Swift 在 `build/`。编译后可用 `RADIOBAR_MENU_CACHED_HOST_ONLY=1 ./build/MenuSnapshots 输出目录` 单跑受控模型；该模型只验证旧弹窗参考桥接，不验证当前原生菜单控制器 |
| `./Tools/Previews/render-menu.sh --interactive` | 编译并组装 `build/RadioBarMenuPreview.app`，使用生产 `NativeMenuBar` 与菜单内容、7 个电台和隔离偏好；自动显示生产电台设置及 `Toggle menu` / `Open settings` 控制窗口。播放约 2 秒后模拟 Playing，无直播音频。Preview Appearance 菜单提供浅／深／系统，生产设置可切换三语、显隐、Dock 等；不操作正式配置。几何写入 `build/menu-live-diagnostics.txt`。需要解锁的图形会话，真实桌面材质与交互应在此模式查看 |
| `./Tools/Tests/test-native-menu.sh` | 独立编译生产原生菜单控制器及提取的内容，使用实际 NSStatusBarButton 呈现、AppKit 应用内事件与隔离偏好；核对单台／五台／七台／十二台、三语浅深／系统、24 pt 行高及上下边界、原生顶部间距、现有按键、音量、设置与倒计时标签。报告 `build/native-menu-result.txt`，失败退出 1；无直播音频，不等于物理鼠标或桌面材质合成验收。`RADIOBAR_NATIVE_MENU_VOLUME_ONLY=1` 只跑开头的音量／空格路径，供开发定位 |
| `./Tools/Previews/render-menu.sh --surface` | 保留 2.0.5 SwiftUI 弹窗与已确认原生候选、标准 NSMenu 的比较工具，三语、浅深／系统、单台／七台可切换。彩色背景仅为观察通透度，几何写入 `build/menu-surface-geometry.txt`。该参考模式不使用完整生产菜单控制器，不能替代上一项专项；再次编译 `--interactive` 回到生产隔离模式 |
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
| 菜单预览与原生专项 | `Tools/PrepareMenuPreview.py` 提取生产视图，组合 `Tools/RenderMenu.swift` 或 `Tests/NativeMenuTests.swift`；生产控制器直接编译 `NativeMenuBar.swift` |
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
