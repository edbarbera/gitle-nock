import SwiftUI

/// The whole panel: a black slab pinned to the top of the screen that grows
/// downward out of the notch when the cursor arrives.
struct NotchRootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var viewModel: NotchViewModel

    var body: some View {
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
                .fill(Theme.shell)
                .shadow(color: .black.opacity(viewModel.isExpanded ? 0.5 : 0), radius: 18, y: 8)
        )
        .clipShape(NotchShape())
        // Anchor to the top of the panel; the panel itself never moves or resizes.
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
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
    }
}
