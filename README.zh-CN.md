# DeepSeek 聚焦

[English](README.md) | **简体中文**

<p align="center">
  <img src="Resources/AppIconRounded.png" width="104" alt="DeepSeek 聚焦图标">
</p>

<p align="center">像聚焦搜索一样，随时向 DeepSeek 提问。</p>

DeepSeek 聚焦是一个原生 macOS 菜单栏应用：通过全局快捷键在任意界面唤出一个 Spotlight 风格的面板，直接使用 DeepSeek 模型回答问题和进行多轮对话。开启联网搜索时，模型可以通过 DeepSeek 官方的 Search API 按需检索实时网页。

> **非官方项目**：本项目是个人开发的第三方 DeepSeek 客户端，与 DeepSeek 官方没有隶属或合作关系。DeepSeek 名称、鲸鱼标志及相关商标归其权利人所有；仓库中的图标仅用于标识这个客户端。API 使用、账户余额和搜索计费均由使用者自行承担。



## 功能

- **全局唤起**：默认 `⌥ Space`，可在设置中录制任意组合键。面板会出现在当前鼠标所在的屏幕，并以悬浮 `NSPanel` 显示，不会创建普通文档窗口。左键点击菜单栏图标直接打开初始搜索框，右键才显示设置/退出菜单。
- **启动与菜单栏**：设置里可以开启“开机自启动”，也可以隐藏菜单栏图标；隐藏后仍可通过全局快捷键唤起面板，再用 `⌘,` 打开设置。
- **Spotlight 风格界面**：半透明磨砂圆角面板。发送第一条消息后，输入框移动到面板底部，消息以对话形式向上展开。
- **数学公式**：原生 SwiftMath 渲染 `$...$` 行内公式和 `$$...$$` 独立公式，支持分式、根号、希腊字母、上下标等常见 LaTeX。
- **中英文界面**：默认跟随系统语言，也可以在设置里切换“简体中文 / English”；界面语言立即生效。
- **流式回答**：展示 DeepSeek 的思考过程、Markdown 正文、代码块、表格、引用和可点击的来源。
- **多轮对话**：在同一个面板里继续追问；历史、思考内容和搜索工具结果会随请求发送。每次用快捷键唤起都会从空白输入框开始；新会话使用设置中的默认模型、推理等级和联网开关，单个会话内的修改会单独记住。在展开页面点“新对话”会留在展开页面，直接清空并聚焦底部输入框。
- **历史会话**：初始输入框里有“历史”入口；展开后的面板顶部左侧可打开类似 DeepSeek 网页端的侧边栏。支持搜索历史、开启新对话、按今天/7 天内/30 天内分组，并可以恢复继续过去 50 个会话。鼠标悬浮或选中会话时显示 `⋯`，可以在原位重命名或删除；切换会话不会改变列表顺序。会话保存在本机 `~/Library/Application Support/DeepSeekFocus/history.json`（权限 0600）。
- **输入框内切换模型、推理等级与联网搜索**：初始输入框和展开后的输入框都有这三项控件；在一个会话内修改后，该会话会记住自己的配置。
- **模型列表来自官方 API**：在设置中验证 API Key 后，从 `https://api.deepseek.com/models` 获取可用模型、上下文长度和该模型支持的推理档位。
- **自动会话标题**：新会话完成第一轮回答后，会异步让模型生成一个简短标题并写入历史；标题生成失败不影响对话。
- **可配置推理等级**：直接使用 DeepSeek 官方的 `Off / Low / High / Max` 名称（以及接口未来返回的其他档位）；关闭时只发送 `thinking: disabled`，不发送非官方的 `reasoning_effort`。输入框和设置里都可以切换。
- **联网搜索两种模式**（设置里选择的是新会话默认值，单个会话可单独修改）：
  - **自动搜索**：向模型提供 `web_search` 工具，由模型判断是否需要搜索；需要时调用 DeepSeek 官方 `/v1/tools/search`，再把结果交回模型继续回答。
  - **关闭搜索**：请求中不提供任何搜索工具，也不发起搜索请求。
- **来源可追溯**：搜索结果以来源卡片展示，默认全部折叠，需要时再展开全部来源；正文中的 Markdown 链接也可以直接打开浏览器。
- **隐私优先**：API Key 默认保存在本机应用数据文件中（权限 600），不使用系统钥匙串；应用没有账号系统、中转服务器、遥测或分析 SDK。对话只发送给 DeepSeek。

## 系统要求

- macOS 13 Ventura 或更高版本
- 一个可用的 DeepSeek API Key，并且账户有可用余额
- 从源码构建需要 Swift 5.9+；如果只安装了 Command Line Tools，请参见下方“构建”说明

## 使用

1. 打开应用。首次启动会自动打开设置。
2. 填入 DeepSeek API Key，点击 **验证并同步**。模型列表会从官方接口获取；也可以直接使用内置的两个常见模型条目。
3. 在“新会话默认配置”里选择默认模型、推理等级和联网搜索方式；这些设置只影响快捷键唤起后的新会话，单个会话内的修改会单独记住。
4. 点击“录制”设置全局快捷键。默认是 `⌥ Space`。
5. 在任意应用中按快捷键，初始输入框会重新打开；左侧是统一的 DeepSeek 蓝色标识，输入问题，按 `Return` 发送。点击初始输入框里的“历史”会直接展开面板并打开历史侧边栏，也可以从展开后的左上角按钮打开。

### 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 唤起 / 收起面板 | 默认 `⌥ Space`，可在设置中修改 |
| 发送 | `Return` |
| 换行 | `Shift + Return` |
| 收起面板 | `Esc`（在设置页按一次返回展开页面，再按一次才收起） |
| 新对话 | `⌘ N` |
| 打开设置 | `⌘ ,` |

设置页位于面板内部，可从展开后的齿轮按钮、菜单栏的“设置…”或 `⌘,` 打开；左上角的返回图标或 `Esc` 会回到展开的会话页面，没有单独的设置窗口，也没有“完成”按钮。

## 工作方式

应用直接调用 DeepSeek 的 OpenAI 兼容接口，没有任何后端中转：

- `GET /models`：同步模型列表和 `effort.supported_levels`。
- `POST /chat/completions`：流式对话；请求包含 `thinking`、`reasoning_effort`、历史消息和工具定义。
- `POST /v1/tools/search`：仅在“自动搜索”模式下由模型触发；每次最多取 6 条结果，按 DeepSeek 的 5 QPS 限制顺序调用。

自动搜索不是简单的“每条问题都搜索”：只有模型判断需要实时信息时才会调用工具。搜索失败不会让整个回答失败，模型会收到错误信息并被要求基于已有内容谨慎回答。

多轮对话会保存并回传：

- 用户和助手消息；
- 思考内容 `reasoning_content`（在带工具的请求中，DeepSeek 要求回传）；
- 工具调用和工具返回；
- 已经获取的来源链接。

每次用快捷键唤起面板都会恢复为空白初始输入框，并取消后台正在进行的当前请求；已经完成的会话会自动进入历史，可从输入框旁的“历史”重新打开并继续。开始新对话会取消正在进行的请求、清空当前上下文，但会保持在展开页面。

## 从源码构建

```bash
git clone https://github.com/ykn0309/deepseek-focus.git
cd deepseek-focus
swift package resolve
./scripts/build_app.sh
```

产物：

- `dist/DeepSeek 聚焦.app`
- `dist/DeepSeekFocus-latest.zip`

构建脚本会用临时 ad-hoc 签名打包，并自动用新版本替换 `/Applications/DeepSeek 聚焦.app`。如果 `Applications` 不可写，会跳过安装并保留 `dist` 中的产物。

> **只有 Command Line Tools 的机器**：macOS 26/27 的 Command Line Tools 中 SwiftUI 接口引用了 `SwiftUIMacros` 编译器插件，但插件没有随 CLT 一起安装。构建脚本会自动检测，并在存在 `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` 时使用该 SDK 编译。安装完整 Xcode 后则直接使用当前 SDK。

API Key 保存在 `~/Library/Application Support/DeepSeekFocus/credentials.json`，不使用 macOS 钥匙串，因此重新构建或替换 App 不会出现钥匙串授权弹窗。首次使用请在设置里粘贴 API Key；旧钥匙串条目的内容不会被读取。

### 开发检查

```bash
# 单元级协议与解析检查
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run CoreChecks

# 本地模拟 DeepSeek API（用于界面/流式联调）
python3 scripts/mock_server.py 8765
```

模拟接口实现了 `/models`、`/chat/completions` 的流式工具调用，以及 `/v1/tools/search`。开发时可通过环境变量覆盖接口地址和 Key（不会被当作正常设置保存）：

```bash
DEEPSEEK_FOCUS_BASE_URL=http://127.0.0.1:8765 \
DEEPSEEK_FOCUS_API_KEY=mock-key \
"dist/DeepSeek 聚焦.app/Contents/MacOS/DeepSeekFocus"
```

## 已知限制

- 当前构建是本机 ad-hoc 签名的本地应用，没有 Developer ID 签名，也没有经过 Apple 公证。
- LaTeX 由 [SwiftMath](https://github.com/mgriebling/SwiftMath) 原生渲染；首次从源码构建需要通过 SwiftPM 获取这个依赖。
- 开机自启动使用 `SMAppService`；App 需要放在稳定位置（建议 `/Applications`），否则系统可能拒绝注册登录项。
- 隐藏菜单栏图标后，只能通过全局快捷键或重新打开 App 进入；如果同时无法注册快捷键，App 会自动重新显示菜单栏图标以避免失去入口。
- 菜单栏空间不足或被菜单栏管理工具收纳时，图标可能折叠到隐藏区域。面板本身不受影响，可用全局快捷键唤起，之后按 `⌘,` 打开设置。
- 当前会话只在每轮回答结束后写入历史；如果流式回答尚未完成就切换会话，已显示的回答会作为该会话的内容保存，但恢复后的模型上下文可能不包含未完成的那一段。
- DeepSeek Search API 按成功请求计费，价格以 [DeepSeek 官方文档](https://api-docs.deepseek.com/guides/search/) 为准。
- 历史记录会写入本机磁盘（见上方“隐私”）；没有云同步。
- API Key 以本地文件形式保存，未使用钥匙串；若需要系统级密钥保护，应改回 Keychain 实现。
- 数学渲染覆盖常见 LaTeX；非常复杂的自定义宏，或在 `\text{}` 中混排中文时，可能受字体回退限制。

## 隐私

- API Key 存储在 `~/Library/Application Support/DeepSeekFocus/credentials.json`，目录权限 0700、文件权限 0600，不使用系统钥匙串。
- 这是有意的取舍：本地文件的保护强度低于钥匙串，同一 macOS 用户下的其他进程可能读取该文件。应用不会将其写入 UserDefaults、日志或对话历史。
- App 不包含第三方统计、崩溃上报或远程配置。
- 用户输入的文本、历史消息和搜索结果会发送给 `api.deepseek.com`，除此之外不会发送到其他地方。
- 会话历史仅保存在本机 `~/Library/Application Support/DeepSeekFocus/history.json`，目录权限 0700、文件权限 0600。

## 参与贡献

欢迎提交 Issue 和 Pull Request。提交前请至少运行：

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run CoreChecks
```

请注意不要提交真实的 API Key、`~/Library/Application Support/DeepSeekFocus` 下的本地历史，或包含个人对话的截图。

## 致谢

- [SwiftMath](https://github.com/mgriebling/SwiftMath)：原生 LaTeX 数学公式渲染（MIT）。
- [Pillow](https://python-pillow.org/)：图标生成脚本使用。

## 许可

代码以 MIT License 发布，见 [LICENSE](LICENSE)。

本项目使用 MIT 许可。数学公式渲染依赖 SwiftMath（MIT），其字体资源随 App 一起打包；第三方说明见 `Resources/THIRD_PARTY_NOTICES.txt`。DeepSeek 名称、鲸鱼标志及相关素材归 DeepSeek 所有；本项目是非官方工具，与 DeepSeek 不存在隶属或背书关系。
