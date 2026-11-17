# 音乐播放器（给 32 位老 iPad）

一个给 iPad mini 第 1 代、iPad 第 4 代这类 32 位老设备写的音乐播放器，用 Objective‑C 编写，纯代码界面，可以用**最新版 Xcode** 的工具链编译出能在 iOS 9.3 / iOS 10 上运行的 armv7 程序。

## 功能

- **本地音乐**：播放 iPad 音乐资料库里的歌曲，以及通过访达 / iTunes“文件共享”拖进来的 mp3、m4a、wav 等文件。
- **网络电台**：预置 27 个电台（古典、爵士、综合），可自行添加和删除；支持 mp3 / AAC 流、m3u8，以及 `.pls` / `.m3u` 播放列表地址。
- **输出到 Sonos**：自动发现局域网里的 Sonos 音箱，播放、暂停、跳转、音量都可控制。做法参考了 [soco-cli](https://github.com/avantrec/soco-cli) 的 `play_file`：app 内置一个支持 Range 的 HTTP 服务，再通过 UPnP 让音箱来拉取。
- **统一的输出菜单**：这台 iPad、AirPlay / 蓝牙、Sonos 在同一个菜单里切换。
- **联网封面**：歌曲没有自带封面时，按“艺人 + 歌名”从 iTunes Search API 查找并缓存。
- 后台播放、锁屏控制、随机、列表循环 / 单曲循环。

## 测试情况

| 设备 | 系统 | 状态 |
|---|---|---|
| iPad mini 第 1 代（iPad2,5） | iOS 9.3.5 | 可启动，电台本机播放已确认 |
| iPad 第 4 代（iPad3,4） | iOS 10.3.3 | 已安装，未完整验证 |
| Sonos Play:5 第 1 代（S1） | — | 从 Mac 用同一份 Sonos 代码实测：播放、跳转、暂停、播完检测正常 |

尚未在真机上验证的部分：Sonos 输出的完整流程（含资料库歌曲导出）、Sonos 播放电台、AAC 电台在 iOS 9 上的兼容性。

## 编译

需要 macOS 和 Xcode（在 Xcode 27 上验证过）。

```bash
cd MusicPlayer
./build.sh
```

产物在 `MusicPlayer/build/MusicPlayer.app`（未签名）。

### 为什么要手工编译

新版 Xcode 已不支持 32 位 iOS，但编译器和链接器仍能输出 armv7。`build.sh` 绕过了三个问题：

1. **SDK 里没有 32 位库**：只借用 SDK 的头文件；链接时用脚本生成的 `.tbd` 桩（只含 install‑name），并加 `-undefined dynamic_lookup`，符号留给设备上的 dyld 解析。
2. **链接器不再标记 Thumb 指针**：入口点、方法实现、block 等指向 Thumb 代码的指针都没有 Thumb 标记，老系统会以 ARM 模式执行 Thumb 代码而立即崩溃。解决办法是全部用 `-marm` 编译。
3. **新 SDK 头文件引入老系统没有的符号**：例如 `FD_SET` 会引用 iOS 14 才有的函数，代码里避开了 `select()`。

没有 Swift，也没有第三方依赖。

## 安装

老系统无法用新版 Xcode 的设备管理来安装，`tools/install.c` 是一个基于 [libimobiledevice](https://libimobiledevice.org) 的小安装器：

```bash
cc tools/install.c -o build/install $(pkg-config --cflags --libs libimobiledevice-1.0)
./build/install <设备 UDID> build/MusicPlayer.app
```

签名有两种情况：

- **已越狱并装有 AppSync Unified 的设备**：签名校验被放行，随便签一下即可安装。上表两台设备都是这样装上的。
- **未越狱的设备**：需要包含该设备的开发描述文件并正确签名（`codesign` 时要带 `--digest-algorithm=sha1,sha256`）。`provisioning/` 是用来让 Xcode 生成描述文件的空壳工程，构建时用 `DEVELOPMENT_TEAM=<你的团队 ID>` 指定团队。注意新版 Xcode 无法为这么老的设备自动登记 UDID，需要在开发者后台手动添加。

使用前请把 `Info.plist` 和 `provisioning` 工程里的 Bundle ID 换成你自己的。

## 目录

```
MusicPlayer/
  Main.m            界面与播放逻辑
  Sonos.h / Sonos.m Sonos 发现（SSDP）、控制（UPnP/SOAP）、内置 HTTP 文件服务
  Info.plist
  MakeIcon.swift    生成应用图标
  build.sh          编译脚本
  tools/
    install.c           安装器
    sonos_test.m        Mac 上的只读自测：发现音箱、查询状态、验证 HTTP 服务
    sonos_play_test.m   Mac 上的实播测试（会让音箱播放指定文件）
  provisioning/     生成描述文件用的空壳 Xcode 工程
```

## 已知限制

- 选择 Sonos 播放本地歌曲时，iPad 会静音同步播放同一首歌，用来让 app 在锁屏后不被挂起（否则内置 HTTP 服务会断）。
- 资料库里的歌要先导出成 m4a 才能给 Sonos，首次播放会多等几秒；受 DRM 保护的歌无法导出。
- iOS 10 及以下没有公开接口列出 AirPlay 设备，菜单里的“AirPlay 与蓝牙…”是再弹出系统选择器。
- 联网找封面是模糊搜索，可能配错；缺封面歌曲的艺人和歌名会作为搜索词发送给 Apple。
- 电台地址可能随时间失效。
