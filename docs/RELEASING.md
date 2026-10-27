# 发布指南

## 准备

1. 在 `Resources/Info.plist` 更新 `CFBundleShortVersionString` 和 `CFBundleVersion`，并同步「关于熊猫图库」显示的版本。
2. 更新 README、安装教程和本次发行说明。
3. 运行 `bash scripts/test.sh`。
4. 运行 `bash scripts/package-release.sh`。

打包脚本会分别构建 `arm64` 和 `x86_64`，合并为 Universal 可执行文件，完成应用签名和两种架构的签名检查，并验证 ZIP、DMG 的完整性。

产物目录为 `output/releases/v<版本号>/`：

- `PandaGallery-macOS-universal.dmg`
- `PandaGallery-macOS-universal.zip`
- `INSTALL-zh-CN.md`
- `SHA256SUMS.txt`

固定的附件文件名用于保持 README 中的 `releases/latest/download/...` 链接有效。每次发布前应在实际 Mac 上确认应用正常启动；交叉编译成功不能替代另一种芯片的实机测试。

## 上传源码和发行附件

先提交并推送已验证的源码，再创建对应标签和 Release。下面以 `v1.1.1` 为例；以后发布时替换为新的版本号。

```sh
git add .
git commit -m "Release v1.1.1"
git push origin main
git tag -a v1.1.1 -m "熊猫图库 1.1.1"
git push origin v1.1.1

gh release create v1.1.1 \
  --repo yangpan-dev/panda-pic \
  --verify-tag \
  --title "熊猫图库 1.1.1" \
  --notes-file docs/releases/v1.1.1.md \
  output/releases/v1.1.1/PandaGallery-macOS-universal.dmg \
  output/releases/v1.1.1/PandaGallery-macOS-universal.zip \
  output/releases/v1.1.1/INSTALL-zh-CN.md \
  output/releases/v1.1.1/SHA256SUMS.txt
```

首次使用 GitHub CLI 需要执行 `gh auth login` 并通过 GitHub 的正常登录流程。不要把 token、证书或其他凭据写进仓库。

发布后确认：

1. Release 是已发布状态，关联的标签指向本次源码提交。
2. DMG、ZIP、教程、校验文件均出现在 Assets。
3. README 中的下载链接可以下载文件。
4. 重新下载附件并与本地 `SHA256SUMS.txt` 比对，确保分发文件与已验证的包一致。

## 签名与 Apple 公证

当前构建脚本使用 ad-hoc 签名，不包含付费开发者证书，下载后可能显示首次安全提醒。安装教程必须如实说明。

如果维护者具备 Apple Developer Program 账户与 Developer ID Application 证书，可以在单独的正式分发流程中使用 Developer ID、Hardened Runtime、Apple `notarytool` 和 `stapler` 完成签名、公证与票据附加。**最终签名、公证或附加票据后，需要重新生成安装包及 SHA-256 校验文件，再上传 Release。**

参考：[Apple Developer：公证 macOS 软件](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[GitHub：管理 Release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
