# 同名 GitHub 仓库重建

本地准备日期：2026-10-23（Asia/Shanghai）。用户已指定新仓库初始化版本为 2.0.0（107），构建号延续递增。当前首次提交包含合并后的更新说明和现有功能；用户配置、偏好、签名密钥及发布流程保持。

## 本地已完成

- 当前目录 `/Users/victor/Github/RadioBar` 重新 `git init`，分支为 `main`，首次提交没有父提交；不保留旧标签、旧分支或远端跟踪引用。`origin` 使用原地址 `git@github.com:GiaoGiaoCat/RadioBar.git`，尚未推送。
- 仅保留一份重建前源码及其原 Git：`private/repository-rebuild-20261023-154311/RadioBar-before-reinit/`。少量校验记录和操作说明放在同级目录；不备份远端附件、SDK、构建缓存或重复源码包。
- 旧 Git 保存其他五个工作目录的关联，包括仍有未提交工作的 iOS 工程；这些目录保持原提交和文件内容。它们仍依赖备份，不要删除／移动备份，也不要从这些旧目录向同名新仓库推送或合并旧历史。
- 本地 `private/builtin-streams.json`、原交接输入及被忽略的生成资源保持；首次提交不含它们、两条完整地址或共享凭据。旧 Git 备份仍含历史敏感内容，只供本机恢复，禁止上传。
- 本机钥匙串中已确认存在 account `local.victor.RadioBar` 的原签名密钥条目；仅查属性，没有读取、导出或另行生成密钥。

## GitHub 网页上后续要做的事

本次没有执行以下操作。先确认本地备份可用、原签名密钥能够取回，再安排仓库切换；删除到新版本附件发布之间，现有 App 的更新检查会暂时不可用，已安装 App 的本地播放不因此中断。

1. 在旧仓库 **Settings → General → Danger Zone → Delete this repository** 删除 `GiaoGiaoCat/RadioBar`。这是用户选择的仓库重建步骤，旧 Releases、Actions 配置和 Secrets 不会自动转移。
2. 在同一账号下创建名为 **RadioBar** 的空仓库，保持原来的 **Public** 可见性。不要勾选初始化 README、`.gitignore` 或许可证；这些文件已在本地首次提交中。
3. 在 **Settings → Secrets and variables → Actions → Repository secrets** 添加三项，名称必须完全一致：

   | Secret | 取值 |
   |---|---|
   | `KISS_STREAM_URL` | 本机 `private/builtin-streams.json` 的 `builtin.kiss` 首个完整地址；不带 JSON 引号或方括号 |
   | `CNR_STREAM_URL` | 同文件的 `builtin.music-radio` 首个完整地址；保留全部查询参数 |
   | `SPARKLE_PRIVATE_KEY` | 本机登录钥匙串 account `local.victor.RadioBar` 的原私钥，以 Sparkle 工具导出的格式填写；不得换新密钥 |

4. 确保仓库允许使用 GitHub Actions，并允许发布工作流声明的 `contents: write` 权限；保留已有 Sparkle 公钥、bundle ID 和更新地址。
5. 创建并配置完成后再告知后续执行者。获得推送授权后，仅从**当前新仓库的 `main`** 普通推送，不从旧备份／旧工作目录镜像推送，不恢复旧标签。首次推送主分支不会触发现有 tag 发布工作流。
6. 发布必须单独获得授权，再按 HANDOFF 的构建、原密钥签名、先分支后 tag 和远端验收流程交付 `v2.0.0` 或届时核准的更高版本。发布最新 ZIP、校验文件及四份签名 appcast 后，原更新地址才能重新提供有效更新。

## 清理范围与恢复

新 Git 的提交历史不含旧地址；旧地址仍可能存在于已下载的安装包、他人克隆或平台缓存中。同名重建不使旧服务端凭据失效，当前 App 包内资源也仍可提取，服务端轮换需另行授权。

本地新旧 Git 已分离。回到旧备份目录可以查看重建前的源码和历史；恢复原目录前须先保留新仓库后续工作，并再次修复关联目录，不能直接覆盖 `.git`。不要上传整个 `private/`。
