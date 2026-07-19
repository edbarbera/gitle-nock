import SwiftUI

/// The whole panel: a black slab pinned to the top of the screen that grows
/// downward out of the notch when the cursor arrives.
struct NotchRootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var settings: Settings

    /// The hardware cutout must stay black no matter the appearance setting —
    /// a light shell there would show as a visible rectangle instead of
    /// blending into the notch bezel. Only the fallback pill (no real notch)
    /// and the expanded menu follow light/dark.
    private var shellColor: Color {
        if !viewModel.isExpanded && viewModel.isRealNotch { return .black }
        return Theme.shell
    }

    var body: some View {
        // Theme's colors are static vars, not @Published, so they can't notify
        // SwiftUI on their own; setting this here (ahead of every Theme.x read
        // below) and forcing a fresh identity with `.id()` is what makes a
        // toggle in Settings actually repaint the panel.
        let _ = { Theme.mode = settings.useLightAppearance ? .light : .dark }()

        VStack(spacing: 0) {
            collapsedBar

            if viewModel.isExpanded {
                MenuContentView()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Both dimensions stated outright. Letting either side size to content made
        // the background and clip shape smaller than the laid-out content, which
        // silently cropped whatever a Spacer pushed to the bottom — the footer.
        .frame(
            width: viewModel.isExpanded
                ? NotchWindowController.expandedSize.width
                : viewModel.collapsedSize.width,
            height: viewModel.isExpanded
                ? NotchWindowController.expandedSize.height
                : viewModel.collapsedSize.height,
            alignment: .top
        )
        .background(
            NotchShape()
                .fill(shellColor)
                .shadow(color: .black.opacity(viewModel.isExpanded ? 0.5 : 0), radius: 18, y: 8)
        )
        .clipShape(NotchShape())
        // Anchor to the top of the panel; the panel itself never moves or resizes.
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .id(settings.useLightAppearance)
    }

    /// What's visible when the menu is shut. On a real notch this hides behind the
    /// hardware cutout; elsewhere it reads as a small pill.
    private var collapsedBar: some View {
        HStack(spacing: 8) {
            if viewModel.isExpanded {
                Text(state.activeRepo?.name ?? "gitle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                StatusDot(status: state.status, isRepo: state.activeRepo != nil)
            } else if !viewModel.isRealNotch {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                Text(state.activeRepo?.name ?? "gitle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                Spacer(minLength: 0)
                StatusDot(status: state.status, isRepo: state.activeRepo != nil)
            }
        }
        .padding(.horizontal, viewModel.isExpanded ? 16 : 12)
        .frame(height: max(viewModel.collapsedSize.height, 30))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// One coloured dot summarising the repo, readable at a glance from the notch.
struct StatusDot: View {
    let status: RepoStatus
    var isRepo: Bool

    private var color: Color {
        guard isRepo, status.isRepo else { return Theme.textFaint }
        if !status.isClean { return Theme.warn }
        if status.ahead > 0 || status.behind > 0 { return Theme.accent }
        return Theme.good
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.9), radius: 3)
            .shadow(color: color.opacity(0.45), radius: 7)
    }
}
