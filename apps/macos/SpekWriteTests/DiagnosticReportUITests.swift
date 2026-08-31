import AppKit
import XCTest
@testable import SpekWrite

private actor DiagnosticUIActionDelay {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func wait() async -> Bool {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
final class DiagnosticReportUITests: XCTestCase {
    func testDiscardGateDisablesBothActionsUntilDeleteFailureCompletes()
        async
    {
        let delay = DiagnosticUIActionDelay()
        let gate = DiagnosticReportActionGate()

        let discarding = Task { @MainActor in
            await gate.performDiscard { await delay.wait() }
        }
        await delay.waitUntilStarted()

        XCTAssertFalse(gate.areActionsEnabled)
        let duplicateAccepted = await gate.performDiscard { true }
        XCTAssertFalse(duplicateAccepted)
        XCTAssertFalse(gate.areActionsEnabled)

        await delay.finish(false)
        let completed = await discarding.value
        XCTAssertFalse(completed)
        XCTAssertTrue(gate.areActionsEnabled)
    }

    func testFiveStatesHaveExactApprovedChineseAndEnglishCopy() {
        let cases: [(TxChatLanguage, DiagnosticReportViewState, String, String, String)] = [
            (
                .simplifiedChinese,
                .prompt(isAbnormalExit: false),
                "TxChat 遇到问题",
                "刚才的操作未能完成。是否发送问题，帮助我们分析并改进？",
                "仅发送错误、版本、系统和操作阶段信息；不包含语音、识别文字、整理结果、手机号或密钥。"
            ),
            (
                .simplifiedChinese,
                .prompt(isAbnormalExit: true),
                "TxChat 上次意外退出",
                "已检测到上次运行发生异常。是否发送问题，帮助我们定位原因？",
                "不会自动上传；仅在你确认后发送经过脱敏的诊断信息。"
            ),
            (
                .simplifiedChinese,
                .sending,
                "正在发送问题…",
                "正在安全上传经过脱敏的错误日志，请稍候。",
                "发送完成前可以继续等待；不会要求填写问题描述。"
            ),
            (
                .simplifiedChinese,
                .sent("TX-23456789"),
                "问题已发送",
                "感谢你的帮助。问题编号 TX-23456789 可用于后续定位。",
                "本次仅上传经过脱敏的诊断信息。"
            ),
            (
                .simplifiedChinese,
                .failed(.unavailable),
                "发送失败",
                "暂时无法连接诊断服务，请检查网络连接后重试。",
                "如果选择暂不发送，本次错误日志将保留到本地诊断轮转期限结束。"
            ),
            (
                .english,
                .prompt(isAbnormalExit: false),
                "TxChat encountered an issue",
                "The last action could not be completed. Send an issue report to help us investigate and improve?",
                "Sends only error, version, system, and workflow-stage data—never audio, transcripts, organized text, phone numbers, or keys."
            ),
            (
                .english,
                .prompt(isAbnormalExit: true),
                "TxChat quit unexpectedly",
                "TxChat did not exit normally last time. Send an issue report to help us find the cause?",
                "Nothing is uploaded automatically. Redacted diagnostics are sent only after you confirm."
            ),
            (
                .english,
                .sending,
                "Sending issue…",
                "Securely uploading redacted diagnostic data. Please wait.",
                "You can keep waiting while it sends; no issue description is required."
            ),
            (
                .english,
                .sent("TX-23456789"),
                "Issue sent",
                "Thanks for helping. Report ID TX-23456789 can be used for follow-up.",
                "Only redacted diagnostic data was uploaded."
            ),
            (
                .english,
                .failed(.unavailable),
                "Couldn’t send",
                "The diagnostic service is unavailable. Check your connection and try again.",
                "If you choose Not Now, this diagnostic stays on this Mac until its local rotation period ends."
            ),
        ]

        for (language, state, title, body, caption) in cases {
            let content = DiagnosticReportContent.make(
                state: state,
                language: language
            )
            XCTAssertEqual(content.title, title)
            XCTAssertEqual(content.body, body)
            XCTAssertEqual(content.caption, caption)
        }
    }

    func testSendingHasOnlyDisabledSendingActionAndNoCancel() {
        let content = DiagnosticReportContent.make(
            state: .sending,
            language: .english
        )

        XCTAssertNil(content.secondaryActionTitle)
        XCTAssertEqual(content.primaryActionTitle, "Sending…")
        XCTAssertFalse(content.primaryActionEnabled)
    }

    func testFailedAccessibilityClarifiesDiscardAndLocalRingRotation() {
        let content = DiagnosticReportContent.make(
            state: .failed(.unavailable),
            language: .english
        )

        XCTAssertEqual(
            content.captionAccessibilityHint,
            "Not Now deletes the consented diagnostic report; only the " +
                "content-free local event ring remains until rotation."
        )
    }


    func testFailureCopyExplainsServerRejectionInsteadOfBlamingNetwork() {
        let invalid = DiagnosticReportContent.make(
            state: .failed(.invalidRequest),
            language: .simplifiedChinese
        )
        let tooLarge = DiagnosticReportContent.make(
            state: .failed(.tooLarge),
            language: .simplifiedChinese
        )
        let rateLimited = DiagnosticReportContent.make(
            state: .failed(.rateLimited(retryAfterSeconds: 45)),
            language: .simplifiedChinese
        )

        XCTAssertEqual(
            invalid.body,
            "诊断信息格式未通过校验，请稍后重试或暂不发送。"
        )
        XCTAssertEqual(
            tooLarge.body,
            "问题报告超过发送大小限制，暂时无法上传。"
        )
        XCTAssertEqual(
            rateLimited.body,
            "发送过于频繁，请等待 45 秒后重试。"
        )
    }

    func testWindowIsSingleBorderlessFixed480By280Controller() throws {
        let controller = DiagnosticReportWindowController(
            languageProvider: { .english },
            actions: .noOp,
            ordersWindow: false
        )

        controller.present(.prompt(isAbnormalExit: false))
        let firstWindow = try XCTUnwrap(controller.window)
        controller.present(.sending)

        XCTAssertTrue(firstWindow === controller.window)
        XCTAssertEqual(firstWindow.contentRect(forFrameRect: firstWindow.frame).size, CGSize(width: 480, height: 280))
        XCTAssertEqual(firstWindow.minSize, CGSize(width: 480, height: 280))
        XCTAssertEqual(firstWindow.maxSize, CGSize(width: 480, height: 280))
        XCTAssertEqual(firstWindow.styleMask, [.borderless])
        XCTAssertNil(firstWindow.standardWindowButton(.closeButton))
        XCTAssertNil(firstWindow.standardWindowButton(.miniaturizeButton))
        XCTAssertNil(firstWindow.standardWindowButton(.zoomButton))
        XCTAssertFalse(firstWindow.hidesOnDeactivate)
        XCTAssertTrue(firstWindow.isExcludedFromWindowsMenu)
    }

    func testLoginLaunchDefersDiagnosticWindowUntilExplicitOpen() {
        let gate = ProductInitialPresentationGate()
        gate.resolve(.background)
        var trace: [String] = []
        let controller = DiagnosticReportWindowController(
            languageProvider: { .simplifiedChinese },
            actions: .noOp,
            initialPresentationGate: gate,
            activateApplication: { trace.append("activate") },
            orderWindow: { _ in trace.append("order") }
        )

        controller.present(.prompt(isAbnormalExit: true))

        XCTAssertEqual(
            controller.presentedState,
            .prompt(isAbnormalExit: true)
        )
        XCTAssertTrue(trace.isEmpty)

        gate.allowPresentations()

        XCTAssertEqual(trace, ["activate", "order"])
    }

    func testDedicatedPaletteMatchesAllApprovedLightAndDarkTokens() {
        XCTAssertEqual(DiagnosticReportPalette.light.hexValues, [
            "#FFFCF8", "#111111", "#707070", "#DED8D0",
            "#171615", "#FBFAF8", "#2F8A4C", "#C94A45",
        ])
        XCTAssertEqual(DiagnosticReportPalette.dark.hexValues, [
            "#211F1D", "#FBFAF8", "#A9A29A", "#3A3733",
            "#FFFCF8", "#111111", "#65B979", "#E1736E",
        ])
    }
}
