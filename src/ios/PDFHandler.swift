import Foundation
import PDFKit
import UIKit

@objc(PDFHandler) class PDFHandler: CDVPlugin {
    @available(iOS 13.0, *)
    @objc(downloadFile:)
  func downloadFile(_ command: CDVInvokedUrlCommand) {
    guard let urlString = command.arguments[0] as? String,
      let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
      let url = URL(string: encoded) else {
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

      // UI and PDF setup logic starts here
      DispatchQueue.main.async {
        // Setup the PDF viewer container
        let vc = UIViewController()
        vc.view.backgroundColor = .white

        // Create and configure the PDF view
        let pdfView = PDFView(frame: self.viewController.view.bounds)
        pdfView.autoScales = true
        vc.view.addSubview(pdfView)

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
          pdfView.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor),
          pdfView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
          pdfView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
          pdfView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)
        ])

        // Persist the downloaded PDF to Application Support so it remains available for reopening
        let fileManager = FileManager.default
        let persistentURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(url.lastPathComponent)

        // Clean up old PDFs older than 7 days
        if let dirContents = try? fileManager.contentsOfDirectory(at: persistentURL.deletingLastPathComponent(), includingPropertiesForKeys: [.contentModificationDateKey], options: []) {
          let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
          for file in dirContents {
            if let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               modDate < sevenDaysAgo {
              try? fileManager.removeItem(at: file)
            }
          }
        }

        try? fileManager.createDirectory(at: persistentURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try? fileManager.removeItem(at: persistentURL)
        do {
          try fileManager.copyItem(at: localURL, to: persistentURL)
          let document = PDFDocument(url: persistentURL)
          pdfView.document = document

          // Add page indicator label
          let pageLabel = UILabel()
          pageLabel.translatesAutoresizingMaskIntoConstraints = false
          pageLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
          pageLabel.textColor = .white
          pageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
          pageLabel.layer.cornerRadius = 6
          pageLabel.layer.masksToBounds = true
          pageLabel.textAlignment = .center
          vc.view.addSubview(pageLabel)

          NSLayoutConstraint.activate([
            pageLabel.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            pageLabel.leadingAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            pageLabel.heightAnchor.constraint(equalToConstant: 24)
          ])

          // Observe page changes to update the label
          NotificationCenter.default.addObserver(forName: Notification.Name.PDFViewPageChanged, object: pdfView, queue: .main) { _ in
            let currentPage = pdfView.currentPage.flatMap { document?.index(for: $0) } ?? 0
            let total = document?.pageCount ?? 0
            pageLabel.text = "\(currentPage + 1) of \(total)"
          }
          // Trigger label for initial page
          let initialPage = pdfView.currentPage.flatMap { document?.index(for: $0) } ?? 0
          let total = document?.pageCount ?? 0
          pageLabel.text = "\(initialPage + 1) of \(total)"
        } catch {
          print("Failed to persist PDF file: \(error.localizedDescription)")
        }

        // Setup toolbar and buttons
        let share = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(self.sharePDF(_:)))
        let search = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(self.searchPDF(_:)))
        let printBtn = UIBarButtonItem(image: UIImage(systemName: "printer"), style: .plain, target: self, action: #selector(self.printPDF(_:)))
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbar.items = [share, spacer, search, spacer, printBtn]
        vc.view.addSubview(toolbar)

        NSLayoutConstraint.activate([
          toolbar.bottomAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.bottomAnchor),
          toolbar.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
          toolbar.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
          toolbar.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Setup navigation bar
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.dismissPDFView))
        vc.navigationItem.rightBarButtonItem = done
        let title = url.lastPathComponent
        vc.title = title.count > 30 ? String(title.prefix(27)) + "..." : title

        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        objc_setAssociatedObject(nav, &AssociatedKeys.documentURL, persistentURL, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
      // Search is not available on iOS PDFKit in this form; consider using a custom search UI or skip on older iOS
      // Placeholder: PDF search interaction would require custom implementation
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
