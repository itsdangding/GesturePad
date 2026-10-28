import AppKit
import SwiftUI

/// Liquid Glass on macOS 26, frosted material before that.

/// A blurred view of whatever is behind the window.
struct WindowBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

extension View {
    /// Frosted window background that lets the desktop show through.
    @ViewBuilder
    func frostedWindow() -> some View {
        if #available(macOS 15, *) {
            self
                .containerBackground(for: .window) { Color.clear }
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self.background(WindowBackdrop().ignoresSafeArea())
        }
    }

    /// A glass panel in the given shape.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .background(tint?.opacity(0.12) ?? .clear, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18)))
        }
    }

    /// A glass capsule, for small status pills.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: false), in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
        }
    }

    /// Glass button style, falling back to the bordered styles.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// Lets the frosted window show through a grouped form.
    /// Buttons without their own style become glass buttons.
    func glassForm() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .glassButton()
    }

    /// A tinted glass card. Put it in a section header, which has no box of its own.
    func glassHeaderCard(tint: Color = .brand) -> some View {
        self
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassPanel(cornerRadius: 22, tint: nil)
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.bottom, 14)
    }

    /// Glass only when `active` is true, for highlights that come and go.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat, tint: Color?, active: Bool) -> some View {
        if active {
            self.glassPanel(cornerRadius: cornerRadius, tint: tint)
        } else {
            self
        }
    }

    @available(macOS 26, *)
    fileprivate static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}
