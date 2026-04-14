# KeyLaunch（键启）

KeyLaunch 是一个 macOS 菜单栏小工具，用来给常用 App 绑定全局快捷键。

如果你经常在 Safari、Finder、终端、编辑器这些应用之间来回切，KeyLaunch 会比较顺手：按下自己设好的组合键，直接切过去，不用再到 Dock 或 Spotlight 里找。

## 可以做什么

- 给 App 绑定全局快捷键
- 支持 `Option`、`Command`、`Option + Command` 组合
- 直接在键盘布局里点选按键，设置更直观
- 如果目标 App 已经在前台，再按一次可以切回上一个 App，或者隐藏当前 App
- 同一组快捷键如果已经被别的 App 占用，会直接提示
- 如果和系统快捷键冲突，也会给出提醒
- 菜单栏里可以随时暂停或恢复快捷键
- 支持导入和导出配置，换机器时比较方便

## 安装

### 用 Homebrew 安装

```bash
brew tap KevoraLabs/tap
brew install --cask KevoraLabs/tap/key-launch
```

### 直接下载

也可以在 [Releases](https://github.com/KevoraLabs/key-launch/releases) 页面下载安装包。

如果 macOS 第一次打开时提示无法验证应用，可以在确认来源可信后执行：

```bash
xattr -dr com.apple.quarantine /Applications/KeyLaunch.app
```

如果你把应用放在别的位置，把路径换成实际的 `.app` 路径就行。

## 怎么用

1. 打开 KeyLaunch 后，它会常驻在菜单栏。
2. 选一个触发组合，比如 `Option` 或 `Command + Option`。
3. 在键盘界面里点一个按键。
4. 给这个按键选一个 App。
5. 之后在任何地方按下这组快捷键，就能直接切到对应应用。

如果你已经在这个 App 里，再按一次，KeyLaunch 会按当前设置切回上一个应用，或者隐藏当前应用。

## 配置文件

快捷键配置保存在：

- `~/Library/Application Support/AppLauncher/shortcuts.json`

你也可以直接用菜单栏里的导入、导出功能来备份和迁移配置。

## 菜单栏里可以做的事

- 打开主界面
- 显示或隐藏 Dock 图标
- 设置开机自启动
- 暂停或恢复快捷键
- 导入或导出快捷键配置
- 退出应用
