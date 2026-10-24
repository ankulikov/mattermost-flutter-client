import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let clipboardChannel = FlutterMethodChannel(
      name: "mattermost/clipboard_files",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    clipboardChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "pasteFiles":
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil)?
          .compactMap { $0 as? URL }
          .filter { $0.isFileURL } ?? []
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let copied = try Self.copyClipboardFiles(Array(urls.prefix(6)))
            DispatchQueue.main.async { result(copied) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "clipboard_file_unavailable", message: "Copied file is unavailable", details: nil))
            }
          }
        }
      case "releaseFile":
        guard let path = call.arguments as? String else {
          result(FlutterError(code: "invalid_clipboard_file", message: nil, details: nil))
          return
        }
        DispatchQueue.global(qos: .utility).async {
          Self.releaseClipboardFile(path)
          DispatchQueue.main.async { result(nil) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private static let clipboardDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("mattermost-clipboard-uploads", isDirectory: true)

  private static func copyClipboardFiles(_ urls: [URL]) throws -> [[String: String]] {
    let manager = FileManager.default
    try manager.createDirectory(at: clipboardDirectory, withIntermediateDirectories: true)
    var copied: [[String: String]] = []
    do {
      for url in urls {
        let name = url.lastPathComponent
        guard !name.isEmpty else { continue }
        if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { continue }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let destination = clipboardDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
          .appendingPathComponent(name)
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: url, to: destination)
        copied.append(["path": destination.path, "name": name])
      }
      return copied
    } catch {
      for entry in copied {
        if let path = entry["path"] { releaseClipboardFile(path) }
      }
      throw error
    }
  }

  private static func releaseClipboardFile(_ path: String) {
    let file = URL(fileURLWithPath: path).standardizedFileURL
    guard file.deletingLastPathComponent().deletingLastPathComponent() == clipboardDirectory.standardizedFileURL else {
      return
    }
    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
  }
}
