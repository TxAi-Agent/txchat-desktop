# TxChat Desktop

[中文](#中文) | [English](#english)

## 中文

### 项目简介

TxChat Desktop 是一个使用 Swift 6 和 SwiftUI 编写的 macOS 听写客户端公开源码快照。它用于本地开发、代码审查、自动化测试，以及研究桌面听写客户端与本地开发服务之间的公开协议。

本仓库包含以下公开开发内容：

- 听写状态与工作流管理；
- 全局快捷键、听写浮层和文字插入逻辑；
- 词典纠错与相关设置；
- 流式听写协议与输入验证；
- 诊断信息的最小化与脱敏逻辑；
- 仅在 Debug 构建中启用的本地开发连接；
- 可由开发者自行扩展的模型服务协议、设置结构和错误诊断接口。

公开版本不包含任何可直接连接第三方模型服务的传输实现。通过内置提供商服务发起的调用会以“提供商未启用”失败关闭，不会发送模型凭据或建立第三方网络连接。

仓库不提供任何真实模型服务 Key、账号、服务地址或托管配置。公开代码中的接口不代表已经包含可用的生产服务。

### 适用人群

本仓库适合：

- macOS、Swift 或 SwiftUI 开发者；
- 研究桌面听写、快捷键、输入和状态管理架构的开发者；
- 开发或验证桌面端与本地服务协议的贡献者；
- 提交代码、测试、文档或安全改进的贡献者；
- 审查公开源码安全与隐私边界的研究人员。

### 不适用范围

本仓库不是已签名的最终用户安装包，也不能直接连接 TxChat 生产服务。它不包含生产账号认证、真实服务配置、更新源、证书、签名、公证、发布、部署或运维资料。

### 环境要求

- macOS 14 或更高版本；
- Apple Silicon Mac；
- Xcode 26 或更高版本；
- XcodeGen。

### 构建

生成 Xcode 项目：

```bash
xcodegen generate --spec apps/macos/project.yml
```

在不使用代码签名的情况下构建 Debug 版本：

```bash
xcodebuild build \
  -project apps/macos/SpekWrite.xcodeproj \
  -scheme SpekWrite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

### 测试

```bash
xcodebuild test \
  -project apps/macos/SpekWrite.xcodeproj \
  -scheme SpekWrite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

公开测试使用确定性的本地数据，不要求真实账号、真实服务、私人 Keychain 数据或隐私敏感硬件。

### 与 TxChat Cloud 配合使用

配套的本地开发服务位于 [TxChat Cloud](https://github.com/TxAi-Agent/txchat-cloud)。两个仓库配合后可运行和验证公开的本地开发链路，但不能替代 TxChat 生产环境。

1. 克隆两个仓库。
2. 先满足 `txchat-cloud` README 列出的环境要求（当前包括 Node.js 24，以及通过 Corepack 使用 pnpm 11.19.0），然后在 `txchat-cloud` 中安装依赖并选择一个本机非特权端口，例如 `41873`：

   ```bash
   corepack enable
   pnpm install --frozen-lockfile
   TXCHAT_PUBLIC_LOCAL_PORT=41873 pnpm dev
   ```

3. 在本仓库中生成 Xcode 项目。
4. 在 Xcode 的 Debug Run 配置中设置：

   ```text
   TXCHAT_PUBLIC_LOCAL_DEVELOPMENT=1
   TXCHAT_PUBLIC_LOCAL_PORT=41873
   ```

5. 构建并运行桌面端。桌面端和云端必须使用同一个端口。
6. 只使用非敏感测试内容验证本地链路。交互运行桌面端时，macOS 可能请求麦克风或输入相关权限。

桌面端会在内部使用 `127.0.0.1` 和指定端口构造 HTTP 与 WebSocket 地址；如果检测到除上述两个允许项之外的额外 `TXCHAT_PUBLIC_LOCAL_*` 环境字段，本地开发配置会被拒绝。该拒绝规则仅适用于这个环境变量前缀下的额外字段。Release 构建不会启用该本地连接。

公开云端只执行确定性的合成识别与文字整理，不连接真实模型、账号、数据库或托管基础设施。

### 参与贡献与安全报告

- 参与开发前请阅读 [贡献指南](CONTRIBUTING.md)。
- 安全问题请按照 [安全政策](SECURITY.md) 私下报告，不要公开漏洞细节。

### 许可证

TxChat 自有源码采用 [Apache License 2.0 官方英文许可证](LICENSE)。[中文说明](LICENSE.zh-CN.md) 仅用于辅助理解，如有歧义，以英文许可证为准。

第三方代码、字体和资源适用各自的许可证，详见 [第三方声明](apps/macos/SpekWrite/Resources/ThirdPartyNotices.txt)。

---

## English

### Overview

TxChat Desktop is a public source snapshot of a macOS dictation client written in Swift 6 and SwiftUI. It is intended for local development, code review, automated testing, and study of the public contract between the desktop client and the companion local development service.

The repository includes public development code for:

- dictation state and workflow management;
- global shortcuts, the dictation overlay, and text insertion;
- dictionary-based corrections and related settings;
- streaming dictation protocol handling and input validation;
- diagnostic data minimization and redaction;
- a local development connector enabled only in Debug builds; and
- model-service protocols, settings structures, and diagnostic interfaces that developers can extend.

The public version contains no transport implementation that connects directly to a third-party model service. Calls through the bundled provider service fail closed as unsupported without sending model credentials or opening a third-party network connection.

No real model-service key, account, service address, or hosted configuration is provided. The presence of an interface in the public source does not mean that a working production service is included.

### Intended audience

This repository is intended for:

- macOS, Swift, and SwiftUI developers;
- developers studying desktop dictation, shortcut, input, and state-management architecture;
- contributors developing or validating the desktop-to-local-service contract;
- contributors proposing code, tests, documentation, or security improvements; and
- security researchers reviewing the public source privacy boundary.

### What this repository is not

This repository is not a signed end-user installation package and cannot connect directly to TxChat production services. It contains no production account authentication, real service configuration, update feed, certificate, signing, notarization, release, deployment, or operations material.

### Requirements

- macOS 14 or later;
- an Apple Silicon Mac;
- Xcode 26 or later; and
- XcodeGen.

### Build

Generate the Xcode project:

```bash
xcodegen generate --spec apps/macos/project.yml
```

Build the Debug configuration without code signing:

```bash
xcodebuild build \
  -project apps/macos/SpekWrite.xcodeproj \
  -scheme SpekWrite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

### Test

```bash
xcodebuild test \
  -project apps/macos/SpekWrite.xcodeproj \
  -scheme SpekWrite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

The public tests use deterministic local data and require no real account, real service, private Keychain data, or privacy-sensitive hardware.

### Using TxChat Desktop with TxChat Cloud

The companion local development service is available in [TxChat Cloud](https://github.com/TxAi-Agent/txchat-cloud). Together, the repositories can run and validate the public local development flow. They do not reproduce the TxChat production environment.

1. Clone both repositories.
2. First meet the environment requirements listed in the `txchat-cloud` README (currently Node.js 24 and pnpm 11.19.0 through Corepack). Then install dependencies in `txchat-cloud` and choose an unprivileged local port, for example `41873`:

   ```bash
   corepack enable
   pnpm install --frozen-lockfile
   TXCHAT_PUBLIC_LOCAL_PORT=41873 pnpm dev
   ```

3. Generate the Xcode project in this repository.
4. Set these variables in the Xcode Debug Run configuration:

   ```text
   TXCHAT_PUBLIC_LOCAL_DEVELOPMENT=1
   TXCHAT_PUBLIC_LOCAL_PORT=41873
   ```

5. Build and run the desktop client. The desktop and cloud repositories must use the same port.
6. Use only non-sensitive test content. An interactive desktop run may cause macOS to request microphone or input-related permissions.

The desktop constructs its HTTP and WebSocket origins internally from `127.0.0.1` and the selected port. The local development configuration is rejected if any additional `TXCHAT_PUBLIC_LOCAL_*` environment field is present beyond the two allowed variables above. This rejection rule applies only to additional fields with that environment-variable prefix. Release builds do not enable this connector.

The public cloud service performs deterministic synthetic recognition and text organization only. It does not connect to real models, accounts, databases, or hosted infrastructure.

### Contributing and security reports

- Read the [contribution guide](CONTRIBUTING.md) before proposing a change.
- Report security issues privately under the [security policy](SECURITY.md). Do not disclose vulnerability details publicly.

### License

TxChat-owned source is licensed under the [official English Apache License 2.0](LICENSE). The [Chinese guide](LICENSE.zh-CN.md) is provided only as a reading aid. If the documents differ, the English license controls.

Third-party code, fonts, and resources remain under their respective licenses. See the [third-party notices](apps/macos/SpekWrite/Resources/ThirdPartyNotices.txt).
