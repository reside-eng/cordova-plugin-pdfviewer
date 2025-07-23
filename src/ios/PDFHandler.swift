import Foundation
import PDFKit
import UIKit

@objc(PDFHandler) class PDFHandler: CDVPlugin {
  @objc(downloadFile:)
  func downloadFile(_ command: CDVInvokedUrlCommand) {
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
        vc.view.backgroundColor = .white
        vc.view.addSubview(pdfView)

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
          pdfView.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor),
          pdfView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
          pdfView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
          pdfView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)
        ])

        let share = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(self.sharePDF(_:)))
        let search = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(self.searchPDF(_:)))
        let printBtn = UIBarButtonItem(barButtonSystemItem: .print, target: self, action: #selector(self.printPDF(_:)))
        vc.navigationItem.rightBarButtonItems = [share, search, printBtn]

        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.dismissPDFView))
        vc.navigationItem.leftBarButtonItem = done

        let nav = UINavigationController(rootViewController: vc)
        objc_setAssociatedObject(nav, &AssociatedKeys.documentURL, localURL, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &AssociatedKeys.navigationController, nav, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        self.viewController.present(nav, animated: true, completion: nil)

        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "PDF opened successfully")
        self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
      }
    }
    task.resume()
    }

  @objc func dismissPDFView() {
    if let nav = objc_getAssociatedObject(self, &AssociatedKeys.navigationController) as? UINavigationController {
      nav.dismiss(animated: true, completion: nil)
    }
  }

  @objc func sharePDF(_ sender: UIBarButtonItem) {
    if let nav = self.viewController.presentedViewController as? UINavigationController,
       let url = objc_getAssociatedObject(nav, &AssociatedKeys.documentURL) as? URL {
      let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      nav.present(activityVC, animated: true)
    }
  }

  @objc func searchPDF(_ sender: UIBarButtonItem) {
    if let nav = self.viewController.presentedViewController as? UINavigationController,
       let pdfVC = nav.viewControllers.first,
       let pdfView = pdfVC.view.subviews.compactMap({ $0 as? PDFView }).first {
      pdfView.isFindEnabled = true
      pdfView.performFindPanelAction(.showFindPanel)
    }
  }

  @objc func printPDF(_ sender: UIBarButtonItem) {
    if let nav = self.viewController.presentedViewController as? UINavigationController,
       let url = objc_getAssociatedObject(nav, &AssociatedKeys.documentURL) as? URL {
      let printInfo = UIPrintInfo(dictionary: nil)
      printInfo.outputType = .general
      printInfo.jobName = url.lastPathComponent

      let printController = UIPrintInteractionController.shared
      printController.printInfo = printInfo
      printController.printingItem = url
      printController.present(animated: true)
    }
  }
}

fileprivate struct AssociatedKeys {
  static var documentURL = "documentURL"
  static var navigationController = "navigationController"
}