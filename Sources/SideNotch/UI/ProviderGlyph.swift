import SwiftUI

/// Small white provider mark drawn in code (no bundled assets).
struct ProviderGlyph: View {
    let glyph: ProviderInfo.Glyph
    var size: CGFloat = 20

    var body: some View {
        Group {
            switch glyph {
            case .claude:
                Starburst().stroke(.white, style: .init(lineWidth: size * 0.11, lineCap: .round))
            case .openAI:
                KnotFlower().stroke(.white, style: .init(lineWidth: size * 0.09, lineJoin: .round))
            case .openRouter:
                Monogram(text: "OR")
            case .deepSeek:
                Monogram(text: "DS")
            case let .monogram(text):
                Monogram(text: text)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Claude-style asterisk: 12 rays with alternating lengths.
private struct Starburst: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<12 {
            let angle = CGFloat(i) * .pi / 6
            let len = r * (i.isMultiple(of: 2) ? 1.0 : 0.62)
            p.move(to: CGPoint(x: c.x + cos(angle) * r * 0.15, y: c.y + sin(angle) * r * 0.15))
            p.addLine(to: CGPoint(x: c.x + cos(angle) * len, y: c.y + sin(angle) * len))
        }
        return p
    }
}

/// OpenAI-style knot: six elongated hexagonal petals rotated around the center.
private struct KnotFlower: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3
            var petal = Path(
                roundedRect: CGRect(x: -r * 0.28, y: -r, width: r * 0.56, height: r * 1.45),
                cornerRadius: r * 0.26
            )
            petal = petal.applying(CGAffineTransform(rotationAngle: angle))
            petal = petal.applying(CGAffineTransform(translationX: c.x, y: c.y))
            p.addPath(petal)
        }
        return p
    }
}

private struct Monogram: View {
    let text: String

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(.system(size: geo.size.height * 0.52, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
