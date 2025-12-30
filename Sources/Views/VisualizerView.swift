import SwiftUI

struct VisualizerView: View {
    let audioLevel: Float
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: index))
                        .frame(width: 3, height: barHeight(for: index, maxHeight: geometry.size.height))
                }
            }
        }
        .frame(width: 20, height: 16)
    }
    
    private func barHeight(for index: Int, maxHeight: CGFloat) -> CGFloat {
        let normalizedLevel = min(1.0, audioLevel * 10)
        let threshold = Float(index) / 5.0
        let height = normalizedLevel > threshold ? maxHeight * CGFloat((normalizedLevel - threshold) * 2) : 2
        return max(2, min(maxHeight, height))
    }
    
    private func barColor(for index: Int) -> Color {
        let normalizedLevel = min(1.0, audioLevel * 10)
        let threshold = Float(index) / 5.0
        return normalizedLevel > threshold ? .green : .gray.opacity(0.3)
    }
}
