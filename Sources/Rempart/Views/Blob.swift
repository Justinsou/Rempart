import SwiftUI

enum Mood: CaseIterable {
    case calm, happy, angry, sleepy, sad

    var center: Color {
        switch self {
        case .calm: Color(red: 0.04, green: 0.57, blue: 0.86)
        case .happy: Color(red: 1.0, green: 0.70, blue: 0.08)
        case .angry: Color(red: 0.90, green: 0.10, blue: 0.40)
        case .sleepy: Color(red: 0.98, green: 0.68, blue: 0.48)
        case .sad: Color(red: 0.60, green: 0.33, blue: 0.97)
        }
    }
    var edge: Color {
        switch self {
        case .calm: Color(red: 0.42, green: 0.78, blue: 0.96)
        case .happy: Color(red: 1.0, green: 0.82, blue: 0.30)
        case .angry: Color(red: 0.97, green: 0.45, blue: 0.60)
        case .sleepy: Color(red: 0.99, green: 0.78, blue: 0.62)
        case .sad: Color(red: 0.70, green: 0.50, blue: 0.98)
        }
    }
    var ink: Color {
        switch self {
        case .calm: Color(red: 0.10, green: 0.20, blue: 0.40)
        case .happy: Color(red: 0.45, green: 0.15, blue: 0.05)
        case .angry: Color(red: 0.30, green: 0.02, blue: 0.12)
        case .sleepy: Color(red: 0.55, green: 0.28, blue: 0.15)
        case .sad: Color(red: 0.20, green: 0.08, blue: 0.40)
        }
    }
}

struct BlobShape: Shape {
    var lobes = 8
    var amp: CGFloat = 0.05
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        let steps = 240
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let rad = r * (1 - amp + amp * CGFloat(cos(Double(lobes) * t)))
            let pt = CGPoint(x: c.x + rad * CGFloat(cos(t)), y: c.y + rad * CGFloat(sin(t)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct FaceView: View {
    let mood: Mood
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            let ink = mood.ink
            ZStack {
                switch mood {
                case .calm:
                    eyes(s, ink)
                    smile(s, ink, w: 0.10, y: 0.58, up: true)
                case .happy:
                    ForEach([0.36, 0.64], id: \.self) { x in
                        arc(s, x: x, y: 0.42, w: 0.09, up: true).stroke(ink, style: .init(lineWidth: s * 0.03, lineCap: .round))
                    }
                    Path { p in
                        let c = CGPoint(x: s * 0.5, y: s * 0.54)
                        p.addArc(center: c, radius: s * 0.07, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                        p.closeSubpath()
                    }.fill(ink)
                case .angry:
                    eyes(s, ink, y: 0.46, r: 0.03)
                    brow(s, x1: 0.30, y1: 0.36, x2: 0.42, y2: 0.41, ink)
                    brow(s, x1: 0.70, y1: 0.36, x2: 0.58, y2: 0.41, ink)
                    smile(s, ink, w: 0.06, y: 0.62, up: false)
                case .sleepy:
                    ForEach([0.38, 0.62], id: \.self) { x in
                        arc(s, x: x, y: 0.46, w: 0.06, up: false).stroke(ink, style: .init(lineWidth: s * 0.025, lineCap: .round))
                    }
                    smile(s, ink, w: 0.05, y: 0.62, up: false)
                case .sad:
                    eyes(s, ink, y: 0.46, r: 0.028)
                    smile(s, ink, w: 0.05, y: 0.62, up: false)
                }
            }
            .frame(width: s, height: s)
        }
    }

    private func eyes(_ s: CGFloat, _ ink: Color, y: CGFloat = 0.43, r: CGFloat = 0.045) -> some View {
        ZStack {
            Circle().fill(ink).frame(width: s * r * 2).position(x: s * 0.37, y: s * y)
            Circle().fill(ink).frame(width: s * r * 2).position(x: s * 0.63, y: s * y)
        }
    }
    private func arc(_ s: CGFloat, x: CGFloat, y: CGFloat, w: CGFloat, up: Bool) -> Path {
        Path { p in
            let d = s * 0.03 * (up ? -1 : 1)
            p.move(to: CGPoint(x: s * (x - w / 2), y: s * y))
            p.addQuadCurve(to: CGPoint(x: s * (x + w / 2), y: s * y),
                           control: CGPoint(x: s * x, y: s * y + d * 2))
        }
    }
    private func smile(_ s: CGFloat, _ ink: Color, w: CGFloat, y: CGFloat, up: Bool) -> some View {
        // up = sourire (courbe vers le bas), sinon moue
        Path { p in
            let d = s * 0.035 * (up ? 1 : -1)
            p.move(to: CGPoint(x: s * (0.5 - w / 2), y: s * y))
            p.addQuadCurve(to: CGPoint(x: s * (0.5 + w / 2), y: s * y),
                           control: CGPoint(x: s * 0.5, y: s * y + d * 2))
        }
        .stroke(ink, style: .init(lineWidth: s * 0.025, lineCap: .round))
    }
    private func brow(_ s: CGFloat, x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, _ ink: Color) -> some View {
        Path { p in
            p.move(to: CGPoint(x: s * x1, y: s * y1))
            p.addLine(to: CGPoint(x: s * x2, y: s * y2))
        }
        .stroke(ink, style: .init(lineWidth: s * 0.03, lineCap: .round))
    }
}

struct BlobView: View {
    var mood: Mood = .calm
    var size: CGFloat = 120
    var glow = true
    var float = true
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BlobShape()
                .fill(RadialGradient(colors: [mood.center, mood.edge], center: .center,
                                     startRadius: size * 0.05, endRadius: size * 0.55))
                .shadow(color: glow ? mood.center.opacity(0.45) : .clear, radius: size * 0.22)
            FaceView(mood: mood).frame(width: size, height: size)
            if mood == .sleepy {
                Text("z z").font(.system(size: size * 0.16, weight: .heavy, design: .rounded))
                    .foregroundStyle(mood.ink).offset(x: size * 0.32, y: -size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .offset(y: float && !reduceMotion ? (up ? -size * 0.03 : size * 0.03) : 0)
        .scaleEffect(float && !reduceMotion ? (up ? 1.02 : 0.98) : 1)
        .accessibilityHidden(true)
        .onAppear {
            guard float, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Double.random(in: 2.4...3.4)).repeatForever(autoreverses: true)) { up = true }
        }
    }
}
