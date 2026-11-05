# GapSong 隐私政策 / Privacy Policy

最后更新 / Last updated：2026-11-05
适用版本 / Applies to：GapSong for macOS（含 TestFlight 测试版 / including the TestFlight beta）
开发者 / Developer：NeoZou

GapSong 是一款在 Mac 上显示歌词、练习英文听写的工具。本政策说明应用会处理哪些数据、为什么处理，以及你可以如何控制。

GapSong is a macOS lyric overlay and English dictation practice tool. This policy explains what data the app handles, why, and what you can control.

## 摘要 / Summary

- 不创建账户、不使用自建服务器、不投放广告、不接入统计或分析 SDK，也不做跨应用跟踪。
- 不录音、不录屏、不读取音频文件或 DRM 内容。只通过 Apple Events（自动化）读取「音乐」中当前曲目的名称、歌手、专辑、时长、播放位置和播放状态，并在练习时暂停、继续或跳转播放。
- 默认只使用本机家长已批准的固定歌词与译文。只有家长解锁审核窗口并主动获取歌词时才查询 LRCLIB；查询会发送歌曲元数据，LRCLIB 能看到你的 IP 地址。我们无法承诺第三方不保留日志。
- 翻译使用 macOS 本机 Translation 框架；首次使用某种语言时，系统可能需要从 Apple 下载语言包。
- 收藏、错题、练习输入、设置、歌词与翻译缓存都保存在本机，不上传到我们的服务器。
- 歌词缓存保留 90 天是「有效期」，不是到期物理删除；过期条目会被忽略，并在同一首歌再次匹配时被覆盖。
- 卸载 App 不保证删除系统中的应用容器；需要时可以在系统设置或访达中自行清除。
- No account, no self-hosted server, no ads, no analytics or statistics SDK, and no cross-app tracking.
- No audio recording, screen recording, audio file access, or DRM access. The app only uses Apple Events (Automation) to read the current Music track's name, artist, album, duration, playback position, and playback state, and to pause, resume, or seek during practice.
- The app defaults to fixed lyrics and translations approved locally by a parent. Only an unlocked parent review window can initiate an LRCLIB lookup. A lookup sends track metadata, and LRCLIB can see your IP address. We cannot promise that a third party keeps no logs.
- Translation uses the on-device macOS Translation framework. The first use of a language may require the system to download a language pack from Apple.
- Favorites, mistakes, practice input, settings, and lyric/translation caches are stored locally and are not uploaded to our servers.
- The 90-day lyric cache is a validity period, not physical deletion. Expired entries are ignored and are overwritten when the same song is matched again.
- Uninstalling the app does not guarantee deletion of the app's system container. You can remove it yourself in System Settings or Finder if needed.

## 1. 账户、服务器与跟踪 / Accounts, servers, and tracking

GapSong 没有账户系统，没有注册或登录，也没有自建后端服务器。应用不集成广告、统计、崩溃分析或归因 SDK，不生成用于跨应用跟踪的标识符，也不请求跟踪授权。应用只使用 Apple 提供的本机框架、Apple Events 和 LRCLIB 的公开歌词接口。

GapSong has no account system, no sign-up or sign-in, and no self-hosted backend server. The app does not integrate advertising, analytics, crash-reporting, or attribution SDKs, does not create identifiers for cross-app tracking, and does not request tracking authorization. It only uses Apple's on-device frameworks, Apple Events, and LRCLIB's public lyrics API.

## 2. 与「音乐」的交互 / Interaction with Music

经你在系统弹窗中允许「自动化」后，GapSong 通过 Apple Events 向「音乐」发送脚本请求，用于：

- 读取当前曲目的名称、歌手、专辑、时长；
- 读取播放位置（秒）和播放状态（播放中/已暂停/已停止）；
- 在听写练习需要时暂停、继续播放或跳转到指定位置。

应用不读取音频数据、不录音、不录屏，也不访问 DRM 内容。你可以在「系统设置 › 隐私与安全性 › 自动化」中随时撤销该权限；撤销后无法读取和控制 Music，依赖实时音乐的歌词同步与听写会受影响；已有收藏与错题练习仍可使用，但应用不会因此上传任何数据。应用没有申请麦克风、摄像头、位置、通讯录、照片、辅助功能或全磁盘访问权限。

After you allow Automation in the system prompt, GapSong sends Apple Events to Music to:

- read the current track's name, artist, album, and duration;
- read the playback position (seconds) and playback state (playing/paused/stopped);
- pause, resume, or seek to a position when dictation practice needs it.

The app does not read audio data, record audio, record the screen, or access DRM content. You can revoke this permission at any time in System Settings › Privacy & Security › Automation. After revocation, reading and controlling Music is unavailable, affecting live lyric sync and Music-based dictation; existing favorite and mistake practice remains available, but the app will not upload any data as a result. The app does not request Microphone, Camera, Location, Contacts, Photos, Accessibility, or Full Disk Access permissions.

## 3. 在线歌词查询（LRCLIB）/ Online lyrics lookup (LRCLIB)

只有在家长解锁审核窗口并主动点击获取预览后，GapSong 才通过 HTTPS 请求 LRCLIB（https://lrclib.net）的公开接口。儿童使用时不会为未知歌曲自动查询网络，也不直接读取未审核缓存。请求中会包含：

- 歌曲名称、歌手名称；
- 专辑名称与时长（在精确匹配时使用）。

这些信息是查询歌词所必需的。与任何 HTTPS 请求一样，LRCLIB 的服务器可以看到你的 IP 地址、请求时间和 User-Agent 等常规网络信息。LRCLIB 是独立第三方服务，其日志、保留期限和隐私做法由它自己决定并受其政策约束；我们无法承诺它不保留日志，也无法代它作出删除承诺。请勿在 LRCLIB 查询中附加与歌词匹配无关的个人信息。

Only after a parent unlocks the review window and explicitly requests a preview does GapSong make an HTTPS request to LRCLIB's (https://lrclib.net) public API. Child use does not automatically query unknown songs or read unapproved cached lyrics. The request contains:

- track title and artist name;
- album name and duration (for exact matching).

This information is necessary to look up lyrics. As with any HTTPS request, LRCLIB's servers can see your IP address, request time, User-Agent, and other standard network information. LRCLIB is an independent third-party service; its logging, retention periods, and privacy practices are its own and are governed by its policy. We cannot promise that it keeps no logs, and we cannot make deletion commitments on its behalf. Do not include personal information unrelated to lyric matching in LRCLIB lookups.

## 4. 系统翻译与语言包 / System translation and language packs

翻译由 macOS 的 Translation 框架在本机完成，歌词文本不会发送到我们的服务器。首次把歌词翻译为某种语言时，系统可能提示下载对应的 Apple 语言包；下载由 macOS 管理与执行，可能需要联网并受 Apple 的隐私政策约束。没有可用语言包时，应用会提示需要你确认下载，不会静默上传歌词。

Translation is performed on-device by the macOS Translation framework; lyric text is not sent to our servers. The first time lyrics are translated into a language, macOS may prompt to download the corresponding Apple language pack. That download is managed and performed by macOS, may require network access, and is subject to Apple's privacy policy. When no language pack is available, the app asks you to confirm the download instead of silently uploading lyrics.

## 5. 保存在本机的数据 / Data stored on this Mac

下列数据只保存在你的 Mac 上，不会自动上传：

- 偏好设置：字号、翻译开关与目标语言、窗口尺寸与位置、透明度、练习强度等，保存在系统 UserDefaults 中；
- 收藏歌词与错题本：分别保存在应用数据目录的 `questions.json` 与 `mistakes.json`；
- 歌词缓存、翻译缓存和诊断日志（`diag.log`），其中诊断日志可能包含当前歌曲名称/歌手、歌词匹配与翻译状态、输入法来源等信息，仅用于本机排查问题；
- 练习时你键入的答案、粘贴的文本（仅在你主动粘贴时读取剪贴板）、打字机音效与系统朗读，都只在本机处理，不写入我们的服务器。应用不读取剪贴板历史，也不在你不粘贴时读取剪贴板。

The following data stays on your Mac and is not uploaded automatically:

- Preferences: font size, translation toggle and target language, window size and position, transparency, practice intensity, and similar settings, stored in system UserDefaults;
- Favorites and mistakes: stored as `questions.json` and `mistakes.json` in the app data directory;
- Lyric cache, translation cache, and a diagnostic log (`diag.log`). The log may contain the current song title/artist, lyric matching and translation status, and input-source name; it is used only for local troubleshooting;
- Answers you type during practice, text you paste (the clipboard is read only when you explicitly paste), typing sounds, and system speech are processed locally only and are never sent to our servers. The app does not read clipboard history and does not read the clipboard unless you paste.

## 5.1 家长口令与审核库 / Parent passphrase and approved library

家长口令由家长自行设置，不会发送给开发者、LRCLIB 或 Apple 服务。应用使用随机盐及 PBKDF2-HMAC-SHA256 派生值校验口令，不保存口令明文；校验记录与独立的审核库完整性密钥保存在本机钥匙串。首次设置需要至少 8 个字符并二次确认。每次打开管理入口重新验证，关闭窗口、应用失去活跃或五分钟会话到期后锁定。

The parent sets a local passphrase. It is not sent to the developer, LRCLIB, or Apple services. A random salt and PBKDF2-HMAC-SHA256 derived value are used to verify it; the plaintext passphrase is not stored. The verifier and a separate approved-library integrity key are kept in this Mac's Keychain. Initial setup requires at least eight characters and confirmation. Opening management requires authentication; closing its window, leaving the app, or reaching the five-minute session limit locks it.

`parental-approved.json` 在本机保存家长批准时的曲目标识、原文、时间轴、可选目标语言译文、批准时间、内容摘要和 HMAC 完整性标记。歌词与译文本身没有加密。普通界面只读取这份固定版本，不生成未经批准的新译文或单词释义。家长获取的歌词可能保留在本机歌词缓存；预览译文不写入普通翻译缓存。原有收藏和错题保留，但未符合批准内容的条目不显示或出题。撤销写入失败时当前运行立即停止显示，并提供重试；成功保存前重新启动仍可能读到上一次保存的批准。

`parental-approved.json` locally stores approved track identifiers, lyrics, timing, optional target-language translations, approval time, a content digest, and an HMAC integrity tag. The lyric and translation text itself is not encrypted. The ordinary interface uses this fixed version and does not generate unapproved translations or word meanings. Fetched lyrics may remain in the local lyric cache; preview translations are not written to the ordinary translation cache. Existing favorites and mistakes are preserved, while entries that do not match approved content are hidden and excluded from practice. If saving a revocation fails, the current run stops showing that content and offers a retry; restarting before a successful save may restore the last saved approval.

此功能不核验监护人身份，也不能替代系统账户、Screen Time 或家长对内容适龄性的判断。知道口令者可以管理审核库；能够清空本机数据、重装应用或访问钥匙串的系统管理员不在防护范围内。删除应用容器不保证删除钥匙串条目；应用没有无需验证的口令重置入口。

This feature does not verify guardian identity or replace system accounts, Screen Time, or a parent's judgment about age-appropriate content. Anyone who knows the passphrase can manage approvals. System administrators who can erase local data, reinstall the app, or access Keychain are outside its protection boundary. Removing the app container does not guarantee removal of Keychain items. There is no unauthenticated passphrase-reset entry.

## 6. 缓存有效期与删除 / Cache lifetime and deletion

歌词缓存写入 90 天有效期：超过 90 天的条目会被当作未命中，并可能在同一首歌再次匹配时被新结果覆盖。这个期限不等于到期自动物理删除，旧的缓存文件可能继续留在磁盘上，直到被覆盖或由你手动清理。翻译缓存同样只用于本机加速，不包含账户信息。

The lyric cache is written with a 90-day validity period: entries older than 90 days are treated as misses and may be overwritten by a fresh result when the same song is matched again. This period is not the same as automatic physical deletion; old cache files may remain on disk until overwritten or manually removed by you. Translation cache is likewise only a local speed-up and contains no account information.

删除应用不一定删除系统保留的应用容器（尤其是沙盒版本的数据容器）。如需彻底清除，可在「访达」中删除对应容器，或在「系统设置 › 通用 › 储存空间」中管理应用数据。卸载后重新安装时，旧容器有可能仍被系统保留；TestFlight 测试版不会自动读取或迁移未沙盒旧版本的数据。

Deleting the app does not necessarily delete the app container retained by the system (especially the sandboxed version's data container). To remove it completely, delete the corresponding container in Finder or manage app data in System Settings › General › Storage. After uninstalling and reinstalling, the system may still retain the old container. The TestFlight beta does not automatically read or migrate data from older, non-sandboxed versions.

## 7. TestFlight 测试版 / TestFlight beta

通过 Apple TestFlight 分发的测试版由 Apple 负责分发。Apple 可能向开发者提供测试者提交的反馈、截图、崩溃日志，以及与崩溃相关的设备型号、系统版本等诊断信息。这些信息由 Apple 的 TestFlight 平台处理并受 Apple 的隐私政策约束；开发者只将其用于定位和修复测试版问题，不会导入 GapSong 的自建系统，也不会用于广告或跟踪。TestFlight 平台本身不要求你创建 GapSong 账户。

Beta builds distributed through Apple TestFlight are delivered by Apple. Apple may provide the developer with tester feedback, screenshots, crash logs, and crash-related diagnostics such as device model and OS version. This information is handled by Apple's TestFlight platform under Apple's privacy policy; the developer uses it only to diagnose and fix beta issues, never imports it into a GapSong-operated system, and never uses it for advertising or tracking. TestFlight itself does not require a GapSong account.

## 8. 支持与反馈 / Support and feedback

支持与反馈统一通过公开的 GitHub Issues 页面进行：https://github.com/ZouQi523/GapSong/issues 。该页面由 GitHub 托管，访问和使用受 GitHub 的隐私政策约束。Issue 内容是公开的，请不要在其中粘贴歌词全文、个人联系方式、账户信息、日志中的隐私内容或其他敏感信息；如需提供日志，请先自行检查并删去个人信息。本应用不提供邮件联系方式，也不会在应用内创建支持工单。

Support and feedback are handled through the public GitHub Issues page: https://github.com/ZouQi523/GapSong/issues . The page is hosted by GitHub, and access and use are subject to GitHub's privacy policy. Issues are public; do not paste full lyrics, personal contact details, account information, private content from logs, or other sensitive information. If you need to share a log, review and redact personal information first. The app does not offer an email contact and does not create in-app support tickets.

## 9. 儿童与政策变更 / Children and changes

GapSong 不面向儿童单独收集任何数据，也不含广告或社交功能。若本政策发生实质变化，我们会更新本文件顶部的「最后更新」日期，并随应用版本一起发布；继续使用新版本即表示你了解更新后的说明。

GapSong does not separately collect any data from children and contains no advertising or social features. If this policy changes materially, we will update the "Last updated" date at the top of this document and ship it with the app version. Continued use of a new version means you are aware of the updated policy.

## 10. 第三方服务 / Third-party services

本政策只覆盖 GapSong 自身。Apple（系统翻译、语言包、TestFlight、Apple Music）、LRCLIB 与 GitHub 是独立服务，分别适用各自的隐私政策。GapSong 不对这些第三方服务的日志、保留或处理行为作出承诺。

This policy covers GapSong itself only. Apple (system translation, language packs, TestFlight, Apple Music), LRCLIB, and GitHub are independent services governed by their own privacy policies. GapSong makes no commitments about the logging, retention, or processing behavior of those third-party services.
