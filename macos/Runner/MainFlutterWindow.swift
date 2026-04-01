import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    self.setContentSize(NSSize(width: 1550, height: 800))
    self.minSize = NSSize(width: 1330, height: 400)
    if let screen = self.screen {
      let screenFrame = screen.visibleFrame
      let x = screenFrame.midX - 775
      let y = screenFrame.midY - 400
      self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
