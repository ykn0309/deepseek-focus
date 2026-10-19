# DeepSeek 聚焦

[English](README.md) | **简体中文**

<p align="center">
  <img src="Resources/AppIconRounded.png" width="104" alt="DeepSeek 聚焦图标">
</p>

<p align="center">像聚焦搜索一样，随时向 DeepSeek 提问。</p>

DeepSeek 聚焦是一个原生 macOS 菜单栏应用。按下全局快捷键，就能在任意应用上方打开一个悬浮搜索面板，直接提问并继续多轮对话，不用切换窗口。

> **非官方项目**：这是个人开发的第三方 DeepSeek 客户端，与 DeepSeek 官方没有隶属或合作关系。API 使用和搜索计费由使用者自行承担。

## 界面

<p align="center">
  <img src="Resources/screenshots/query.jpg" width="49%" alt="聚焦搜索式 DeepSeek 输入框">
  <img src="Resources/screenshots/conversation.jpg" width="49%" alt="带历史侧边栏的 DeepSeek 会话">
</p>

## 下载

从 [GitHub Releases](https://github.com/ykn0309/deepseek-focus/releases/latest) 下载 DMG，打开后把 `DeepSeek Focus.app` 拖进 **Applications**。

当前版本使用 ad-hoc 签名，没有经过 Apple 公证。首次启动如被系统拦截，请右键点击 App 选择 **打开**，或在 **系统设置 → 隐私与安全性** 中允许。

## 功能

- **聚焦搜索式界面**：全局快捷键唤出悬浮面板，默认 `⌥ Space`。
- **菜单栏入口**：左键搜索，右键打开设置、检查更新和退出；支持开机自启动与隐藏菜单栏图标。
- **流式回答**：展示思考过程、Markdown、代码块、表格、引用、来源和 LaTeX 公式。
- **多轮对话**：每个会话可单独选择模型、推理等级和联网搜索。
- **历史会话**：搜索、恢复、重命名和删除最多 50 个本地会话。
- **官方模型列表**：验证 API Key 后同步可用模型和推理档位。
- **中英文界面**：默认跟随系统语言；系统提示词跟随界面语言，模型回答仍匹配你的提问语言。每个会话会固定使用创建时的语言，之后切换界面语言只影响新会话。
- **应用内更新**：在设置页或菜单栏检查；发现新版本后直接下载、校验并安装，自动重启，无需跳转 GitHub 手动下载。
- **选区快捷操作**：在任意应用选中文字，按选区快捷键后选择「问 DeepSeek」「翻译」或「查词」。结果在选区附近的小浮窗中显示；翻译和查词不会保存到历史。需要授予 macOS 辅助功能权限。
- **独立配置**：三个选区功能分别配置模型、思考强度和联网搜索。翻译和查词默认关闭思考，问 DeepSeek 默认开启联网搜索；整个选区快捷操作也可以关闭。
- **翻译目标语言**：默认跟随系统语言，可设置中文或 English。

## 版本号

从 **v1.9** 开始，公开版本使用两位版本号，例如 `v1.9`、`v1.10`。构建号只作为内部编号，在「关于」中显示。已有的 `v1.8.x` 版本保留原编号，不会重命名。

## 系统要求

- macOS 13 Ventura 或更高版本
- 一个可用的 DeepSeek API Key
- 只有从源码构建时才需要 Swift 5.9+

## 使用

1. 打开应用，在设置中填入 DeepSeek API Key。未配置 Key 时，快捷键和左键点击菜单栏图标都会直接打开设置，而不是初始输入框。
2. 点击 **验证并同步**，选择默认模型、推理等级和联网搜索方式。
3. 设置全局快捷键，默认是 `⌥ Space`。
4. 在任意界面按快捷键，输入问题后按 `Return` 发送。

### 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 唤起 / 收起面板 | `⌥ Space`（可修改） |
| 从初始输入框展开 | `⌘ ↩`（可修改） |
| 显示 / 隐藏侧边栏 | `⌘ \`（可修改） |
| 选区查询 / 翻译 | `⌥ D`（可修改） |
| 发送 | `Return` |
| 换行 | `Shift + Return` |
| 新对话 | `⌘ N` |
| 打开设置 | `⌘ ,` |
| 收起面板 | `Esc` |

## 隐私

- API Key 只保存在这台 Mac 上，除了发送给 DeepSeek 外不会传到其他地方。
- 没有账号系统、遥测、统计 SDK 或中转服务器。
- 历史会话保存在本机；对话只会发送给 `api.deepseek.com`。
- 检查更新和下载会访问 GitHub，不会包含 API Key 或对话内容。

## 从源码构建

```bash
git clone https://github.com/ykn0309/deepseek-focus.git
cd deepseek-focus
./scripts/build_app.sh
```

SDK 配置、测试、API 行为、本地数据细节和打包方式见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 许可

MIT，见 [LICENSE](LICENSE) 和 [第三方说明](Resources/THIRD_PARTY_NOTICES.txt)。
