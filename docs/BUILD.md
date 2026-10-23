# 从源码编译

需要 **macOS 14 及以上的 Apple Silicon Mac（M 系列芯片）**。安装 Command Line Tools（`xcode-select --install`）后，在仓库根目录执行下述步骤。

## 准备构建输入

先创建 `private/builtin-streams.json`，将以下示例中的假地址替换为已确认的完整串流地址（保留全部查询参数）：

```json
{
  "builtin.kiss": ["https://example.invalid/kiss.m3u8"],
  "builtin.music-radio": ["https://example.invalid/cnr.m3u8"]
}
```

`private/` 已由 Git 忽略；建议将该文件权限设为 `0600`。此文件仅在构建时使用：生成器以 AES-256-GCM 加密完整输入，每次生成随机密钥与 nonce，将密钥随机置换并用随机掩码拆分后生成 Swift 源码。App 只打包 `builtin-streams.bin`，密钥材料编入程序，运行时在内存中解密；不写回明文，不覆盖用户的 `stations.json`。

## 构建与安装

```sh
./build.sh
```

首次构建需联网下载 Sparkle SDK。产物为 `build/RadioBar-macOS-arm64.zip`，安装步骤见 [README](../README.md#安装与环境)。

## GitHub Actions 发布构建

GitHub Actions 发布构建使用仓库 Settings → Secrets and variables → Actions 中的两个 Repository Secrets：`KISS_STREAM_URL`、`CNR_STREAM_URL`，分别填写一个完整地址，不加引号或 JSON。保留原 `SPARKLE_PRIVATE_KEY`。环境变量优先且必须成对；Actions 不回退本地文件，任一地址缺失或校验失败会在下载 SDK／编译 App 前停止，保留已有交付 ZIP。脚本不打印地址或解析错误正文。

## Xcode 与 SwiftPM

Xcode 工程在编译前调用同一生成器，将配对产物写入 DerivedSources，再编译密钥源码、复制密文；增量构建会移除旧的包内明文资源。SwiftPM 需先生成被 Git 忽略的密文及源码，再编译：

```sh
./Tools/prepare-builtin-streams.sh "$PWD/Sources/RadioBar/Generated"
swift build
```

生成目录只用于 `builtin-streams.bin` 和 `BuiltinStreamKey.swift`，两者成对原子替换，已有其他文件时拒绝覆盖；密文权限为 0644，密钥源码为 0600，均不入 Git。CLT 构建在临时目录生成，完成后清理。SwiftPM 每次修改输入后需重新生成两者；正式交付仍使用 `./build.sh`。旧版 SwiftPM 生成的 `Sources/RadioBar/Resources/builtin-streams.json` 可删除，不能作为新构建输入。离线 `./test.sh` 和预览不需要私有文件或密钥，使用假地址；联网专项使用相同工具打包真实地址。无私有输入的第三方需自行提供可用地址才能构建完整 App。

## 地址保护的边界

加密与密钥混淆可以避免直接打开资源或普通文本搜索得到完整地址；解密能力随 App 分发，有能力的逆向分析或运行时调试仍可提取。无需增加 Secrets，也不使用 Sparkle 更新私钥加密地址。旧提交及已发布的明文安装包不受此改动影响；若需使旧地址失效，必须另行更换地址或服务端凭据。
