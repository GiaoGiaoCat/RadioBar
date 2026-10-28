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

此流程用于从 GitHub 分发经过 Developer ID 签名和 Apple 公证的 App。普通 `./build.sh` 仍生成 ad-hoc 包，不能代替以下公证步骤。需要联网、可用的 Xcode 和 `stapler`、本机钥匙串中有效的 Developer ID Application 证书及配对私钥、构建输入，以及朋友的公证协助。`build/` 被 Git 忽略，是可覆盖的产物目录；需要留存的 ZIP、摘要和日志应另作备份。

### 1. 确定版本和源码

在仓库根目录检查 `git status --short`、`git diff` 和 `git diff --cached`，保留并确认所有改动。功能版本按 [AGENTS](../AGENTS.md) 同步 `Resources/Info.plist` 的版本和递增构建号、App 内双语更新日志及 [CHANGELOG](../CHANGELOG.md)；先按 [TESTING](TESTING.md#按改动选择验证) 完成对应验证。提交前核对暂存内容和近期提交惯例，按授权提交。

签名构建必须在准备发布的**干净提交**上执行，记录 `git rev-parse HEAD` 输出的完整提交 SHA。随后若源码有变化，需要重新构建、重新提交公证并重新记录 SHA；不要将旧包标记成新提交。例：版本 2.0.8 对应 `v2.0.8`，构建号要大于上一发布版；具体值以当次源码为准。

### 2. 签名并生成待公证包

确认签名身份：

```sh
security find-identity -v -p codesigning
```

在输出中找到 `Developer ID Application` 对应的证书 SHA-1，确认身份有效且属于预期团队，替换下面的 `证书SHA1` 后运行（不要选择 Apple Development 身份）：

```sh
RADIOBAR_SIGNING_IDENTITY=证书SHA1 ./build.sh --developer-id
```

构建时可能要求允许 `codesign` 使用钥匙串私钥；签名需要安全时间戳网络服务。成功后生成 `build/RadioBar-notary-submission.zip`，这是待公证包，不是最终交付物。计算并记录摘要：

```sh
shasum -a 256 build/RadioBar-notary-submission.zip
```

### 3. 请朋友提交公证

把待公证 ZIP、其 SHA-256 和适用的中文步骤发给账户持有人，不发送签名私钥：首次在朋友的 Mac 上配置并提交使用[首次公证操作步骤](首次公证操作步骤.md)，已配置有效凭据时使用[再次公证操作步骤](再次公证操作步骤.md)。朋友应核对收到的 ZIP 摘要、提交 Apple 公证，并返回提交 ID、状态及完整日志。收到 `Accepted` 后仍需检查日志是否有警告；`Invalid`／`Rejected` 或有待处理的警告时先排查，不进入发布。等待中断时可由朋友用提交 ID 查询状态。

保留本机与朋友提交的**同一份原 ZIP**，并核对摘要一致；不要重新构建，因为每次构建的签名及资源均可能不同。每个新构建版本都要重新提交公证；朋友已保存且仍有效的公证凭据可以继续使用。公证不等于 App Store 审核。

### 4. 附加凭据并核验最终包

确认该包已获 Accepted 后，在本机对原提交包执行：

```sh
./Tools/finalize-notarized.sh build/RadioBar-notary-submission.zip
```

脚本解压该包，联网获取并附加公证凭据，重新打包，再从最终 ZIP 解压执行严格签名、公证凭据和 Gatekeeper 检查；全部通过后才替换 `build/RadioBar-macOS-arm64.zip`。如果失败，原提交包与旧交付包保留；先核对朋友的提交结果、摘要及网络后重试。不要将旧交付包误认为本次成功产物。

计算并保存**最终 ZIP**的 SHA-256，然后用该摘要再次校验（将示例中的 `最终ZIP的SHA256` 换成实际小写摘要）：

```sh
shasum -a 256 build/RadioBar-macOS-arm64.zip
./Tools/verify-notarized-release.sh build/RadioBar-macOS-arm64.zip 最终ZIP的SHA256
```

验证脚本还检查完整 Info.plist、arm64、时间戳、运行时、Developer ID 团队 `8H54LK5X2H`、公证凭据与 Gatekeeper。它读取当前工作区的 `Resources/Info.plist`，因此必须在准备发布的同一提交执行。若团队更换，先单独确认并更新验证脚本，不绕过检查。最终 ZIP 必须保留到发布完成；普通 `./build.sh` 会覆盖它。

如需本地预先验证 Sparkle 更新源，只能在最终 ZIP 生成后运行 `./Tools/sign-release.sh`，并按 TESTING 选择更新专项；此脚本会重建 `build/updates/`。发布工作流也会对上传的最终 ZIP 重新生成并校验签名。现有 2.0.5 到公证 2.0.7 的隔离替换验证及未覆盖范围见 [TESTING](TESTING.md)。

## 使用本地公证包发布 GitHub Release

发布前确保本流程对应的工作流已提交并推送到 `main`，且已完成上面的构建、公证和验证。核对版本及构建号后，记录构建时的完整提交 SHA 和最终 ZIP 的 SHA-256：

```sh
git rev-parse HEAD
shasum -a 256 build/RadioBar-macOS-arm64.zip
```

按发布授权先推送分支，再创建并推送对应 tag。推送 `main` 只触发只读验证任务：检查脚本、发布顺序，并验证临时生成的 ad-hoc 测试包会被公证校验拒绝；不创建或发布版本。推送 tag 本身不会触发发布。创建对应的 **draft** Release，在草稿中只上传一个 `RadioBar-macOS-arm64.zip`；不要用已正式发布的标签，也不要预先上传 appcast 或校验文件。使用网页或 GitHub CLI 均可，例如在设置好仓库与标签后：

以下仅以 2.0.8 为示例；在 `main` 的发布提交上、获得提交和推送授权后执行，实际版本必须与 `Resources/Info.plist` 一致。先检查 `git status --short` 是干净的，并确认 `git rev-parse HEAD` 仍等于构建时记录的完整 SHA。不要复用已发布的 tag。

```sh
git push origin main
git tag v2.0.8
git push origin v2.0.8
```

确认分支和标签推送成功，再创建草稿：

```sh
gh release create v2.0.8 build/RadioBar-macOS-arm64.zip --draft --verify-tag --title 'RadioBar 2.0.8' --generate-notes
```

示例中的 `v2.0.8` 和标题都要替换成实际版本，且标签必须已经存在于远端。使用网页时，在仓库的 **Releases → Draft a new release** 选择已有 tag、填写标题和说明、上传最终 ZIP，选择 **Save draft**。

在 GitHub 仓库 **Actions → Release notarized macOS app → Run workflow** 中选择 `main`，填写以下三个值，再运行：

| 输入 | 值 |
|---|---|
| `release_tag` | 远端已有的版本 tag，例如 `v2.0.8` |
| `source_commit` | 构建时记录的完整提交 SHA，小写 40 位 |
| `archive_sha256` | 最终 ZIP 的小写 SHA-256，64 位 |

工作流检出标签，验证输入和远端标签指向同一提交、草稿状态和附件，下载并核验 ZIP 摘要、完整 Info.plist、arm64、Developer ID 团队、时间戳、运行时、公证及 Gatekeeper；然后生成并验证四份 Sparkle 更新源，上传后重新下载逐字节检查，最后发布草稿为 latest。**Run workflow 会在验证通过后正式发布，不是仅预览。**

摘要确认远端 ZIP 与本地所选文件相同；签名和元数据检查**不能证明二进制由该提交编译**。因此要在干净的该提交工作区构建并记录提交，不能用版本号相同但来源不明的包。公证和 Sparkle 私钥继续分别管理，无需上传 Developer ID 私钥或 Apple 公证凭据。

工作流失败时先查看对应步骤的日志；草稿仍保留。若失败发生在上传更新源之后，检查草稿并删除本次产生的校验文件和 appcast，仅保留原 ZIP，再重新运行。若 ZIP、摘要、版本、提交或签名不匹配，先确认原因，必要时重新构建和公证；不要替换已正式发布的版本或移动已发布标签。

运行成功后，到 Actions 确认对应提交的发布任务成功；再到 Release 页面确认版本、非草稿及 latest，核对 ZIP、`SHA256SUMS.txt` 和四份 `appcast*.xml` 附件。检查最新更新源及 ZIP 的 Sparkle 签名，并在适当的隔离环境验收旧版到新版更新；必要时查看 [TESTING](TESTING.md)。公开下载和用户实际更新是单独验收，不能由工作流成功代替。

例如，可以使用已认证且指向本仓库的 GitHub CLI 检查实际远端附件。下例的 `v2.0.8` 要替换成实际版本；检查目录每次新建，避免使用旧下载或旧工具：

```sh
release_tag=v2.0.8
verify_dir="$(mktemp -d "$PWD/build/release-verify.XXXXXX")"
gh release view "$release_tag" --json tagName,isDraft,isLatest,assets
gh release download "$release_tag" --dir "$verify_dir"
(cd "$verify_dir" && shasum -a 256 -c SHA256SUMS.txt)
```

确认 `isDraft` 为 false、`isLatest` 为 true，六项附件齐全；再比较下载 ZIP 的摘要与发布前记录的摘要，并用实际摘要运行 `./Tools/verify-notarized-release.sh "$verify_dir/RadioBar-macOS-arm64.zip" 最终ZIP的SHA256`。从当前源码重新编译验证工具，逐份检查实际下载的四份更新源及 ZIP（不读取 Sparkle 私钥）：

```sh
xcrun swiftc -parse-as-library -module-cache-path "$PWD/build/ModuleCache" Tools/VerifyUpdate.swift -o "$verify_dir/VerifyUpdate"
for feed in "$verify_dir"/appcast*.xml; do
  "$verify_dir/VerifyUpdate" Resources/Info.plist "$feed" "$verify_dir/RadioBar-macOS-arm64.zip" \
    "https://github.com/GiaoGiaoCat/RadioBar/releases/download/$release_tag/RadioBar-macOS-arm64.zip"
done
```

如需确认 `latest/download` 当前四份更新源与该 tag 一致，在另一个新目录用 `gh release download --pattern 'appcast*.xml' --dir 目录` 下载 latest，逐份比较。以上命令应在与发布 tag 对应的源码上运行；如果实际仓库或下载地址改变，更新 URL 后再验。`gh` 缺失或未认证时，可在 GitHub 网页查看和下载附件，在本机按上述相同方法验签。

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
