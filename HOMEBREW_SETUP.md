# Homebrew Setup

这份文档用于把 `key-launch` 接入自定义 Homebrew tap。

目标效果：

- 用户可以执行 `brew install --cask KevoraLabs/tap/key-launch`
- 安装来源是 `KevoraLabs/key-launch` 的 GitHub Release
- cask 文件维护在 `KevoraLabs/homebrew-tap`

## 一、tap 仓库结构

目标仓库：

- `KevoraLabs/homebrew-tap`

目录结构至少需要这样：

```text
homebrew-tap/
  Casks/
    key-launch.rb
```

说明：

- 仓库名使用 `homebrew-tap`，用户执行 `brew tap KevoraLabs/tap` 时会自动映射到这个仓库
- cask 文件放在 `Casks/` 目录里

## 二、cask 文件

在第一次 release 跑完后，workflow 会自动创建或更新：

- `KevoraLabs/homebrew-tap/Casks/key-launch.rb`

典型内容如下：

```ruby
cask "key-launch" do
  version "1.1"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/KevoraLabs/key-launch/releases/download/v#{version}/key-launch-#{version}.dmg",
      verified: "github.com/KevoraLabs/key-launch/"
  name "KeyLaunch"
  desc "Launch apps with global keyboard shortcuts on macOS"
  homepage "https://github.com/KevoraLabs/key-launch"

  app "KeyLaunch.app"
end
```

## 三、Release 产物要求

为了让 Homebrew 配置最简单，`key-launch` 发布时建议满足这两个条件：

1. Git tag 形式固定为：

```bash
v1.1
```

2. GitHub Release 资产名固定为：

```bash
key-launch-1.1.dmg
```

也就是：

```text
https://github.com/KevoraLabs/key-launch/releases/download/v1.1/key-launch-1.1.dmg
```

## 四、用户安装方式

用户可以这样安装：

```bash
brew tap KevoraLabs/tap
brew install --cask key-launch
```

或者一步完成：

```bash
brew install --cask KevoraLabs/tap/key-launch
```

升级：

```bash
brew upgrade --cask key-launch
```

卸载：

```bash
brew uninstall --cask key-launch
```

## 五、每次发版如何更新

每次 `key-launch` 发布新版本后，需要同步更新 `homebrew-tap` 里的 cask：

1. 确认 GitHub Release 已经生成
2. 拿到新版本号，例如 `1.2`
3. 拿到新的 DMG 下载地址
4. 计算 DMG 的 `sha256`
5. 更新 `Casks/key-launch.rb` 里的：

- `version`
- `sha256`
- `url`

如果已经配置了 `HOMEBREW_TAP_TOKEN`，这一步会由 workflow 自动完成。

## 六、本地验证

改完 cask 后，本地可以这样验证：

```bash
brew tap KevoraLabs/tap /path/to/homebrew-tap
brew install --cask --verbose key-launch
```

或者直接审核：

```bash
brew audit --cask --tap KevoraLabs/tap key-launch
```

## 七、注意事项

1. Homebrew 只负责安装，不负责 Apple notarization。  
   如果应用没有完成 notarization，用户第一次打开仍可能遇到 Gatekeeper 提示。

2. `sha256` 必须和 Release 里的 `.dmg` 完全一致。  
   只要 DMG 内容变了，就必须重新计算。

3. 版本号、tag、下载文件名最好保持一一对应。  
   推荐固定规则：

```text
tag: v1.1
version: 1.1
asset: key-launch-1.1.dmg
```
