# Nexo Codex Skin

<p align="center">
  <strong>中文</strong> · <a href="./README.en.md">English</a>
</p>

<p align="center">
  <strong>NexoToken 为 Codex 桌面端打造的跨平台沉浸式皮肤助手</strong><br>
  原生界面保留 · 全窗口主题渲染 · macOS / Windows · 安全自动更新
</p>

<p align="center">
  <a href="https://nexotoken.net"><strong>进入 NexoToken</strong></a> ·
  <a href="https://github.com/18534516725/Codex-Dream-Skin/releases"><strong>下载换肤助手</strong></a>
</p>

> 这是 NexoToken 皮肤系统的客户端引擎仓库，不是公开主题下载站。安装包只包含换肤运行引擎，不打包 NexoToken 的付费皮肤原图或主题包。皮肤展示、资格判断和一键应用入口统一由 NexoToken 平台控制。

## 使用方式

1. 在 [NexoToken](https://nexotoken.net) 登录账号，进入平台提供的 Codex 皮肤页面。
2. 首次使用时，从 [GitHub Releases](https://github.com/18534516725/Codex-Dream-Skin/releases) 安装对应系统的换肤助手。
3. 回到 NexoToken 选择已获得使用资格的皮肤，点击“一键应用”。
4. 助手会校验固定主题编号、资源来源和图片完整性，完成应用并验证真实 Codex 窗口。

当前皮肤功能处于灰度测试阶段，NexoToken 页面仅向管理员开放。正式开放时，主题资格和充值赠送规则以平台页面为准。

## 下载安装

| 系统 | 安装包 | 图形安装说明 |
|---|---|---|
| macOS（Apple Silicon / Intel） | `CodexDreamSkin-vX.Y.Z.dmg` | [macOS 安装说明](./docs/install-macos.md) |
| Windows 10 / 11 | `CodexDreamSkin-Setup-vX.Y.Z.exe` | [Windows 安装说明](./docs/install-windows.md) |

普通用户不需要 clone 仓库，不需要安装 Node.js，也不需要手动执行 `.sh` 或 `.ps1`。安装后助手会定期检查本仓库的正式 Release；更新包通过版本、文件身份和 SHA-256 校验后才会安装，并尽量避免打断正在运行的 Codex。

## 这套助手做什么

- **完整主题化**：背景、侧边栏、顶部区域、输入框、选中态、弹窗和新窗口统一适配。
- **原生可交互**：不把假 UI 截图盖在界面上，Codex 原有按钮和操作保持可用。
- **跨平台一致**：macOS 与 Windows 共用 Theme V2 主题合同和视觉目录。
- **高清与动态**：支持 4K 静态背景，也支持经过限制和降级策略处理的动态媒体。
- **安全应用**：只接受固定格式的一键链接，不执行链接中的任意网址、文件路径或命令。
- **可验证恢复**：只有真实窗口确认主题已经渲染才报告成功；失败时保留恢复官方外观的路径。
- **自动更新**：旧助手遇到新主题合同会先引导更新，再继续应用。

## 分发边界

- 客户端菜单不提供外部主题库、在线 Studio 或第三方主题网站入口。
- GitHub Release 公开提供的是 macOS / Windows 换肤助手，不是 NexoToken 付费皮肤合集。
- NexoToken 固定皮肤通过平台页面发起，客户端只处理经过识别的主题编号。
- 本仓库不会修改用户的 API Key、Base URL、模型渠道或计费配置。

## 安全设计

- 只通过本机回环调试连接工作，不修改官方 `.app`、`app.asar` 或 WindowsApps。
- 图片、主题配置、Safe CSS、ZIP 与更新包都有大小、格式和完整性边界。
- 更新与换肤采用临时目录、事务替换和失败恢复，避免半写入状态。
- 不使用关闭系统安全功能的命令；首次运行未签名安装包时按安装文档完成系统图形确认。

## 开发与验证

| 平台 | 源码目录 | 主要入口 |
|---|---|---|
| macOS | [`macos/`](./macos/) | `Install Codex Dream Skin.command` |
| Windows | [`windows/`](./windows/) | `scripts/install-dream-skin.ps1` |

主要文档：

- [平台差异与路径](./docs/platforms.md)
- [macOS 开发说明](./macos/README.md)
- [Windows 开发说明](./windows/README.md)
- [项目架构记录](./docs/PROJECT.md)

提交改动前请运行对应平台测试，并确保 `tools/sync-runtime-assets.mjs --check` 通过。正式安装包只由 `main` 分支的自动发布流水线构建。

## 许可与声明

- 本项目是非 OpenAI 官方的外观增强工具；Codex、ChatGPT 及相关商标归其权利人所有。
- 开源许可见 [`macos/LICENSE`](./macos/LICENSE)，第三方来源和保留声明见 [`macos/NOTICE.md`](./macos/NOTICE.md)。
- 主题图片和人物/IP 素材必须在确认版权、肖像权和商用范围后才能进入公开分发。

---

NexoToken：模型调用与 Codex 工作空间体验，一套账号统一使用。
