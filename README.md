# KeyLaunch（键启）

一个原生 macOS 快捷启动工具：把按键绑定到 App，用全局快捷键快速切换/启动应用。

## 主要功能

- 全局快捷键启动 App，目标 App 已在前台时可快速切回上一个应用（或隐藏当前应用）。
- 支持 `Option` / `Command` / `Option + Command` 触发键组合。
- 主界面键盘映射可视化，点击按键即可绑定/修改 App。
- 绑定弹窗支持按字母推荐 App（推荐项置顶，不参与搜索，最多 4 个）。
- 显示 App 已绑定的快捷键，当前组合已被该 App 使用时会有明确提示。
- 应用内冲突检测：同一按键组合已被占用时，阻止保存并提示冲突对象。
- 系统快捷键冲突提示：读取 macOS `com.apple.symbolichotkeys` 做提醒。
- 注册失败可视化：若全局热键注册失败（常见于被其他 App 占用），键帽会显示警告标识。
- 近 7 日使用前 10（横向滚动）：单项至少使用 3 次，且榜单至少有 3 项才展示。
- 启动失败自动重试一次（约 300ms），提升首次拉起成功率。
- 一键暂停/开启快捷键（菜单栏可操作）。
- 快捷键配置导入/导出 JSON（迁移机器方便）。

## 本地运行

```bash
cd /Users/kevin/Developer/Code/side-project/apps/macos/KeyLaunch
open KeyLaunch.xcodeproj
```

然后在 Xcode 里直接 `Run`。

## 打包发布包

```bash
./scripts/package-app.sh
```

脚本会：

- 构建 `Release` 版本
- 输出 `dist/key-launch-版本号-构建号.dmg`
- 打印对应的 SHA256，后续可直接填到 Homebrew cask

## GitHub Actions 发版

自动化放在 `key-launch` 仓库本身，通过推 tag 发版：

完整步骤见 [RELEASE.md](/Users/kevin/Developer/Code/KevoraLabs/key-launch/RELEASE.md:1)。

```bash
git tag v1.1
git push origin v1.1
```

这里的 tag 去掉前缀 `v` 后，必须和 app 的 `MARKETING_VERSION` 一致；workflow 会做这个校验，不一致就直接失败。

`/.github/workflows/release.yml` 会自动执行这条链路：

- 构建 `.app`
- 打包成 GitHub Release 资产 `key-launch-版本号.dmg`
- 创建 GitHub Release 并上传 DMG
- 计算 SHA256
- 如果配置了 `HOMEBREW_TAP_TOKEN`，自动创建或更新 `KevoraLabs/homebrew-tap` 的 `Casks/key-launch.rb`

## Homebrew 安装

第一次 release 完成并同步到 tap 后，用户可以执行：

```bash
brew install --cask KevoraLabs/tap/key-launch
```

具体接入方式见 [HOMEBREW_SETUP.md](/Users/kevin/Developer/Code/KevoraLabs/key-launch/HOMEBREW_SETUP.md:1)。

## 快捷键配置文件

应用首次启动会生成配置文件：

- `~/Library/Application Support/AppLauncher/shortcuts.json`

示例：

```json
[
  {
    "bundleIdentifier": "com.apple.Safari",
    "enabled": true,
    "id": "safari",
    "key": "1",
    "modifiers": ["command", "option"],
    "name": "Safari"
  },
  {
    "bundleIdentifier": "com.apple.finder",
    "enabled": true,
    "id": "finder",
    "key": "2",
    "modifiers": ["command", "option"],
    "name": "Finder"
  }
]
```

支持的修饰键：`command` / `option` / `control` / `shift`  
支持的按键：`a-z`、`0-9`、`f1-f12`、`space`、`return`、`tab`、`esc`、`delete`

## 菜单栏操作

- 显示主窗口
- 在 Dock 栏显示图标（可开关）
- 开机自启动
- 暂停快捷键 / 开启快捷键
- 导入快捷键配置 / 导出快捷键配置
- 退出

## TODO

- [ ] 支持多个配置项：允许用户创建和管理多个配置项，每个配置项可绑定不同的一组快捷方式，方便在不同场景下快速切换使用。
