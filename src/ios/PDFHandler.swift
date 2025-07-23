import Foundation
import PDFKit

@objc(PDFHandler) class PDFHandler: CDVPlugin {
  @objc(downloadFile:withCommand:)
  func downloadFile(command: CDVInvokedUrlCommand) {
    guard let urlString = command.arguments[0] as? String,
          let url = URL(string: urlString) else {
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid URL")
      self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
      return
    }

    let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
      guard let localURL = localURL, error == nil else {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: error?.localizedDescription)
        self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
        return
      }

      DispatchQueue.main.async {
        let pdfView = PDFView(frame: self.viewController.view.bounds)
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: localURL)

        let vc = UIViewController()
        vc.view = pdfView
        self.viewController.present(vc, animated: true, completion: nil)

        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "PDF opened successfully")
        self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
      }
    }
    task.resume()
  }
}