import SwiftUI

struct PasketToastOverlay: View {
    @Bindable var center: PasketToastCenter
    var onAction: (PasketToast.Action) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    private struct TimeoutIdentity: Equatable {
        let id: UUID?
        let isPaused: Bool
    }

    var body: some View {
        VStack {
            if let toast = center.current {
                card(toast)
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, 20)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9), value: center.current?.id)
        .task(id: TimeoutIdentity(id: center.current?.id, isPaused: isHovered || isAccessibilityFocused)) {
            guard !isHovered, !isAccessibilityFocused,
                  let toast = center.current, let duration = toast.duration else { return }
            do {
                try await Task.sleep(for: duration)
                try Task.checkCancellation()
                center.dismiss(id: toast.id)
            } catch {}
        }
        .onChange(of: center.current?.id, initial: true) {
            if let toast = center.current {
                AccessibilityNotification.Announcement("\(toast.title). \(toast.message)").post()
            }
        }
    }

    private func card(_ toast: PasketToast) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(for: toast.style))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint(for: toast.style))
                .frame(width: 30, height: 30)
                .background(tint(for: toast.style).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(toast.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(toast.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = toast.action {
                    Button(action.title) { onAction(action) }
                        .buttonStyle(PasketButtonStyle(hasBackground: true))
                        .font(.system(size: 12, weight: .medium))
                        .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PasketCloseButton(title: "Dismiss notification", help: "Dismiss notification") {
                center.dismiss(id: toast.id)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.15), radius: 16, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityFocused($isAccessibilityFocused)
        .accessibilityIdentifier("clipboardToast")
    }

    private func symbol(for style: PasketToast.Style) -> String {
        switch style {
        case .success: "checkmark.circle.fill"
        case .information: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    private func tint(for style: PasketToast.Style) -> Color {
        switch style {
        case .success: .green
        case .information: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }
}
