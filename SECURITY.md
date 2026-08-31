# TxChat Desktop 安全政策 / Security Policy

[中文](#中文) | [English](#english)

## 中文

### 支持范围

本政策只覆盖 `txchat-desktop` 公开仓库最新 `main` 分支中的源码。它不代表对 TxChat 生产服务、正式安装包、非公开系统或第三方服务提供安全支持。

与本公开源码相关的重点领域包括：

- macOS 本地权限、麦克风和输入处理；
- 会话及凭据存储逻辑；
- 协议解析和不可信输入验证；
- 诊断信息最小化与脱敏；
- Debug 本地开发连接的回环地址限制。

### 私下报告漏洞

请使用本仓库的 [GitHub Private Vulnerability Reporting](https://github.com/TxAi-Agent/txchat-desktop/security/advisories/new)。不要在公开 Issue、Discussion 或 Pull Request 中披露漏洞。

报告应包含：

- 受影响的仓库、提交和代码区域；
- 问题描述、攻击前提和潜在影响；
- 最小、可重复且已经脱敏的复现步骤；
- 已执行的验证；
- 可行的修复建议（如有）。

报告不得包含真实 Key、Token、账号、密码、用户数据、录音、听写内容、服务地址、内部网络信息、本机绝对路径、Keychain 导出、证书、签名或公证资料。

### 研究边界

请仅在研究人员拥有或明确控制的本地环境中开展安全测试。本政策不授权访问、扫描、攻击、干扰或测试任何真实 TxChat 服务、用户账号、用户设备或第三方系统。

如果问题只能在非公开生产系统中复现，请不要把生产地址、账号、日志或其他敏感证据上传到 GitHub。本仓库的安全政策不提供生产事件报告渠道。

请在维护者完成评估和必要修复前避免公开披露。当前没有漏洞赏金计划，也不承诺固定的确认、回复或修复时间。

---

## English

### Supported scope

This policy covers only source in the latest `main` branch of the public `txchat-desktop` repository. It does not provide security support for TxChat production services, signed installation packages, non-public systems, or third-party services.

Relevant public-source areas include:

- macOS local permissions, microphone handling, and input handling;
- session and credential-storage logic;
- protocol parsing and validation of untrusted input;
- diagnostic data minimization and redaction; and
- loopback enforcement for the Debug local development connector.

### Report a vulnerability privately

Use this repository's [GitHub Private Vulnerability Reporting](https://github.com/TxAi-Agent/txchat-desktop/security/advisories/new). Do not disclose a vulnerability in a public issue, discussion, or pull request.

A report should include:

- the affected repository, commit, and code area;
- a description, attack prerequisites, and potential impact;
- a minimal, reproducible, and sanitized reproduction;
- verification already performed; and
- a possible repair, if available.

Do not include real keys, tokens, accounts, passwords, user data, recordings, transcripts, service addresses, internal network information, machine-specific absolute paths, Keychain exports, certificates, signing, or notarization material.

### Research boundaries

Conduct security testing only in a local environment owned or explicitly controlled by the researcher. This policy does not authorize accessing, scanning, attacking, disrupting, or testing any real TxChat service, user account, user device, or third-party system.

If an issue can be reproduced only against a non-public production system, do not upload production addresses, accounts, logs, or other sensitive evidence to GitHub. This repository policy does not provide a production incident-reporting channel.

Avoid public disclosure until the maintainers have assessed the report and completed any necessary repair. There is currently no bug bounty program and no guaranteed acknowledgement, response, or repair time.
