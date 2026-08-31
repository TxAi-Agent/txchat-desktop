import XCTest
@testable import SpekWrite

final class DictationStateReducerTests: XCTestCase {
    func testIdleStartImmediatelyBecomesStartingAndCapturesOneTarget() {
        let transition = DictationStateReducer.reduce(
            state: .idle,
            event: .userStarted(mode: .smart)
        )

        XCTAssertEqual(transition.state, .starting)
        XCTAssertEqual(transition.effects, [.captureTarget])
        XCTAssertTrue(transition.accepted)
    }

    func testBusyStartIsRejectedWithoutEffects() {
        assertRejected(
            state: .starting,
            event: .userStarted(mode: .verbatim)
        )
        assertRejected(
            state: .listening(.empty),
            event: .userStarted(mode: .smart)
        )
    }

    func testUnavailableTargetStillStartsTheSession() {
        let transition = DictationStateReducer.reduce(
            state: .starting,
            event: .targetUnavailable
        )

        XCTAssertEqual(transition.state, .starting)
        XCTAssertEqual(transition.effects, [.startSession])
        XCTAssertTrue(transition.accepted)
    }

    func testBlockedTargetNeverStartsCaptureOrNetwork() {
        let transition = DictationStateReducer.reduce(
            state: .starting,
            event: .targetBlocked
        )

        XCTAssertEqual(transition.state, .failed(.targetUnavailable))
        XCTAssertEqual(transition.effects, [.releaseSession])
        XCTAssertTrue(transition.accepted)
        XCTAssertFalse(transition.effects.contains(.startSession))
    }

    func testPartialOnlyReplacesListeningSnapshot() {
        let transition = DictationStateReducer.reduce(
            state: .listening(.init(partialText: "old")),
            event: .partialReceived("new")
        )

        XCTAssertEqual(
            transition.state,
            .listening(.init(partialText: "new"))
        )
        XCTAssertTrue(transition.effects.isEmpty)
        XCTAssertTrue(transition.accepted)

        assertRejected(
            state: .finalizing(.init(partialText: "old")),
            event: .partialReceived("late")
        )
    }

    func testStopAndMaximumDurationShareOneFinalizingEffect() {
        let snapshot = TranscriptSnapshot(partialText: "hypothesis")

        for event in [
            DictationEvent.userStopped,
            .maximumDurationReached,
        ] {
            let transition = DictationStateReducer.reduce(
                state: .listening(snapshot),
                event: event
            )

            XCTAssertEqual(transition.state, .finalizing(snapshot))
            XCTAssertEqual(transition.effects, [.stopAndFinalize])
            XCTAssertTrue(transition.accepted)
        }

        assertRejected(
            state: .finalizing(snapshot),
            event: .userStopped
        )
        assertRejected(
            state: .finalizing(snapshot),
            event: .maximumDurationReached
        )
    }

    func testFinalIsPreparedOnlyWhileFinalizing() {
        let finalizing = DictationState.finalizing(
            .init(partialText: "hypothesis")
        )
        let transition = DictationStateReducer.reduce(
            state: finalizing,
            event: .finalReceived("确认文本")
        )

        XCTAssertEqual(transition.state, finalizing)
        XCTAssertEqual(
            transition.effects,
            [.prepareFinal(text: "确认文本")]
        )
        XCTAssertTrue(transition.accepted)

        assertRejected(state: finalizing, event: .finalReceived("  "))
        assertRejected(state: .idle, event: .finalReceived("过早"))
    }

    func testCloudOrganizingBecomesDistinctStateAndStillAcceptsFinal() {
        let snapshot = TranscriptSnapshot(partialText: "hypothesis")
        let organizing = DictationStateReducer.reduce(
            state: .finalizing(snapshot),
            event: .organizingStarted
        )

        XCTAssertEqual(organizing.state, .organizing)
        XCTAssertTrue(organizing.effects.isEmpty)

        let final = DictationStateReducer.reduce(
            state: organizing.state,
            event: .finalReceived("fixture final")
        )
        XCTAssertEqual(final.state, .organizing)
        XCTAssertEqual(
            final.effects,
            [.prepareFinal(text: "fixture final")]
        )
    }

    func testPreparedFinalIsInsertedExactlyOnce() {
        let transition = DictationStateReducer.reduce(
            state: .finalizing(.empty),
            event: .finalPrepared("准备完成")
        )

        XCTAssertEqual(transition.state, .inserting(text: "准备完成"))
        XCTAssertEqual(transition.effects, [.insert(text: "准备完成")])
        XCTAssertTrue(transition.accepted)

        assertRejected(
            state: transition.state,
            event: .finalPrepared("重复")
        )
    }

    func testInsertionFailureRetainsOnlyConfirmedFinal() {
        let transition = DictationStateReducer.reduce(
            state: .inserting(text: "只保留终稿"),
            event: .insertionFailed
        )

        XCTAssertEqual(
            transition.state,
            .resultFallback(text: "只保留终稿")
        )
        XCTAssertTrue(transition.effects.isEmpty)
        XCTAssertTrue(transition.accepted)

        let retried = DictationStateReducer.reduce(
            state: transition.state,
            event: .insertionRetried
        )
        XCTAssertEqual(retried.state, .inserting(text: "只保留终稿"))
        XCTAssertEqual(retried.effects, [.insert(text: "只保留终稿")])
        XCTAssertTrue(retried.accepted)

        let dismissed = DictationStateReducer.reduce(
            state: transition.state,
            event: .resultDismissed
        )
        XCTAssertEqual(dismissed.state, .idle)
        XCTAssertEqual(dismissed.effects, [.releaseSession])
        XCTAssertTrue(dismissed.accepted)
    }

    func testAuthenticationInvalidationClearsContentAndBecomesUnavailable() {
        for state in contentBearingStates {
            let transition = DictationStateReducer.reduce(
                state: state,
                event: .authenticationInvalidated(.sessionReplaced)
            )

            XCTAssertEqual(
                transition.state,
                .unavailable(.sessionReplaced)
            )
            XCTAssertEqual(transition.effects, [.cancelSession])
            XCTAssertTrue(transition.accepted)
        }
    }

    func testUserCancelOnlyInterruptsStagesBeforeInsertionStarts() {
        let cancellableStates: [DictationState] = [
            .starting,
            .listening(.init(partialText: "partial")),
            .finalizing(.init(partialText: "partial")),
            .organizing,
        ]

        for state in cancellableStates {
            let transition = DictationStateReducer.reduce(
                state: state,
                event: .userCancelled
            )

            XCTAssertEqual(transition.state, .idle)
            XCTAssertEqual(transition.effects, [.cancelSession])
            XCTAssertTrue(transition.accepted)
        }

        assertRejected(
            state: .inserting(text: "final"),
            event: .userCancelled
        )
        assertRejected(
            state: .resultFallback(text: "final"),
            event: .userCancelled
        )
    }

    func testLogoutAndTerminationClearEveryContentBearingState() {
        let expectations: [(DictationEvent, DictationState)] = [
            (.loggedOut, .unavailable(.authenticationRequired)),
            (.applicationTerminated, .idle),
        ]
        for (event, expectedState) in expectations {
            for state in contentBearingStates {
                let transition = DictationStateReducer.reduce(
                    state: state,
                    event: event
                )

                XCTAssertEqual(transition.state, expectedState)
                XCTAssertEqual(transition.effects, [.cancelSession])
                XCTAssertTrue(transition.accepted)
            }
        }
    }

    func testLateAndDuplicateEventsProduceNoEffects() {
        assertRejected(state: .idle, event: .partialReceived("late"))
        assertRejected(state: .idle, event: .sessionStarted)
        assertRejected(state: .completed, event: .insertionSucceeded)
        assertRejected(
            state: .resultFallback(text: "final"),
            event: .insertionFailed
        )
    }

    private var contentBearingStates: [DictationState] {
        [
            .listening(.init(partialText: "partial")),
            .finalizing(.init(partialText: "partial")),
            .organizing,
            .inserting(text: "final"),
            .resultFallback(text: "final"),
        ]
    }

    private func assertRejected(
        state: DictationState,
        event: DictationEvent,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let transition = DictationStateReducer.reduce(
            state: state,
            event: event
        )
        XCTAssertEqual(transition.state, state, file: file, line: line)
        XCTAssertTrue(
            transition.effects.isEmpty,
            file: file,
            line: line
        )
        XCTAssertFalse(transition.accepted, file: file, line: line)
    }
}
