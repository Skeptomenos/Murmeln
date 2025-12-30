import SwiftUI
import AppKit

enum OverlayState {
    case idle
    case listening
    case processing
}

@MainActor
class OverlayWindowController: NSObject, ObservableObject {
    private var window: NSWindow?
    @Published var state: OverlayState = .idle
    @Published var audioLevel: Float = 0.0
    
    static let shared = OverlayWindowController()
    
    private override init() {
        super.init()
    }
    
    func show() {
        if window == nil {
            createWindow()
        }
        state = .listening
        window?.orderFrontRegardless()
    }
    
    func updateAudioLevel(_ level: Float) {
        self.audioLevel = level
    }
    
    func setProcessing() {
        state = .processing
    }
    
    func hide() {
        state = .idle
        window?.orderOut(nil)
    }
    
    private func createWindow() {
        let contentView = OverlayContentView(controller: self)
        let hostingView = NSHostingView(rootView: contentView)
        
        let windowWidth: CGFloat = 60
        let windowHeight: CGFloat = 28
        
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        let notchAreaHeight = screenFrame.height - visibleFrame.height - (screenFrame.height - visibleFrame.maxY)
        let yPosition = screenFrame.height - notchAreaHeight - windowHeight - 8
        let xPosition = (screenFrame.width - windowWidth) / 2
        
        let windowFrame = NSRect(x: xPosition, y: yPosition, width: windowWidth, height: windowHeight)
        
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.contentView = hostingView
        
        self.window = window
    }
}

struct OverlayContentView: View {
    @ObservedObject var controller: OverlayWindowController
    
    var body: some View {
        HStack(spacing: 6) {
            stateIcon
            
            if controller.state == .listening {
                AudioBarsView(audioLevel: controller.audioLevel)
            } else if controller.state == .processing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundGradient)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
    }
    
    private var stateIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(iconColor)
            .symbolEffect(.pulse, isActive: controller.state == .listening)
    }
    
    private var iconName: String {
        switch controller.state {
        case .idle: return "mic"
        case .listening: return "mic.fill"
        case .processing: return "sparkles"
        }
    }
    
    private var iconColor: Color {
        switch controller.state {
        case .idle: return .secondary
        case .listening: return .red
        case .processing: return .blue
        }
    }
    
    private var backgroundGradient: some ShapeStyle {
        .ultraThinMaterial
    }
}

struct AudioBarsView: View {
    let audioLevel: Float
    private let barCount = 5
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: index))
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.1), value: audioLevel)
            }
        }
        .frame(width: 22, height: 16)
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let normalizedLevel = min(1.0, audioLevel * 8)
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 16
        
        let indexFactor = Float(index) / Float(barCount - 1)
        let centerDistance = abs(indexFactor - 0.5) * 2
        let heightMultiplier = 1.0 - (centerDistance * 0.3)
        
        let dynamicHeight = CGFloat(normalizedLevel * heightMultiplier) * (maxHeight - baseHeight)
        return baseHeight + dynamicHeight
    }
    
    private func barColor(for index: Int) -> Color {
        let normalizedLevel = min(1.0, audioLevel * 8)
        let threshold = Float(index) / Float(barCount)
        
        if normalizedLevel > threshold {
            let intensity = (normalizedLevel - threshold) / (1.0 - threshold)
            return Color(
                red: Double(0.3 + intensity * 0.7),
                green: Double(0.8 - intensity * 0.5),
                blue: Double(0.3)
            )
        }
        return .gray.opacity(0.3)
    }
}
