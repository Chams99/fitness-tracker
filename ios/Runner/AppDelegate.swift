import Flutter
import MessageUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  MFMailComposeViewControllerDelegate {
  private var mailResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FitnessSupportMail") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "tn.dhibi.fitness_tracker/support", binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "compose" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self, self.mailResult == nil, MFMailComposeViewController.canSendMail(),
        let presenter = registrar.viewController, presenter.presentedViewController == nil,
        let args = call.arguments as? [String: String],
        let recipient = args["recipient"], let subject = args["subject"], let body = args["body"]
      else {
        result(false)
        return
      }

      let composer = MFMailComposeViewController()
      composer.mailComposeDelegate = self
      composer.setToRecipients([recipient])
      composer.setSubject(subject)
      composer.setMessageBody(body, isHTML: false)
      self.mailResult = result
      presenter.present(composer, animated: true)
    }
  }

  func mailComposeController(
    _ controller: MFMailComposeViewController,
    didFinishWith result: MFMailComposeResult,
    error: Error?
  ) {
    let reply = mailResult
    mailResult = nil
    controller.dismiss(animated: true) {
      reply?(result != .failed && error == nil)
    }
  }
}
