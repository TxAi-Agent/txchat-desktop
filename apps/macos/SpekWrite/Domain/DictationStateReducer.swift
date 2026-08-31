import Foundation

enum DictationStateReducer {
    static func reduce(
        state: DictationState,
        event: DictationEvent
    ) -> DictationTransition {
        switch (state, event) {
        case (.unavailable, .becameAvailable):
            return accept(.idle)

        case (.idle, .becameUnavailable(let availability)),
             (.completed, .becameUnavailable(let availability)),
             (.failed, .becameUnavailable(let availability)):
            return accept(.unavailable(availability))

        case (.starting, .becameUnavailable(let availability)),
             (.listening, .becameUnavailable(let availability)),
             (.finalizing, .becameUnavailable(let availability)),
             (.organizing, .becameUnavailable(let availability)),
             (.inserting, .becameUnavailable(let availability)),
             (.resultFallback, .becameUnavailable(let availability)):
            return accept(
                .unavailable(availability),
                effects: [.cancelSession]
            )

        case (.idle, .userStarted),
             (.completed, .userStarted),
             (.failed, .userStarted):
            return accept(.starting, effects: [.captureTarget])

        case (.starting, .targetCaptured),
             (.starting, .targetUnavailable):
            return accept(.starting, effects: [.startSession])

        case (.starting, .targetBlocked):
            return accept(
                .failed(.targetUnavailable),
                effects: [.releaseSession]
            )

        case (.starting, .sessionStarted):
            return accept(.listening(.empty))

        case (.listening, .partialReceived(let text)):
            return accept(
                .listening(.init(partialText: text))
            )

        case (.listening(let snapshot), .userStopped),
             (.listening(let snapshot), .maximumDurationReached):
            return accept(
                .finalizing(snapshot),
                effects: [.stopAndFinalize]
            )

        case (.finalizing, .finalReceived(let text))
            where isNonempty(text),
             (.organizing, .finalReceived(let text))
            where isNonempty(text):
            return accept(
                state,
                effects: [.prepareFinal(text: text)]
            )

        case (.finalizing, .organizingStarted):
            return accept(.organizing)

        case (.finalizing, .finalPrepared(let text)),
             (.organizing, .finalPrepared(let text))
            where isNonempty(text):
            return accept(
                .inserting(text: text),
                effects: [.insert(text: text)]
            )

        case (.finalizing, .finalPreparationFailed(let rawText)),
             (.organizing, .finalPreparationFailed(let rawText))
            where isNonempty(rawText):
            return accept(
                .inserting(text: rawText),
                effects: [.insert(text: rawText)]
            )

        case (.inserting, .insertionSucceeded):
            return accept(.completed, effects: [.releaseSession])

        case (.inserting(let text), .insertionFailed):
            return accept(
                .resultFallback(text: text)
            )

        case (.resultFallback(let text), .insertionRetried):
            return accept(
                .inserting(text: text),
                effects: [.insert(text: text)]
            )

        case (.resultFallback, .resultDismissed):
            return accept(.idle, effects: [.releaseSession])

        case (.completed, .resultDismissed),
             (.failed, .resultDismissed):
            return accept(.idle)

        case (.starting, .serviceFailed(let failure)),
             (.listening, .serviceFailed(let failure)),
             (.finalizing, .serviceFailed(let failure)),
             (.organizing, .serviceFailed(let failure)):
            return accept(.failed(failure), effects: [.cancelSession])

        case (.idle, .authenticationInvalidated(let availability)),
             (.completed, .authenticationInvalidated(let availability)),
             (.failed, .authenticationInvalidated(let availability)),
             (.unavailable, .authenticationInvalidated(let availability)):
            return accept(.unavailable(availability))

        case (.starting, .authenticationInvalidated(let availability)),
             (.listening, .authenticationInvalidated(let availability)),
             (.finalizing, .authenticationInvalidated(let availability)),
             (.organizing, .authenticationInvalidated(let availability)),
             (.inserting, .authenticationInvalidated(let availability)),
             (.resultFallback, .authenticationInvalidated(let availability)):
            return accept(
                .unavailable(availability),
                effects: [.cancelSession]
            )

        case (.starting, .userCancelled),
             (.listening, .userCancelled),
             (.finalizing, .userCancelled),
             (.organizing, .userCancelled):
            return accept(.idle, effects: [.cancelSession])

        case (.starting, .loggedOut),
             (.listening, .loggedOut),
             (.finalizing, .loggedOut),
             (.organizing, .loggedOut),
             (.inserting, .loggedOut),
             (.resultFallback, .loggedOut):
            return accept(
                .unavailable(.authenticationRequired),
                effects: [.cancelSession]
            )

        case (.idle, .loggedOut),
             (.completed, .loggedOut),
             (.failed, .loggedOut),
             (.unavailable, .loggedOut):
            return accept(.unavailable(.authenticationRequired))

        case (.starting, .applicationTerminated),
             (.listening, .applicationTerminated),
             (.finalizing, .applicationTerminated),
             (.organizing, .applicationTerminated),
             (.inserting, .applicationTerminated),
             (.resultFallback, .applicationTerminated):
            return accept(.idle, effects: [.cancelSession])

        default:
            return DictationTransition(
                state: state,
                effects: [],
                accepted: false
            )
        }
    }

    private static func accept(
        _ state: DictationState,
        effects: [DictationEffect] = []
    ) -> DictationTransition {
        DictationTransition(
            state: state,
            effects: effects,
            accepted: true
        )
    }

    private static func isNonempty(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
