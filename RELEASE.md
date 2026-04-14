# Release Guide

`key-launch` 的发版自动化放在当前仓库，通过推送 `v*` tag 触发。

## 一次性准备

先把自动化代码提交到主仓库：

```bash
git status
git add .github/workflows/release.yml scripts/package-app.sh scripts/update-homebrew-cask.sh .gitignore README.md RELEASE.md HOMEBREW_SETUP.md
git commit -m "Add Homebrew release automation"
git push origin main
```

如果要让 release 自动同步 Homebrew tap，需要先配置 Actions secret：

1. 打开 `KevoraLabs/key-launch`
2. 进入 `Settings > Secrets and variables > Actions`
3. 新建 secret：`HOMEBREW_TAP_TOKEN`
4. 这个 token 需要能访问 `KevoraLabs/homebrew-tap`，并具备提交代码权限

现在 workflow 会在 secret 存在时自动更新 `KevoraLabs/homebrew-tap`。

## 每次发版

### 1. 更新版本号

当前 release workflow 会校验 tag 去掉前缀 `v` 后，是否和 app 内的 `MARKETING_VERSION` 一致。

也就是：

- `git tag v1.1`
- app 构建出来的 `CFBundleShortVersionString` 必须是 `1.1`

如果不一致，GitHub Actions 会直接失败。

### 2. 提交并推送代码

```bash
git add .
git commit -m "Prepare release 1.1"
git push origin main
```

### 3. 打 tag 并推送

```bash
git tag v1.1
git push origin v1.1
```

## Workflow 会自动做什么

推送 tag 后，`/.github/workflows/release.yml` 会自动执行：

1. checkout 当前仓库
2. 构建 Release 版 `KeyLaunch.app`
3. 打包为 `key-launch-版本号.dmg`
4. 计算安装包 `sha256`
5. 创建 GitHub Release 并上传 DMG
6. 在 workflow Summary 输出可用于 Homebrew cask 的版本号、下载地址和 `sha256`
7. 如果配置了 `HOMEBREW_TAP_TOKEN`，自动创建或更新 `KevoraLabs/homebrew-tap/Casks/key-launch.rb`

## 两种发布模式

### 半自动

不配置 `HOMEBREW_TAP_TOKEN` 时：

- GitHub Release 自动完成
- 你手动更新 `homebrew-tap` 的 cask
- workflow Summary 里会直接给出 `version`、下载地址和 `sha256`

### 全自动

配置 `HOMEBREW_TAP_TOKEN` 后，workflow 会：

- checkout `KevoraLabs/homebrew-tap`
- 创建或更新 `Casks/key-launch.rb`
- 直接提交并推送到 `main`

## 手动更新 Homebrew tap

如果当前是半自动模式，可以从 release 产物里拿到：

- version
- 下载地址
- sha256

然后本地运行：

```bash
./scripts/update-homebrew-cask.sh \
  --cask-token key-launch \
  --cask-file /path/to/homebrew-tap/Casks/key-launch.rb \
  --version 1.1 \
  --sha256 <sha256> \
  --url https://github.com/KevoraLabs/key-launch/releases/download/v1.1/key-launch-1.1.dmg \
  --verified github.com/KevoraLabs/key-launch/ \
  --app-name KeyLaunch \
  --desc "Launch apps with global keyboard shortcuts on macOS" \
  --homepage https://github.com/KevoraLabs/key-launch
```
