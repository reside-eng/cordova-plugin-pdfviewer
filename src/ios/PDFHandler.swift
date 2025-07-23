
// src/ios/PDFHandler.swift
import Foundation
import PDFKit

@objc(PDFHandler) class PDFHandler: CDVPlugin {
  @objc(downloadFile:withCallbackId:)
  func downloadFile(command: CDVInvokedUrlCommand) {
    guard let urlString = command.arguments[0] as? String, let url = URL(string: urlString) else {
      self.commandDelegate?.send(CDVPluginResult(status: .error, messageAs: "Invalid URL"), callbackId: command.callbackId)
      return
    }

    let task = URLSession.shared.downloadTask(with: url) { localURL, _, error in
      guard let localURL = localURL, error == nil else {
        self.commandDelegate?.send(CDVPluginResult(status: .error, messageAs: error?.localizedDescription), callbackId: command.callbackId)
        return
      }

      DispatchQueue.main.async {
        let pdfView = PDFView(frame: self.viewController.view.bounds)
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: localURL)

        let vc = UIViewController()
        vc.view = pdfView
        self.viewController.present(vc, animated: true)

        self.commandDelegate?.send(CDVPluginResult(status: .ok, messageAs: "PDF opened successfully"), callbackId: command.callbackId)
      }
    }
    task.resume()
  }
}