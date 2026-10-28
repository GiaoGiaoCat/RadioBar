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

## 本地签名与朋友协助公证

此流程保留原 `./build.sh` 的 ad-hoc 构建，且不改变 GitHub Actions。需要钥匙串中有效的 Developer ID Application 证书及配对私钥、可用的安全时间戳网络服务和 Xcode 的 `stapler`。查看签名身份：

```sh
security find-identity -v -p codesigning
```

将下面的示例替换为所选 Developer ID Application 的证书 SHA-1（不要使用 Apple Development 身份），然后生成待提交包：

```sh
RADIOBAR_SIGNING_IDENTITY=证书SHA1 ./build.sh --developer-id
```

生成 `build/RadioBar-notary-submission.zip`；这是待公证包，不是最终交付物。将该 ZIP 发给账户持有人，并让对方提供 Apple 公证结果（Accepted）和完整日志；签名私钥不需要发送。保存原提交包，不要重新构建，因为每次构建的签名及资源均可能不同。

账户持有人可使用自己 Mac 上的 Xcode `notarytool`：先为自己的 Apple 账户创建 App 专用密码，再执行 `xcrun notarytool store-credentials RadioBarNotary` 并按交互提示输入自己的 Apple 账户、团队 ID 和专用密码；随后执行 `xcrun notarytool submit /收到的ZIP路径 --keychain-profile RadioBarNotary --wait`。记下提交 ID，并用 `xcrun notarytool log 提交ID --keychain-profile RadioBarNotary` 查看完整日志，包括 Accepted 时的警告。不要在聊天或命令行参数中发送密码；公证凭据留在账户持有人的电脑。具体用法见 [Apple 文档](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。

确认该包已获 Accepted 后，在本机对原提交包执行：

```sh
./Tools/finalize-notarized.sh build/RadioBar-notary-submission.zip
```

脚本解压该包，附加并验证 Apple 公证凭据，重新打包，再从最终 ZIP 解压执行严格签名、公证凭据和 Gatekeeper 检查。全部通过后才替换 `build/RadioBar-macOS-arm64.zip`。失败保留旧交付包；需要联网获取凭据。Apple 公证不等于 App Store 审核。之后才使用 `./Tools/sign-release.sh` 对最终 ZIP 生成 Sparkle 更新签名；切勿在附加凭据前签更新包。旧版 ad-hoc 到 Developer ID 的实际更新兼容性须单独验证。

## 使用本地公证包发布 GitHub Release

发布前确保本流程对应的工作流已提交到 `main`。在干净的工作区、准备发布的提交上构建并完成朋友协助公证；生成最终 ZIP 后不要重新运行普通 `./build.sh`，它会覆盖同名产物。核对版本及构建号后，记录发布提交的完整 SHA 和最终 ZIP 的 SHA-256：

```sh
git rev-parse HEAD
shasum -a 256 build/RadioBar-macOS-arm64.zip
```

按发布授权先推送分支，再创建并推送对应 tag。推送 `main` 只触发只读验证任务：检查脚本、发布顺序，并验证临时生成的 ad-hoc 测试包会被公证校验拒绝；不创建或发布版本。推送 tag 本身不会触发发布。创建对应的 **draft** Release，在草稿中只上传一个 `RadioBar-macOS-arm64.zip`；不要用已正式发布的标签，也不要预先上传 appcast 或校验文件。使用网页或 GitHub CLI 均可，例如在设置好仓库与标签后：

```sh
gh release create v版本号 build/RadioBar-macOS-arm64.zip --draft --verify-tag --title 'RadioBar 版本号' --generate-notes
```

在 GitHub Actions 手动运行 `Release notarized macOS app`，选择 `main`，填写 `release_tag`、上述完整 `source_commit` 和小写 `archive_sha256`。工作流检出标签，验证输入和远端标签指向同一提交、草稿状态和附件，下载并核验 ZIP 摘要、完整 Info.plist、arm64、Developer ID 团队、时间戳、运行时、公证及 Gatekeeper；然后生成并验证四份 Sparkle 更新源，上传后重新下载逐字节检查，最后发布草稿为 latest。

摘要确认远端 ZIP 与本地所选文件相同；签名和元数据检查**不能证明二进制由该提交编译**。因此要在干净的该提交工作区构建并记录提交，不能用版本号相同但来源不明的包。公证和 Sparkle 私钥继续分别管理，无需上传 Developer ID 私钥或 Apple 公证凭据。

工作流失败时草稿保留；若失败发生在上传更新源之后，检查草稿并删除本次产生的校验文件和 appcast，仅保留原 ZIP，再重新运行。不要替换已正式发布的版本或移动已发布标签。完成后需核对 Actions 状态、Release 附件及更新源；真实客户端升级仍需单独验收。

## GitHub Actions 发布构建

GitHub Actions 发布工作流不再构建 App，也不需要电台地址或 Developer ID 私钥；仍需原有 `SPARKLE_PRIVATE_KEY` 对最终 ZIP 与更新源签名。日常构建的电台地址输入仍按上文配置。

## Xcode 与 SwiftPM

Xcode 工程在编译前调用同一生成器，将配对产物写入 DerivedSources，再编译密钥源码、复制密文；增量构建会移除旧的包内明文资源。SwiftPM 需先生成被 Git 忽略的密文及源码，再编译：

```sh
./Tools/prepare-builtin-streams.sh "$PWD/Sources/RadioBar/Generated"
swift build
```

生成目录只用于 `builtin-streams.bin` 和 `BuiltinStreamKey.swift`，两者成对原子替换，已有其他文件时拒绝覆盖；密文权限为 0644，密钥源码为 0600，均不入 Git。CLT 构建在临时目录生成，完成后清理。SwiftPM 每次修改输入后需重新生成两者；正式交付仍使用 `./build.sh`。旧版 SwiftPM 生成的 `Sources/RadioBar/Resources/builtin-streams.json` 可删除，不能作为新构建输入。离线 `./test.sh` 和预览不需要私有文件或密钥，使用假地址；联网专项使用相同工具打包真实地址。无私有输入的第三方需自行提供可用地址才能构建完整 App。

## 地址保护的边界

加密与密钥混淆可以避免直接打开资源或普通文本搜索得到完整地址；解密能力随 App 分发，有能力的逆向分析或运行时调试仍可提取。无需增加 Secrets，也不使用 Sparkle 更新私钥加密地址。旧提交及已发布的明文安装包不受此改动影响；若需使旧地址失效，必须另行更换地址或服务端凭据。
