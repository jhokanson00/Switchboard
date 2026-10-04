import SwiftUI

/// CPU and GPU load side by side, at the top of the panel.
struct LoadMeters: View {
    let monitor: SystemMonitor

    var body: some View {
        HStack(spacing: 14) {
            Meter(label: "CPU", value: monitor.cpu)
            Meter(label: "GPU", value: monitor.gpu)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }
}

private struct Meter: View {
    let label: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * min(max(value ?? 0, 0), 1))
                        .animation(.easeOut(duration: 0.3), value: value)
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { "\(Int(($0 * 100).rounded())) percent" } ?? "Unknown")
    }

    private var color: Color {
        switch value ?? 0 {
        case ..<0.6: .accentColor
        case ..<0.85: .orange
        default: .red
        }
    }
}
