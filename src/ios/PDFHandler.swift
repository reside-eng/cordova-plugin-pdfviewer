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
      // Handle file operations immediately to prevent temporary file cleanup
      let fileManager = FileManager.default
      
      // Create unique filename to avoid conflicts
      let timestamp = Int(Date().timeIntervalSince1970)
      let originalName = url.lastPathComponent
      let fileExtension = (originalName as NSString).pathExtension
      let baseName = (originalName as NSString).deletingPathExtension
      let uniqueFileName = "\(baseName)_\(timestamp).\(fileExtension)"
      let persistentURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(uniqueFileName)

      // Clean up old PDFs older than 7 days
      let applicationSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      if let dirContents = try? fileManager.contentsOfDirectory(at: applicationSupportDir, includingPropertiesForKeys: [.contentModificationDateKey], options: []) {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for file in dirContents {
          if let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
             modDate < sevenDaysAgo {
            try? fileManager.removeItem(at: file)
          }
        }
      }

      try? fileManager.createDirectory(at: applicationSupportDir, withIntermediateDirectories: true, attributes: nil)
      
      do {
        // Remove any existing file at the target location
        try? fileManager.removeItem(at: persistentURL)
        
        // Copy the downloaded file to persistent location IMMEDIATELY
        try fileManager.copyItem(at: localURL, to: persistentURL)
        
        // Verify the file was copied successfully with size validation
        guard fileManager.fileExists(atPath: persistentURL.path) else {
          print("Failed to copy file to persistent location: \(persistentURL)")
          let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to save PDF file")
          self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
          return
        }
        
        // Verify the copied file has content
        if let attributes = try? fileManager.attributesOfItem(atPath: persistentURL.path),
           let fileSize = attributes[.size] as? Int64 {
          print("PDF file copied successfully to: \(persistentURL.path), Size: \(fileSize) bytes")
          
          if fileSize == 0 {
            print("Error: Copied file is empty")
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Copied PDF file is empty")
            self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
            return
          }
        } else {
          print("Warning: Could not verify file size after copy")
        }
        
        // Small delay to ensure file system operations are complete
        Thread.sleep(forTimeInterval: 0.1)
        
        // Now move to main queue for UI operations
        DispatchQueue.main.async {
          // Setup the PDF viewer container
          let vc = UIViewController()
          vc.view.backgroundColor = .white

          // Create and configure the PDF view
          let pdfView = PDFView(frame: self.viewController.view.bounds)
          pdfView.autoScales = true
          vc.view.addSubview(pdfView)

          // Setup toolbar first so we can reference it in PDF view constraints
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

          pdfView.translatesAutoresizingMaskIntoConstraints = false
          NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)
          ])

          // Additional debugging and validation before creating PDF document
          print("Attempting to create PDFDocument from URL: \(persistentURL)")
          print("File exists at path: \(fileManager.fileExists(atPath: persistentURL.path))")
          
          // Check file size
          if let fileAttributes = try? fileManager.attributesOfItem(atPath: persistentURL.path),
             let fileSize = fileAttributes[.size] as? Int64 {
            print("File size: \(fileSize) bytes")
            
            if fileSize == 0 {
              print("Error: PDF file is empty (0 bytes)")
              let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "PDF file is empty")
              self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
              return
            }
          }
          
          // Check file readability
          guard fileManager.isReadableFile(atPath: persistentURL.path) else {
            print("Error: PDF file is not readable")
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "PDF file is not readable")
            self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
            return
          }
          
          // Log file header for debugging but don't reject based on it
          if let fileData = try? Data(contentsOf: persistentURL, options: .mappedIfSafe) {
            let pdfHeader = fileData.prefix(10) // Read more bytes for better debugging
            let pdfHeaderString = String(data: pdfHeader, encoding: .ascii) ?? ""
            print("File header: \(pdfHeaderString)")
          }
          
          // Try creating PDF document with additional error handling
          let document: PDFDocument
          do {
            // First try with the URL directly
            if let pdfDoc = PDFDocument(url: persistentURL) {
              document = pdfDoc
              print("Successfully created PDFDocument from URL")
            } else {
              // If URL fails, try with Data
              print("URL-based PDFDocument creation failed, trying with Data...")
              let pdfData = try Data(contentsOf: persistentURL)
              if let pdfDoc = PDFDocument(data: pdfData) {
                document = pdfDoc
                print("Successfully created PDFDocument from Data")
              } else {
                print("Both URL and Data-based PDFDocument creation failed")
                
                // Provide more helpful error message based on file content
                var errorMessage = "Failed to load PDF document"
                if let fileData = try? Data(contentsOf: persistentURL, options: .mappedIfSafe) {
                  let header = String(data: fileData.prefix(20), encoding: .ascii) ?? ""
                  if header.hasPrefix("<?xml") || header.contains("<html") {
                    errorMessage = "Downloaded file is not a PDF (appears to be XML/HTML content). Check if the URL requires authentication or redirects to an error page."
                  } else if header.isEmpty {
                    errorMessage = "Downloaded file is empty"
                  } else if !header.hasPrefix("%PDF") {
                    errorMessage = "Downloaded file is not a valid PDF format"
                  }
                }
                
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: errorMessage)
                self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
                return
              }
            }
          } catch {
            print("Error reading PDF data: \(error.localizedDescription)")
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Error reading PDF: \(error.localizedDescription)")
            self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
            return
          }
          
          // Verify document has pages
          guard document.pageCount > 0 else {
            print("PDF document has no pages: \(persistentURL)")
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "PDF document is empty")
            self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
            return
          }
          
          // Assign document to PDF view
          pdfView.document = document
          
          // Force layout update
          pdfView.layoutIfNeeded()

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
            let currentPage = pdfView.currentPage.flatMap { document.index(for: $0) } ?? 0
            let total = document.pageCount
            pageLabel.text = "\(currentPage + 1) of \(total)"
          }
          // Trigger label for initial page
          let initialPage = pdfView.currentPage.flatMap { document.index(for: $0) } ?? 0
          let total = document.pageCount
          pageLabel.text = "\(initialPage + 1) of \(total)"
          
          print("PDF loaded successfully: \(persistentURL.lastPathComponent), Pages: \(total)")

          // Setup navigation bar
          let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.dismissPDFView))
          vc.navigationItem.rightBarButtonItem = done
          let title = url.lastPathComponent
          vc.title = title.count > 30 ? String(title.prefix(27)) + "..." : title

          let nav = UINavigationController(rootViewController: vc)
          nav.modalPresentationStyle = .fullScreen
          
          // Configure navigation bar appearance to prevent color changes when scrolling
          let appearance = UINavigationBarAppearance()
          appearance.configureWithDefaultBackground()
          nav.navigationBar.standardAppearance = appearance
          nav.navigationBar.scrollEdgeAppearance = appearance
          nav.navigationBar.compactAppearance = appearance
          objc_setAssociatedObject(nav, &AssociatedKeys.documentURL, persistentURL, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
          objc_setAssociatedObject(self, &AssociatedKeys.navigationController, nav, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
          self.viewController.present(nav, animated: true, completion: nil)

          let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "PDF opened successfully")
          self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
        }
      } catch {
        print("Failed to persist PDF file: \(error.localizedDescription)")
        DispatchQueue.main.async {
          let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to save PDF: \(error.localizedDescription)")
          self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
        }
      }
    }
    task.resume()
    }

  @objc func dismissPDFView() {
    if let nav = objc_getAssociatedObject(self, &AssociatedKeys.navigationController) as? UINavigationController {
      // Clean up notification observers before dismissing
      if let pdfVC = nav.viewControllers.first,
         let pdfView = pdfVC.view.subviews.compactMap({ $0 as? PDFView }).first {
        NotificationCenter.default.removeObserver(self, name: Notification.Name.PDFViewPageChanged, object: pdfView)
      }
      
      nav.dismiss(animated: true, completion: nil)
      
      // Clear associated objects
      objc_setAssociatedObject(self, &AssociatedKeys.navigationController, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
