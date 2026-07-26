import SwiftUI

/// The whole panel: a pane of glass pinned to the top of the screen that grows
/// downward out of the notch when the cursor arrives.
struct NotchRootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var settings: Settings

    @Namespace private var glassNamespace

    /// How far the collapsed slab spills out either side of the cutout while it
    /// is reporting something. Zero the rest of the time, so the app is
    /// invisible when it has nothing to say.
    private var activityWings: CGFloat {
        guard !viewModel.isExpanded, state.activity != nil else { return 0 }
        return viewModel.isRealNotch ? 320 : 0
    }

    private var collapsedWidth: CGFloat {
        viewModel.collapsedSize.width + activityWings
    }

    private var panelWidth: CGFloat {
        viewModel.isExpanded ? NotchWindowController.expandedSize.width : collapsedWidth
    }

    private var panelHeight: CGFloat {
        viewModel.isExpanded
            ? NotchWindowController.expandedSize.height
            : max(viewModel.collapsedSize.height, state.activity != nil ? 34 : 0)
    }

    /// The hardware cutout must stay black no matter the appearance setting — a
    /// translucent shell there would show as a lit rectangle instead of blending
    /// into the bezel. Only the wings, the fallback pill and the expanded menu
    /// get the material.
    private var showsMaterial: Bool {
        viewModel.isExpanded || !viewModel.isRealNotch || state.activity != nil
    }

    var body: some View {
        // `Theme` is static state, which SwiftUI cannot observe. Writing it here
        // — ahead of every token read below — and keying the tree on
        // `appearanceToken` is what makes a preference change actually repaint.
        let _ = Theme.apply(settings)

        VStack(spacing: 0) {
            collapsedBar

            if viewModel.isExpanded {
                MenuContentView()
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        // Both dimensions stated outright. Letting either side size to content made
        // the background and clip shape smaller than the laid-out content, which
        // silently cropped whatever a Spacer pushed to the bottom — the footer.
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .background(panelBackground)
        .clipShape(NotchShape())
        .overlay(panelRim)
        .shadow(
            color: .black.opacity(viewModel.isExpanded ? 0.42 : 0.18),
            radius: viewModel.isExpanded ? 30 : 10,
            y: viewModel.isExpanded ? 12 : 4
        )
        .animation(Theme.spring, value: viewModel.isExpanded)
        .animation(Theme.snap, value: activityWings)
        // Anchor to the top of the panel; the panel itself never moves or resizes.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.glassNamespace, glassNamespace)
        .id(settings.appearanceToken)
    }

    // MARK: - Shell

    @ViewBuilder
    private var panelBackground: some View {
        if showsMaterial {
            ZStack {
                PanelMaterial(strength: Theme.materialStrength)
                NotchShape().fill(Theme.panelScrim)
                // A faint wash of the accent across the top keeps the panel from
                // reading as plain grey glass without tinting the whole surface.
                NotchShape().fill(
                    LinearGradient(
                        colors: [Theme.accentWash, .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
        } else {
            NotchShape().fill(.black)
        }
    }

    @ViewBuilder
    private var panelRim: some View {
        if showsMaterial {
            NotchShape()
                .stroke(Theme.specular, lineWidth: 1)
                .opacity(viewModel.isExpanded ? 0.9 : 0.6)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Collapsed bar
    //
    // On a notched Mac this strip sits *behind* the cutout, so the middle of it
    // is never visible. Everything therefore hugs the far left and far right.

    /// Width to keep clear down the middle of the top strip. The cutout is
    /// physically on top of this row, so anything laid out under it is simply
    /// not there — text has to be given a hard boundary, not just centred away.
    private var cutoutGap: CGFloat {
        viewModel.isRealNotch ? viewModel.collapsedSize.width + 32 : 0
    }

    private var collapsedBar: some View {
        HStack(spacing: 0) {
            if viewModel.isExpanded {
                RepoSwitcherButton()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: cutoutGap)

                HStack(spacing: 8) {
                    if !state.status.branch.isEmpty {
                        Text(state.status.branch)
                            .font(Theme.display(11, .medium))
                            .foregroundStyle(Theme.textDim)
                            .lineLimit(1)
                            // Long branch names are usually ticket numbers at the
                            // front and the meaningful words at the back, so a
                            // middle ellipsis keeps both ends readable.
                            .truncationMode(.middle)
                    }
                    StatusDot(status: state.status, isRepo: state.activeRepo != nil)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if let activity = state.activity {
                ActivityWings(activity: activity, gap: cutoutGap)
            } else if !viewModel.isRealNotch {
                IdlePill(status: state.status, name: state.activeRepo?.name ?? "gitle")
            }
        }
        .legibleOnPanel()
        .padding(.horizontal, viewModel.isExpanded ? 18 : 12)
        .frame(height: max(viewModel.collapsedSize.height, viewModel.isExpanded ? 32 : 30))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Collapsed content

/// The project name in the expanded header, doubling as the way into the
/// project list — the one control that's always reachable from the top bar.
private struct RepoSwitcherButton: View {
    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        Button {
            state.screen = .repos
        } label: {
            HStack(spacing: 6) {
                Text(state.activeRepo?.name ?? "gitle nock")
                    .font(Theme.display(12.5, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(hovering ? Theme.surfaceHover : .clear))
        }
        .buttonStyle(.plain)
        .disabled(state.repos.isEmpty)
        .animation(Theme.hover, value: hovering)
        .onHover { hovering = $0 }
        .help("Switch project")
    }
}

/// What shows either side of the hardware cutout while something is happening.
/// Icon to the left of the notch, words to the right, the way a Live Activity
/// splits around it.
private struct ActivityWings: View {
    let activity: PanelActivity
    let gap: CGFloat

    @State private var spin = false

    private var tint: Color {
        switch activity.kind {
        case .working: return Theme.accent
        case .success: return Theme.good
        case .failure: return Theme.bad
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: activity.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(activity.kind == .working && spin ? 360 : 0))
                .animation(
                    activity.kind == .working && !Theme.reduceMotion
                        ? .linear(duration: 1.6).repeatForever(autoreverses: false)
                        : nil,
                    value: spin
                )
                .frame(width: 20, height: 20)
                .background(Circle().fill(tint.opacity(0.18)))
                // Both wings hug the cutout rather than the outer edges, so the
                // pair reads as one badge wrapped around the notch instead of
                // two things stranded at opposite ends of the screen.
                .frame(maxWidth: .infinity, alignment: .trailing)

            Color.clear.frame(width: gap > 0 ? gap : 10)

            Text(activity.text)
                .font(Theme.display(11.5, .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .transition(.opacity)
        .onAppear { spin = true }
    }
}

/// The resting look on a Mac with no cutout to hide in.
private struct IdlePill: View {
    let status: RepoStatus
    let name: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
            Text(name)
                .font(Theme.display(11, .medium))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
            Spacer(minLength: 0)
            StatusDot(status: status, isRepo: true)
        }
    }
}

/// One coloured dot summarising the repo, readable at a glance from the notch.
struct StatusDot: View {
    let status: RepoStatus
    var isRepo: Bool

    @State private var pulse = false

    private var color: Color {
        guard isRepo, status.isRepo else { return Theme.textFaint }
        if status.hasConflicts { return Theme.bad }
        if !status.isClean { return Theme.warn }
        if status.ahead > 0 || status.behind > 0 { return Theme.accent }
        return Theme.good
    }

    /// Only states that want something from the user breathe. A clean repo is
    /// a still, quiet dot.
    private var wantsAttention: Bool {
        isRepo && status.isRepo && (status.hasConflicts || !status.isClean)
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.9), radius: 3)
            .shadow(color: color.opacity(0.45), radius: 8)
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 1)
                    .scaleEffect(pulse ? 2.6 : 1)
                    .opacity(pulse ? 0 : 0.55)
            )
            .animation(
                wantsAttention && !Theme.reduceMotion
                    ? .easeOut(duration: 1.8).repeatForever(autoreverses: false)
                    : nil,
                value: pulse
            )
            .onAppear { pulse = wantsAttention }
            .onChange(of: wantsAttention) { _, wants in pulse = wants }
    }
}

// MARK: - Glass namespace

/// Shared namespace so glass surfaces can morph into one another across screen
/// changes instead of cross-fading as unrelated rectangles.
private struct GlassNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var glassNamespace: Namespace.ID? {
        get { self[GlassNamespaceKey.self] }
        set { self[GlassNamespaceKey.self] = newValue }
    }
}
