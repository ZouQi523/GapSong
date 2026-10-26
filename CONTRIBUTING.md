# 贡献指南

感谢你愿意改进 GapSong！这是一个 macOS 菜单栏小工具，**保持轻量、零第三方依赖**是重要原则。

## 开始之前

- 先搜索已有的 Issue / PR，避免重复；
- 较大的功能或行为改动，请先开 Issue 讨论方向；
- 安全问题不要公开开 Issue，请按 [SECURITY.md](SECURITY.md) 私下报告。

## 环境

- macOS 15（Sequoia）或更高版本；
- Xcode Command Line Tools：`xcode-select --install`；
- 不需要 Xcode 工程文件，构建脚本直接调用 `swiftc`；
- 首次运行需要授予「控制音乐」的自动化权限。

## 构建、自检与预览

```bash
# 构建到 build/GapSong.app
./build.sh

# 命令行自检（歌词抓取、LRC 解析、判分、收藏兼容、错题持久化/历史、离线练习、来源切换、隔离模式等）
# 失败会以非 0 退出码结束；使用隔离目录/独立偏好，不读写真实收藏与错题
./build/GapSong.app/Contents/MacOS/GapSong --selftest

# 离屏渲染截图（改 UI 时很有用，不需要真的放歌）
./build/GapSong.app/Contents/MacOS/GapSong --snapshot docs/screenshots/preview.png
./build/GapSong.app/Contents/MacOS/GapSong --snapshot-full docs/screenshots/screenshot-full.png
./build/GapSong.app/Contents/MacOS/GapSong --snapshot-practice docs/screenshots/practice.png
./build/GapSong.app/Contents/MacOS/GapSong --snapshot-practice-answer docs/screenshots/practice-answer.png
./build/GapSong.app/Contents/MacOS/GapSong --snapshot-practice-setup docs/screenshots/practice-setup.png
./build/GapSong.app/Contents/MacOS/GapSong --snapshot-practice-bank docs/screenshots/practice-bank.png
./build/GapSong.app/Contents/MacOS/GapSong --snapshot-favorites docs/screenshots/favorites.png
./build/GapSong.app/Contents/MacOS/GapSong --snapshot-mistakes docs/screenshots/mistakes.png
./build/GapSong.app/Contents/MacOS/GapSong --snapshot-practice-mistakes docs/screenshots/practice-mistakes.png
```

> `--selftest` 会访问 LRCLIB 并检查系统翻译可用性，需要网络；离线环境可以只跑构建。自检与 `--snapshot*` 都会进入隔离模式（临时数据目录 + 独立 UserDefaults），不会写真实偏好，也不会向 Music 发送播放命令。

## 手动验收清单

提交 UI 或练习相关改动前，建议至少过一遍：

- [ ] 启动后能读取「音乐」播放状态，歌词与翻译正常；
- [ ] 紧凑 / 全文模式切换、拖动、缩放、锁定位置正常；
- [ ] 开始练习后能选 30%–100% 强度，题目来源可选当前歌曲 / 收藏歌词 / 错题本；
- [ ] 播放时句末自动暂停，`⌘R` 重听保留已填内容；
- [ ] 打满一个空自动跳到下一个；空格可以手动跳过；
- [ ] 只填部分空也能提交，跳过的空不算错，得分按填写比例折算；
- [ ] 揭示答案后「再试试」不计分，「下一句」正常；
- [ ] 不播放音乐也能从收藏歌词或错题本出题、答题、看答案；
- [ ] 只有真正提交且判错才进错题本；同句多次错误保留历史；答对不删旧记录；
- [ ] 部分填空跳空后，错题历史里的原句词下标仍对得上；
- [ ] 来源切换（尤其从当前歌曲切到收藏/错题）会停止旧计时和自动下一题；
- [ ] 收藏/错题管理窗口可查看、单句删除、练一句/练全部；清空有二次确认，取消不改变数据；
- [ ] 收藏/错题为空时，菜单入口仍显示但置灰并解释；
- [ ] 中文/日文行不可收藏，空收藏有提示；
- [ ] 没有崩溃，`~/Library/Caches/GapSong/diag.log` 没有反复报错。

## 代码结构

所有源码在 `Sources/GapSong/`，由 `build.sh` 一次性编译，没有第三方依赖。

| 模块 | 文件 |
|---|---|
| 入口 / 生命周期 | `main.swift`、`AppDelegate.swift`、`OverlayController.swift` |
| 歌词窗 UI | `OverlayView.swift`、`Models.swift` |
| 播放状态 | `MusicWatcher.swift`、`PlayerState.swift` |
| 歌词与翻译 | `LRCLIB.swift`、`TranslationEngine.swift` |
| 练习 | `PracticeEngine.swift`、`PracticeView.swift`、`PracticeSetup.swift`、`PracticeBlanks.swift`、`DictationJudge.swift` |
| 收藏 / 错题 / 设置 | `QuestionBank.swift`、`MistakeBook.swift`、`LibraryView.swift`、`Settings.swift`、`Paths.swift`、`AppRuntime.swift` |
| 工具 | `SelfTest.swift`、`SnapshotTool.swift`、`Diag.swift` |

## 代码风格

- Swift 5，4 空格缩进；
- 不引入第三方依赖，优先用系统框架；
- 用户可见文案保持简体中文，延续现有语气；
- 注释中英文都可以，但请解释「为什么」而不是复述代码；
- 播放控制集中在 `MusicWatcher`，不要把 AppleScript 散落到 UI；测试/快照通过 `MusicControlling` 注入替身，不能碰真实 Music；
- 耗时操作不要阻塞主线程，用 `Task` / 串行队列；
- 新增用户数据时考虑迁移与本地隐私。

## 提交 PR

1. Fork 并新建分支，一个 PR 只做一件事；
2. 跑通 `./build.sh` 与 `--selftest`；
3. UI 改动附上离屏截图（或说明无法渲染的原因）；
4. 行为变化时同步更新 `README.md` 和 `CHANGELOG.md`；
5. 在 PR 描述里写清楚动机、做法和测试方式。

提交即表示你同意以 [GPL-3.0](LICENSE) 许可贡献这些代码。
