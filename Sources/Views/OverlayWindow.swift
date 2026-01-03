import SwiftUI
import AppKit
import CoreGraphics

enum OverlayState: Equatable {
    case idle
    case waiting
    case listening
    case locked
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
    
    func showAlways() {
        if window == nil {
            createWindow()
        }
        positionWindowOnActiveScreen()
        window?.orderFrontRegardless()
    }
    
    func show() {
        showAlways()
        state = .listening
    }
    
    func updateAudioLevel(_ level: Float) {
        self.audioLevel = level
    }
    
    func setProcessing() {
        state = .processing
    }
    
    func hide() {
        state = .idle
    }
    
    private func createWindow() {
        let contentView = MinimalLineIndicator(controller: self)
        let hostingView = NSHostingView(rootView: contentView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 50, height: 10),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.contentView = hostingView
        
        self.window = window
    }
    
    private func positionWindowOnActiveScreen() {
        guard let window = self.window else { return }
        
        let screen = getActiveScreen()
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        let windowWidth: CGFloat = 50
        let windowHeight: CGFloat = 10
        
        let yPosition = visibleFrame.maxY - windowHeight - 2
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

struct MinimalLineIndicator: View {
    @ObservedObject var controller: OverlayWindowController
    @State private var shimmerOffset: CGFloat = -1
    
    private let baseWidth: CGFloat = 40
    private let maxExpansion: CGFloat = 8
    
    var body: some View {
        ZStack {
            if controller.state == .processing {
                processingIndicator
            } else {
                audioIndicator
            }
        }
        .frame(width: baseWidth + maxExpansion, height: 4)
    }
    
    private var audioIndicator: some View {
        Capsule()
            .fill(lineColor)
            .frame(width: currentWidth, height: 2.5)
            .opacity(lineOpacity)
            .animation(.easeOut(duration: 0.08), value: controller.audioLevel)
            .animation(.easeInOut(duration: 0.25), value: controller.state)
    }
    
    private var processingIndicator: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.3),
                        .white.opacity(0.7),
                        .white.opacity(0.3)
                    ],
                    startPoint: UnitPoint(x: shimmerOffset, y: 0.5),
                    endPoint: UnitPoint(x: shimmerOffset + 0.4, y: 0.5)
                )
            )
            .frame(width: baseWidth, height: 2.5)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.4
                }
            }
            .onDisappear {
                shimmerOffset = -1
            }
    }
    
    private var currentWidth: CGFloat {
        switch controller.state {
        case .idle:
            return baseWidth * 0.5
        case .waiting:
            return baseWidth * 0.7
        case .listening, .locked:
            let expansion = CGFloat(min(1.0, controller.audioLevel * 4)) * maxExpansion
            return baseWidth + expansion
        case .processing:
            return baseWidth
        }
    }
    
    private var lineColor: Color {
        switch controller.state {
        case .idle, .waiting, .listening:
            return .white
        case .locked:
            return .orange
        case .processing:
            return .white
        }
    }
    
    private var lineOpacity: Double {
        switch controller.state {
        case .idle:
            return 0.15
        case .waiting:
            return 0.4
        case .listening, .locked:
            return 0.85
        case .processing:
            return 0.7
        }
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
