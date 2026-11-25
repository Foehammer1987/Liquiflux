import Flutter
import UIKit

/// Apple TV services for Liquiflux on channel `liquiflux/tvos`. See README.md.
public final class LiquifluxTvosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "liquiflux/tvos", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(LiquifluxTvosPlugin(), channel: channel)
  }

  private static func topController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "defaultsGet":
      guard let key = args["key"] as? String else { return result(nil) }
      result(UserDefaults.standard.string(forKey: key))
    case "defaultsSet":
      guard let key = args["key"] as? String else { return result(nil) }
      if let value = args["value"] as? String {
        UserDefaults.standard.set(value, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
      result(nil)
    case "environment":
      // Dart's Platform.environment is empty on tvOS; launch switches are read here.
      guard let key = args["key"] as? String else { return result(nil) }
      result(ProcessInfo.processInfo.environment[key])
    case "keyboard":
      // The system keyboard, opened by a UITextField of our own: its Search key hands the
      // text back at once (flutter-tvos's keyboard proxy delivers it too late for a submit).
      let keyboard = KeyboardController(
        text: args["text"] as? String ?? "",
        placeholder: args["placeholder"] as? String,
        done: { text in result(text) })
      guard let top = Self.topController() else { return result(nil) }
      top.present(keyboard, animated: false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// An invisible screen whose only job is a text field that opens tvOS's full-screen keyboard.
/// It returns the text when the keyboard closes, by its Search key or by Menu alike (the
/// app searches either way, as it did with its own field).
final class KeyboardController: UIViewController, UITextFieldDelegate {
  private let field = UITextField()
  private var done: ((String?) -> Void)?

  init(text: String, placeholder: String?, done: @escaping (String?) -> Void) {
    self.done = done
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .overFullScreen
    field.text = text
    field.placeholder = placeholder
    field.returnKeyType = .search
    field.autocorrectionType = .no
    field.delegate = self
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    field.alpha = 0.01
    view.addSubview(field)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    field.becomeFirstResponder()
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    textField.resignFirstResponder()
    return true
  }

  func textFieldDidEndEditing(_ textField: UITextField) {
    let text = textField.text ?? ""
    let callback = done
    done = nil
    dismiss(animated: false) { callback?(text) }
  }
}
