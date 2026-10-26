import AppKit
import SwiftUI

// Visual monocromático: tudo em .primary (preto no claro, branco no escuro) sobre vidro translúcido.

enum Brand {
    static let menuIcon: NSImage = {
        let img = Bundle.main.image(forResource: "MenuIcon")
            ?? NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Sinapse")!
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }()

    static let logo: NSImage = {
        let img = Bundle.main.image(forResource: "LogoMark")
            ?? NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Sinapse")!
        img.isTemplate = true
        return img
    }()
}

/// Cor "invertida": fundo da janela, usada como texto sobre botões cheios.
let invertedColor = Color(nsColor: .windowBackgroundColor)

struct LogoMark: View {
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: Brand.logo)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

// MARK: - Botões

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration, prominent: true) }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration, prominent: false) }
}

private struct StyledButton: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .foregroundStyle(prominent ? invertedColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent ? Color.primary : Color.primary.opacity(0.08))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(Rectangle())
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .foregroundStyle(selected ? invertedColor : Color.primary)
                .background(Capsule().fill(selected ? Color.primary : Color.primary.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FooterButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(hover ? Color.primary : Color.secondary)
        .onHover { hover = $0 }
    }
}

// MARK: - Blocos

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.secondary)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2)))
    }
}

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

extension View {
    /// Cartão translúcido sutil.
    func card(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}
