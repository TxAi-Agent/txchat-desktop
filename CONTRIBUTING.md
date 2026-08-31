# 为 TxChat Desktop 贡献代码 / Contributing to TxChat Desktop

[中文](#中文) | [English](#english)

## 中文

感谢你关注 TxChat Desktop。我们接受 Issue 和 Pull Request，但所有修改都必须经过维护者审核，提交并不保证会被合并。

### 开始之前

- 搜索现有 Issue，避免重复报告或重复实现。
- 对较大功能、协议变更、新依赖或明显的界面行为变化，请先创建 Issue 说明目的、范围和替代方案。
- 安全漏洞不要创建公开 Issue，请按照 [安全政策](SECURITY.md) 使用 GitHub Private Vulnerability Reporting。

### 可接受的贡献范围

- macOS 客户端缺陷修复；
- 确定性单元测试和回归测试；
- 可维护性、可访问性和隐私保护改进；
- 公开本地协议兼容性改进；
- 面向公开开发者的文档修正。

不接受生产服务配置、真实账号集成、签名、公证、更新发布、部署或内部运维内容。

### 隐私与公开内容要求

不得在源码、测试、提交信息、Issue、Pull Request、截图或日志中加入：

- Key、Token、账号、密码或登录凭据；
- 手机号、真实身份、录音、听写内容或其他个人数据；
- 真实服务地址、内部域名、内部 IP、路由或服务器信息；
- 私人 Keychain 数据、证书、签名、公证或更新密钥；
- 本机绝对路径、内部计划、发布、部署或运维资料。

示例必须使用合成数据、`127.0.0.1` 或保留测试域名。请考虑使用 GitHub 隐私邮箱，避免在 Git 提交历史中公开个人邮箱。

### 开发与验证

修改必须保持 macOS 14+、Apple Silicon、Swift 6 和 Xcode 26+ 兼容。

```bash
xcodegen generate --spec apps/macos/project.yml
xcodebuild build \
  -project apps/macos/SpekWrite.xcodeproj \
  -scheme SpekWrite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test \
  -project apps/macos/SpekWrite.xcodeproj \
  -scheme SpekWrite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

行为变化应包含能够稳定复现问题并验证修复的确定性测试。

### 同时修改桌面端与云端

如果修改影响 [TxChat Cloud](https://github.com/TxAi-Agent/txchat-cloud) 的公开本地协议，请在两个仓库分别提交范围清晰的 Pull Request，并互相链接。两个修改必须使用同一协议版本并通过各自测试，且不得引入生产接口或私有配置。

### Pull Request 清单

Pull Request 应说明：

- 修改目的和影响范围；
- 已执行的构建与测试及结果；
- 是否增加或变更第三方依赖；
- 是否影响协议、安全或隐私边界；
- 如有界面变化，提供不含私人信息的截图。

新增第三方代码、字体或资源前，必须确认许可证兼容，并更新适用的第三方声明。

### 许可与审核

提交贡献即表示你同意该贡献可以按照 Apache License 2.0 授权。当前不要求 CLA 或 DCO。维护者可以因安全、隐私、项目范围、测试不足或长期维护成本而拒绝修改。

---

## English

Thank you for your interest in TxChat Desktop. Issues and pull requests are welcome for review, but every change requires maintainer approval and submission does not guarantee acceptance.

### Before you start

- Search existing issues to avoid duplicate reports or implementations.
- Open an issue before a large feature, protocol change, new dependency, or material user-interface behavior change. Describe the goal, scope, and alternatives.
- Do not open a public issue for a vulnerability. Follow the [security policy](SECURITY.md) and use GitHub Private Vulnerability Reporting.

### Contribution scope

Appropriate contributions include:

- macOS client bug fixes;
- deterministic unit and regression tests;
- maintainability, accessibility, and privacy improvements;
- public-local protocol compatibility improvements; and
- corrections to public developer documentation.

Production service configuration, real-account integration, signing, notarization, update publication, deployment, and internal operations material are out of scope.

### Privacy and public-content requirements

Do not place any of the following in source, tests, commit messages, issues, pull requests, screenshots, or logs:

- keys, tokens, accounts, passwords, or login credentials;
- phone numbers, real identities, recordings, transcripts, or other personal data;
- real service addresses, internal domains, internal IP addresses, routes, or server information;
- private Keychain data, certificates, signing, notarization, or update keys; or
- machine-specific absolute paths or internal planning, release, deployment, or operations material.

Examples must use synthetic data, `127.0.0.1`, or reserved test domains. Consider using a GitHub privacy address so that a personal email is not published in Git history.

### Development and verification

Changes must remain compatible with macOS 14+, Apple Silicon, Swift 6, and Xcode 26+.

```bash
xcodegen generate --spec apps/macos/project.yml
xcodebuild build \
  -project apps/macos/SpekWrite.xcodeproj \
  -scheme SpekWrite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test \
  -project apps/macos/SpekWrite.xcodeproj \
  -scheme SpekWrite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

Behavior changes should include deterministic tests that reproduce the problem and verify the correction.

### Changes spanning desktop and cloud

If a change affects the public-local contract in [TxChat Cloud](https://github.com/TxAi-Agent/txchat-cloud), submit focused pull requests to both repositories and link them to each other. Both changes must use the same protocol version and pass their repository tests without introducing production interfaces or private configuration.

### Pull request checklist

A pull request should describe:

- its purpose and affected areas;
- the build and test commands run and their results;
- added or changed third-party dependencies;
- protocol, security, or privacy-boundary effects; and
- sanitized screenshots when user-interface behavior changes.

Before adding third-party code, fonts, or resources, verify license compatibility and update the applicable third-party notices.

### License and review

By submitting a contribution, you agree that it may be licensed under Apache License 2.0. This project currently requires neither a CLA nor a DCO. Maintainers may decline a change because of security, privacy, project scope, insufficient verification, or long-term maintenance cost.
