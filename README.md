<h1 align="center">RadioBar</h1>

<p align="center">把电台放进 Mac 菜单栏，随手打开，安心听歌。</p>

<p align="center">
  <img alt="macOS 14 及以上" src="https://img.shields.io/badge/macOS-14%2B-555555?style=flat-square">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple_Silicon-arm64-555555?style=flat-square">
  <a href="https://github.com/GiaoGiaoCat/RadioBar/releases/latest"><img alt="下载最新版本" src="https://img.shields.io/github/v/release/GiaoGiaoCat/RadioBar?label=%E7%89%88%E6%9C%AC&amp;style=flat-square&amp;color=58786a"></a>
</p>

<p align="center">
  <img src="docs/images/menu-light.png" width="256" height="496" alt="RadioBar 中文浅色主菜单：12 个默认电台、播放控制、音量与睡眠定时入口">
  &nbsp;&nbsp;
  <img src="docs/images/menu-dark.png" width="256" height="496" alt="RadioBar 中文深色主菜单：12 个默认电台、播放控制、音量与睡眠定时入口">
</p>
<p align="center"><sub>浅色 / 深色 · 基于当前源码生成的界面预览</sub></p>

当前源码从 **2.0.0** 开始维护，合并此前版本的功能与更新记录；现有用户配置和偏好继续保留。

## 想做什么

一个自用的小项目：让收听电台变得简单，在工作、阅读或放空时，留一点音乐陪伴。使用原生 SwiftUI / AppKit / AVPlayer，选台与播放控制都在菜单栏完成。

- **打开就听**：默认提供 12 个电台，包括台湾中广、飞碟、广东音乐之声、动感101、Radio Paradise 等。
- **听得舒服**：2.5 秒柔和切台，先淡出、静音间隔 0.5 秒再淡入，避免两个电台声音重叠；支持独立静音与音量控制，连接异常时自动重试并轮换主备地址。
- **管理自己的电台**：在设置中添加、编辑、删除普通电台，拖动排序、显示或隐藏；保存前自动备份配置。
- **按习惯启动**：从上次收听、固定电台或随机电台开始，启动自动播放与开机自启动可分别设置。
- **定时休息**：支持 1–720 分钟睡眠定时，菜单栏可显示剩余时间，到点用 6 秒渐弱停止。
- **融入 Mac**：跟随系统或指定浅色 / 深色外观，支持简体中文、繁體中文与 English；菜单栏可显示电台名和播放动画，也可始终显示 Dock 图标。
- **更新与排查**：关于页支持自动或手动检查更新；诊断页可查看、复制本次运行的脱敏记录。

## 安装与环境

支持 **macOS 14 及以上的 Apple Silicon Mac（M 系列芯片）**，收听需要网络连接。

1. 前往 [下载页面](https://github.com/GiaoGiaoCat/RadioBar/releases/latest)，下载 `RadioBar-macOS-arm64.zip`。
2. 解压，将 `RadioBar.app` 拖入“应用程序”后打开；更新前先退出旧版。

**首次打开被拦截？请按下图操作。** 当前版本仅 ad-hoc 签名，尚未经过 Apple 公证。若提示“Apple 无法验证”，请先确认文件来源可信且未被篡改，再按照图中步骤打开。

<p align="center">
  <a href="docs/images/radiobar-wechat-install-guide.png">
    <img src="docs/images/radiobar-wechat-install-guide.png" width="680" alt="RadioBar 安装指南：保存并解压 ZIP，将 App 拖入应用程序后打开；若提示 Apple 无法验证，点完成，再到系统设置的隐私与安全性中点仍要打开，按提示验证并确认打开，最后点击菜单栏天线图标选择电台。">
  </a>
</p>
<p align="center"><sub>点击图片查看大图，也可保存后随安装包通过微信发送。系统界面为操作示意，实际样式可能略有不同。</sub></p>

图中的放行步骤仅适用于“无法验证”提示；如遇“已损坏”等其他报错，请先反馈具体提示。详见 [Apple 官方说明：在 Mac 上安全地打开 App](https://support.apple.com/zh-cn/102445)。

## 用法

点击菜单栏的天线图标，选择电台即可播放；菜单内可暂停、重连、静音和调整音量。新电台静音连接并开始实际播放后，先用 0.8 秒淡出原电台，静音间隔 0.5 秒，再用 1.2 秒淡入新电台；2.5 秒交接不包含网络连接与缓冲时间，连接失败时保留原电台。静音不会暂停播放，也不改变保存的音量。

在“设置”里管理电台、启动行为、外观和睡眠定时。点击主菜单的睡眠定时入口可直接打开对应设置页；计时期间默认在菜单栏显示剩余时间，关闭显示不会停止计时。设置窗口打开时会显示 Dock 图标，关闭后恢复菜单栏模式；也可在通用页开启“始终显示 Dock 图标”。

菜单展开时可用：`空格` 播放 / 暂停、`⌘R` 重连、`⌘,` 打开设置、`⌘Q` 退出。

### 电台使用规则

- **播放线路**：所有电台使用有序固定地址；失败后按原有重试预算依次轮换，单地址原线重试。KISS 和央广各保留已确认的一条固定线路，不再进行客户端动态取址或定时刷新。

- **添加、编辑与删除**：打开“设置 → 电台配置”，在列表底部点击“添加电台”，或点击普通电台行的铅笔按钮。中英文名称必填，播放地址每行一个，首个为主线路，其余为备用；应填写音频流或播放列表地址。删除需在编辑窗口内确认。保存或删除前自动备份，成功后立即生效，无需另点“重新加载”。KISS 与央广 Music Radio 为内置台，只能隐藏和排序，不能编辑或删除。
- **排序与显示**：拖动行左侧手柄排序，右侧开关控制显示，更改自动保存。至少保留一个显示台；隐藏台不参与菜单、默认电台选项和启动随机，但不打断当前播放。“恢复默认顺序”只重置顺序，不清除显示选择。
- **启动与当前播放**：固定默认台被隐藏或删除后，改为“上次收听的电台”；上次收听已失效时，启动使用当前顺序中的首个显示台。编辑名称即时刷新，新地址用于后续连接；删除正在播放的电台不会立即停止该连接。
- **手动编辑配置（进阶）**：界面管理与 JSON 编辑共用同一份 `stations.json`。在页面下方的“配置文件”卡片点击“打开文件”，用外部编辑器保存后再点“重新加载”；当前不自动监听文件。校验失败保留当前列表和播放。已有顺序保留，新电台追加；手动显示或隐藏的选择优先于 JSON 默认值。若编辑窗口提示文件已被外部修改，取消编辑、重新加载后再打开。
- **恢复默认电台列表**：页面下方“恢复内置电台”的“恢复”会先备份当前 JSON，再完整替换为本版默认列表并立即应用，自定义添加和修改也会被替换；备份失败则不覆盖。此操作保留排序与显示偏好，与“恢复默认顺序”分别独立。App 更新不会覆盖已有用户配置。

配置文件位置、字段、稳定 ID、备份和异常处理详见 [电台 JSON 配置说明](docs/STATIONS.md)。保存或加载成功只表示配置有效，不代表地址已通过联网试播。

### 配置同步（可选）

在“设置 → 配置同步”中设置 iCloud 文件夹，Mac 将本机电台资料、排序、显示选择和默认模式单向发布，iPhone 只读并保留最后有效缓存。默认位置为 `RadioBar/RadioBarSync`，也可选择原有目录；首次发布和接替现有配置需要确认。只有一台 Mac 管理，不提供多 Mac 编辑。

启动、回到前台及配置修改时自动发布，也可“立即同步”。停止同步保留本机及云端文件。原 Application Support 目录、音量、上次收听等设备偏好保持；外部编辑 JSON 后仍须先“重新加载”。由系统传递配置，不承诺实时到达。

新版电台 JSON 备份固定保留最近 5 次成功操作，旧备份及失败恢复材料保留，可从“电台配置 → 打开文件夹”手动检查。同步页在关联后可直接“打开 iCloud 同步文件夹”。界面不再提供历史恢复、手动清理、存储统计或独立同步排查。格式和迁移见 [配置说明](docs/STATIONS.md)，两端约定见 [iPhone 整改需求](docs/IPHONE_SYNC_SIMPLIFICATION.md)。iPhone 开发及真实双端 iCloud 验收分别进行。

<p align="center">
  <img src="docs/images/stations-dark.png" width="760" height="620" alt="RadioBar 深色电台配置页下半部分：电台行、添加电台、打开配置文件、重新加载与恢复内置电台">
</p>
<p align="center"><sub>电台配置页向下滚动后的界面 · 基于当前源码生成的预览</sub></p>

## 从源码编译

在上述环境安装 Command Line Tools（`xcode-select --install`），然后在仓库根目录准备构建输入。

先创建 `private/builtin-streams.json`，将以下示例中的假地址替换为已确认的完整串流地址（保留全部查询参数）：

```json
{
  "builtin.kiss": ["https://example.invalid/kiss.m3u8"],
  "builtin.music-radio": ["https://example.invalid/cnr.m3u8"]
}
```

`private/` 已由 Git 忽略；建议将该文件权限设为 `0600`。此文件仅在构建时使用，App 运行时读取包内生成的 `builtin-streams.json`，更新不覆盖用户的 `stations.json`。

```sh
./build.sh
```

首次构建需联网下载 Sparkle SDK。产物为 `build/RadioBar-macOS-arm64.zip`，按上面的步骤安装即可。

GitHub Actions 发布构建使用仓库 Settings → Secrets and variables → Actions 中的两个 Repository Secrets：`KISS_STREAM_URL`、`CNR_STREAM_URL`，分别填写一个完整地址，不加引号或 JSON。保留原 `SPARKLE_PRIVATE_KEY`。环境变量优先且必须成对；Actions 不回退本地文件，任一地址缺失或校验失败会在下载 SDK／编译 App 前停止，保留已有交付 ZIP。脚本不打印地址或解析错误正文。

Xcode 工程已加入同一资源生成阶段，直接构建时读取本地私有文件或成对环境变量。SwiftPM 需先生成被 Git 忽略的资源，再编译：

```sh
./Tools/prepare-builtin-streams.sh "$PWD/Sources/RadioBar/Resources/builtin-streams.json"
swift build
```

SwiftPM 每次修改输入后需重新生成资源；正式交付仍使用 `./build.sh`。离线 `./test.sh` 和预览不需要私有文件，使用假地址；联网专项使用相同注入工具打包真实地址。无私有输入的第三方需自行提供可用地址才能构建完整 App。

此方案避免在后续源码快照中存放地址，打包后的资源仍可提取；它不会抹除已发布历史。当前央广地址已经存在于旧提交及 `v1.2.15`，若需使该旧地址失效，必须另行更换地址或服务端凭据。

[更新日志](CHANGELOG.md) · [开发交接](docs/HANDOFF.md) · [UI 设计规范](docs/UI_GUIDELINES.md) · [开发脚本与验证](docs/TESTING.md)
