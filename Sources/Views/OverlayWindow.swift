import SwiftUI
import AppKit
import CoreGraphics

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
        positionWindowOnActiveScreen()
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
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 28),
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
    
    private func positionWindowOnActiveScreen() {
        guard let window = self.window else { return }
        
        let screen = getActiveScreen()
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        let windowWidth: CGFloat = 60
        let windowHeight: CGFloat = 28
        
        let yPosition = visibleFrame.maxY - windowHeight - 4
        let xPosition = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        
        window.setFrame(NSRect(x: xPosition, y: yPosition, width: windowWidth, height: windowHeight), display: true)
    }
    
    private func getActiveScreen() -> NSScreen {
        if let screen = getScreenOfFrontmostWindow() {
            return screen
        }
        
        if let builtIn = getBuiltInScreen() {
            return builtIn
        }
        
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }
    
    private func getScreenOfFrontmostWindow() -> NSScreen? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontmostApp.processIdentifier
        
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        
        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == pid,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                continue
            }
            
            let windowRect = CGRect(x: x, y: y, width: width, height: height)
            
            let windowCenter = NSPoint(x: windowRect.midX, y: windowRect.midY)
            
            for screen in NSScreen.screens {
                let flippedFrame = NSRect(
                    x: screen.frame.origin.x,
                    y: primaryScreenHeight - screen.frame.origin.y - screen.frame.height,
                    width: screen.frame.width,
                    height: screen.frame.height
                )
                if flippedFrame.contains(windowCenter) {
                    return screen
                }
            }
        }
        
        return nil
    }
    
    private func getBuiltInScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                if CGDisplayIsBuiltin(screenNumber) != 0 {
                    return screen
                }
            }
        }
        return nil
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
