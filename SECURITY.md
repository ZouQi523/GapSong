# 安全策略

## 报告漏洞

请通过 GitHub 的 **Security › Advisories › Report a vulnerability** 私下报告，不要开公开 Issue。

报告中请包含：

- 受影响的版本（`CFBundleShortVersionString` 或 Release tag）；
- 复现步骤与影响范围；
- 如涉及日志，请先去掉个人信息。

## 支持范围

| 版本 | 支持 |
|---|---|
| 0.4.x | ✅ |
| 更早版本 | 仅建议升级 |

## 数据与权限

GapSong 没有账号、后端服务或遥测。它涉及的数据只有：

- **播放状态**：通过 AppleScript 读取/控制「音乐」，不读取音频、不接触 DRM；
- **歌词请求**：把歌名、歌手、专辑、时长发给 [LRCLIB](https://lrclib.net)（结果缓存 90 天）；
- **翻译**：使用系统 `Translation.framework`，在本机完成；
- **本地文件**：收藏 `~/Library/Application Support/GapSong/questions.json`、错题 `mistakes.json`，翻译缓存与诊断日志在 `~/Library/Caches/GapSong/`。

如果你发现任何未经说明的数据外发、命令注入、越权文件访问或歌词/翻译内容被当作代码执行的问题，请按上面的方式私下报告。
