import AppKit
import SwiftUI

struct PermissionRepairView: View {
    let presentation: PermissionRepairPresentation
    let cancel: () -> Void
    let repairPermission: () async -> Void
    let recheckPermission: () async -> Void
    @Environment(\.txChatLanguage) private var language

    var body: some View {
        TxChatDialogView(
            title: presentation.title,
            detail: presentation.detail,
            showsCancel: true,
            showsRecheck: true,
            primaryTitle: presentation.action,
            cancel: cancel,
            recheck: { Task { await recheckPermission() } },
            primaryAction: { Task { await repairPermission() } }
        )
        .background {
            PermissionRepairWindowAttachment()
                .frame(width: 0, height: 0)
        }
        .accessibilityIdentifier("permission-repair.screen")
    }
}

struct TxChatDialogView: View {
    let title: String
    let detail: String
    let showsCancel: Bool
    let showsRecheck: Bool
    let primaryTitle: String
    let cancel: () -> Void
    let recheck: () -> Void
    let primaryAction: () -> Void
    @Environment(\.txChatLanguage) private var language

    var body: some View {
        ZStack(alignment: .topLeading) {
            TxChatTheme.Palette.canvas

            TxChatBrandMark(size: 56)
                .offset(x: 212, y: 24)

            Text(title)
                .font(TxChatTheme.noto(23, weight: .bold))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 432, height: 34, alignment: .center)
                .offset(x: 24, y: 96)

            Text(detail)
                .font(TxChatTheme.dialogBody)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 420, height: 46, alignment: .top)
                .offset(x: 30, y: 138)

            HStack(spacing: 10) {
                if showsCancel {
                    Button(language.select("取消", "Cancel"), action: cancel)
                        .buttonStyle(TxChatSecondaryButtonStyle())
                }
                if showsRecheck {
                    Button(language.select("重新检查授权", "Recheck"), action: recheck)
                        .buttonStyle(TxChatSecondaryButtonStyle())
                        .accessibilityIdentifier("permission-repair.recheck")
                }
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(TxChatCompactPrimaryButtonStyle())
                    .accessibilityIdentifier("permission-repair.open-settings")
            }
            .fixedSize()
            .frame(width: 480, alignment: .center)
            .offset(x: 0, y: 200)
        }
        .frame(width: 480, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
        .accessibilityIdentifier("dialog.screen")
    }
}

@MainActor
enum PermissionRepairWindowConfigurator {
    static func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 480, height: 280))
        window.minSize = NSSize(width: 480, height: 280)
        window.maxSize = NSSize(width: 480, height: 280)
    }
}

private struct PermissionRepairWindowAttachment: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            PermissionRepairWindowConfigurator.configure(window)
        }
    }

    private final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                PermissionRepairWindowConfigurator.configure(window)
            }
        }
    }
}
