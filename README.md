# DeepSeek Glass

一个 iOS 26 的 DeepSeek 第三方客户端：原生 SwiftUI、系统液态玻璃底栏、流式对话、深度思考、联网搜索、按住说话，以及可注入的对话风格预设。

> 只接你自己的 DeepSeek API Key，不登录账号、不做云同步。不是深度求索官方 App。

## 为什么是「另一个客户端」

官方 App 用的是 `chat.deepseek.com/api/v0/*` 私有接口，系统提示词在服务端，客户端只发 `prompt` + 会话 id。APK 里没有可提取的前置提示词（官方 R1 README 也明确说 App 不使用 system prompt，温度 0.6）。所以这个客户端做了两件事：

1. 用公开的 DeepSeek API（Anthropic 兼容 Messages 接口）复刻对话界面与交互；
2. 把「对话风格」做成可切换的预设：
   - **DeepSeek 原生**：只注入日期，温度 0.6，尽量贴近官方服务端的默认行为；
   - **陪伴模式**：一段为长期聊天写的前置提示词，语气更松弛、会接情绪、不列清单；
   - **自定义**：自己写 system prompt。

设置里可以展开「查看当前生效的提示词」，看到实际发出去的每一句话。

## 功能

- iOS 26 原生 `TabView` + `.tabBarMinimizeBehavior(.onScrollDown)`：底栏是系统液态玻璃，向下滚动自动收起，没有手搓的假玻璃。
- 对话页：流式输出、Markdown（标题/列表/表格/代码块/LaTeX 兜底）、思考过程折叠、联网搜索步骤、来源 favicon、引用角标、复制/点赞/朗读/分享/重新生成。
- 输入区：深度思考 / 智能搜索开关、图片、拍照、相册、PDF/TXT、按住说话（上滑取消），语音走 DeepSeek ASR。
- 历史页：按今天/昨天/本周分组，搜索、置顶、重命名、删除。
- 设置页：API Key（钥匙串）、模型、API 地址、风格预设、推理强度、外观、字体大小、清空数据。
- 液态玻璃：系统 TabBar、悬浮玻璃头部按钮、玻璃输入卡、玻璃设置卡、玻璃侧边抽屉。全部使用 `glassEffect` / `GlassEffectContainer` / 系统 Material，不手绘折射。

## 系统要求

- iPhone，**iOS 26.0+**（液态玻璃与底栏收起 API 的最低版本）
- Xcode 26+（iOS 26 SDK），Swift 5 语言模式
- 你自己的 DeepSeek API Key：https://platform.deepseek.com/

## 编译（没有 Mac 也能出包）

仓库自带 `.github/workflows/build.yml`：

1. 把整个目录推到一个 GitHub 仓库（私有即可）；
2. 打开 **Actions → Build unsigned IPA → Run workflow**；
3. 跑完在本次运行的 **Artifacts** 里下载 `DeepSeekGlass-unsigned-ipa`；
4. 得到一个未签名 `.ipa`，用 Sideloadly / AltStore / SideStore 用自己的 Apple ID 签一下即可（免费 ID 7 天有效）。

工作流用 `macos-latest` + 最新 Xcode，`CODE_SIGNING_ALLOWED=NO`，不需要证书。

有 Mac 时也可以直接打开 `DeepSeekGlass.xcodeproj`，选自己的 Team 运行。Bundle ID 默认 `com.nxcdsl.deepseekglass`，可自行修改。

## 第一次使用

1. 打开 App → **设置** → 填 API Key → **保存** → **验证连接**；
2. 回「对话」，在输入框上方选「深度思考 / 智能搜索」；
3. 想改说话风格：**设置 → 对话风格**。陪伴用途建议选「陪伴模式」，再按自己的口味改自定义提示词。

## 说明与限制

- 这是第三方客户端，和深度求索没有隶属关系；API 按 token 计费，费用在你的 DeepSeek 账户里。
- 语音输入会把 16 kHz 单声道 WAV 上传到 `https://api.deepseek.com/v1/tools/asr`，单次最长 120 秒；不保存录音。
- 对话、图片、附件只存在本机 Application Support；删除 App 即删除。
- 官方 App 的私有接口、服务端提示词和风控不在这个项目里，所以行为「接近」而不是逐字一致。
- 思考过程、搜索步骤和引用依赖 DeepSeek Messages API 的返回块；换模型或中转可能导致这些块缺失，界面会自动降级。

## 目录

```
DeepSeekGlass/
├─ App/            入口、TabView、路由
├─ Chat/           对话页、输入卡、消息、思考、语音、侧边栏
├─ Markdown/       轻量 Markdown + LaTeX 兜底渲染
├─ Models/         数据模型、本地存储、附件
├─ API/            Messages SSE、ASR、错误处理
├─ Settings/       设置页、风格预设、Keychain
├─ Design/         配色、字体、玻璃组件、鲸鱼 logo
└─ Assets.xcassets
```

## 许可

仅限个人学习与自用。DeepSeek 名称与鲸鱼形象归深度求索所有；本项目使用自绘的鲸鱼图形，不包含官方 App 的任何代码或资源。
