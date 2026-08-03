import Cocoa
import FlutterMacOS

final class MytaskkingDesktopPlugin {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "mytaskking/desktop",
      binaryMessenger: controller.engine.binaryMessenger
    )
    let instance = MytaskkingDesktopPlugin()
    channel.setMethodCallHandler(instance.handle)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showWorkActivityPrompt":
      let args = call.arguments as? [String: Any]
      let seconds = (args?["seconds"] as? Int) ?? 30
      if Thread.isMainThread {
        result(Self.showWorkActivityPrompt(seconds: seconds))
      } else {
        DispatchQueue.main.sync {
          result(Self.showWorkActivityPrompt(seconds: seconds))
        }
      }
    case "getIdleSeconds":
      let anyInput = CGEventType(rawValue: ~0)!
      result(Int(CGEventSource.secondsSinceLastEventType(
        .combinedSessionState,
        eventType: anyInput
      )))
    case "captureFrames":
      let args = call.arguments as? [String: Any]
      let frameCount = min(max((args?["frameCount"] as? Int) ?? 1, 1), 12)
      let delayMs = max((args?["delayMs"] as? Int) ?? 0, 0)
      let maxWidth = max((args?["maxWidth"] as? Int) ?? 1280, 320)
      DispatchQueue.global(qos: .userInitiated).async {
        let paths = Self.captureFrames(
          frameCount: frameCount,
          delayMs: delayMs,
          maxWidth: maxWidth
        )
        DispatchQueue.main.async {
          result(paths)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func showWorkActivityPrompt(seconds: Int) -> String {
    var response = "working"
    var finished = false
    let panel = WorkActivityPromptPanel(seconds: max(seconds, 1)) { note in
      response = note.isEmpty ? "working" : note
      finished = true
    }
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    while !finished {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    return response
  }

  private static func captureFrames(
    frameCount: Int,
    delayMs: Int,
    maxWidth: Int
  ) -> [String] {
    if #available(macOS 10.15, *) {
      _ = CGPreflightScreenCaptureAccess()
      _ = CGRequestScreenCaptureAccess()
    }

    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("mytaskking-capture-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    } catch {
      return []
    }

    var paths: [String] = []
    for index in 0..<frameCount {
      let fileURL = tempDir.appendingPathComponent(String(format: "frame-%02d.png", index))
      if saveMainDisplayPng(to: fileURL, maxWidth: maxWidth) {
        paths.append(fileURL.path)
      }
      if index < frameCount - 1 && delayMs > 0 {
        Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0)
      }
    }
    return paths
  }

  private static func saveMainDisplayPng(to url: URL, maxWidth: Int) -> Bool {
    guard let screen = NSScreen.main else { return false }
    let frame = screen.frame
    guard let image = CGWindowListCreateImage(
      frame,
      .optionOnScreenOnly,
      kCGNullWindowID,
      .bestResolution
    ) else {
      return false
    }

    let width = image.width
    let height = image.height
    let targetWidth = min(width, maxWidth)
    let targetHeight = Int(Double(height) * (Double(targetWidth) / Double(width)))

    guard let context = CGContext(
      data: nil,
      width: targetWidth,
      height: targetHeight,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return false
    }

    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    guard let scaled = context.makeImage() else { return false }

    let rep = NSBitmapImageRep(cgImage: scaled)
    guard let data = rep.representation(using: .png, properties: [:]) else { return false }
    do {
      try data.write(to: url)
      return true
    } catch {
      return false
    }
  }
}

private final class WorkActivityPromptPanel: NSPanel, NSTextFieldDelegate, NSWindowDelegate {
  private var remaining: Int
  private var needsNote = false
  private var completed = false
  private let onComplete: (String) -> Void
  private var timer: Timer?
  private let messageLabel = NSTextField(labelWithString: "")
  private let entry = NSTextField(string: "")
  private let workingButton = NSButton(title: "I am working", target: nil, action: nil)
  private let submitButton = NSButton(title: "Submit update", target: nil, action: nil)

  init(seconds: Int, onComplete: @escaping (String) -> Void) {
    self.remaining = seconds
    self.onComplete = onComplete
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 430, height: 270),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    title = "MyTaskKing Work Check"
    level = .floating
    isFloatingPanel = true
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    delegate = self
    setupUI()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.tick()
    }
  }

  private func setupUI() {
    messageLabel.frame = NSRect(x: 20, y: 120, width: 390, height: 80)
    messageLabel.lineBreakMode = .byWordWrapping
    messageLabel.maximumNumberOfLines = 0
    contentView?.addSubview(messageLabel)

    entry.frame = NSRect(x: 20, y: 80, width: 390, height: 24)
    entry.placeholderString = "What are you working on?"
    entry.isHidden = true
    entry.delegate = self
    contentView?.addSubview(entry)

    workingButton.frame = NSRect(x: 220, y: 20, width: 110, height: 32)
    workingButton.target = self
    workingButton.action = #selector(workingTapped)
    contentView?.addSubview(workingButton)

    submitButton.frame = NSRect(x: 300, y: 20, width: 110, height: 32)
    submitButton.target = self
    submitButton.action = #selector(submitTapped)
    submitButton.isHidden = true
    contentView?.addSubview(submitButton)

    updateMessage()
    center()
  }

  private func updateMessage() {
    if needsNote {
      messageLabel.stringValue = "Please type a short update before continuing work."
      return
    }
    messageLabel.stringValue =
      "Click \"I am working\" or wait \(remaining) seconds for the note box."
  }

  private func tick() {
    if needsNote { return }
    remaining -= 1
    if remaining <= 0 {
      needsNote = true
      entry.isHidden = false
      workingButton.isHidden = true
      submitButton.isHidden = false
      window?.makeFirstResponder(entry)
    }
    updateMessage()
  }

  @objc private func workingTapped() {
    finish(note: "working")
  }

  @objc private func submitTapped() {
    finish(note: entry.stringValue)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    finish(note: "working")
    return false
  }

  private func finish(note: String) {
    if completed { return }
    completed = true
    timer?.invalidate()
    timer = nil
    orderOut(nil)
    onComplete(note.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  override func close() {
    timer?.invalidate()
    timer = nil
    super.close()
  }
}
