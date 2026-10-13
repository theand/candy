import AppKit
import Testing

@testable import CandyKit

@Test @MainActor func lollipopStatusIconRendersWithTransparency() throws {
  let image = CandyApplication.statusIcon()
  #expect(image.isTemplate)
  #expect(image.size == NSSize(width: 18, height: 18))
  let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
  let bitmap = NSBitmapImageRep(cgImage: cgImage)
  #expect(bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0)
  let opaquePixels = (0..<bitmap.pixelsHigh).reduce(0) { count, y in
    count
      + (0..<bitmap.pixelsWide).filter {
        (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.5
      }.count
  }
  #expect(opaquePixels > 20 && opaquePixels < bitmap.pixelsWide * bitmap.pixelsHigh / 2)
}

@Test @MainActor func menuBarAppKeepsEditorCommandsAndReopensWindows() throws {
  let app = NSApplication.shared
  let previousPolicy = app.activationPolicy()
  let previousMenu = app.mainMenu
  let previousWindows = Set(app.windows.map(ObjectIdentifier.init))
  func editorWindows() -> [NSWindow] {
    app.windows.filter {
      $0.windowController is EditorWindow && !previousWindows.contains(ObjectIdentifier($0))
    }
  }
  let delegate = CandyApplication()
  defer {
    for window in editorWindows() { window.close() }
    if let item = delegate.statusItem { NSStatusBar.system.removeStatusItem(item) }
    app.mainMenu = previousMenu
    app.setActivationPolicy(previousPolicy)
  }
  delegate.applicationDidFinishLaunching(
    Notification(name: NSApplication.didFinishLaunchingNotification))
  #expect(app.activationPolicy() == .accessory)
  let item = try #require(delegate.statusItem)
  #expect(item.button?.image?.isTemplate == true)
  let menu = try #require(item.menu)
  #expect(menu.items.first?.action == #selector(CandyApplication.showEditor(_:)))
  #expect(menu.items.last?.action == #selector(NSApplication.terminate(_:)))
  let commands = menu.items.compactMap(\.submenu).flatMap(\.items).compactMap(\.action)
  #expect(commands.contains(#selector(CandyApplication.openDocument(_:))))
  #expect(commands.contains(#selector(EditorWindow.saveDocument(_:))))
  #expect(commands.contains(#selector(CandyApplication.undoDocument(_:))))
  let editor = try #require(editorWindows().first)
  editor.orderOut(nil)
  delegate.showEditor(nil)
  #expect(editor.isVisible)
  #expect(editorWindows().count == 1)
  editor.close()
  #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(app))
  delegate.showEditor(nil)
  #expect(editorWindows().contains { $0.isVisible })
}
