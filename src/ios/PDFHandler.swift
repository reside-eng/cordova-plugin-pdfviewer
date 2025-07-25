import Foundation
import PDFKit
import UIKit
import WebKit

@objc(PDFHandler) class PDFHandler: CDVPlugin, WKScriptMessageHandler {
  
  override func pluginInitialize() {
    super.pluginInitialize()
    setupBlobURLMessageHandler()
  }
  
  private func setupBlobURLMessageHandler() {
    // Add message handler for blob URL processing
    if let webView = self.webView as? WKWebView {
      webView.configuration.userContentController.add(self, name: "blobData")
      print("Blob URL message handler registered successfully")
    } else {
      print("WARNING: WebView is not WKWebView - blob URL support will not be available")
    }
  }
  
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

    // Handle non-PDF files with native share
    let lowercased = url.pathExtension.lowercased()
    if lowercased != "pdf" {
      print("Processing non-PDF file: \(lowercased.uppercased())")
      print("Original URL: \(url.absoluteString)")
      print("URL scheme: \(url.scheme ?? "none")")
      print("URL host: \(url.host ?? "none")")
      print("URL path: \(url.path)")
      
      // Check for problematic URL schemes and handle them appropriately
      if let scheme = url.scheme {
        if scheme == "blob" {
          print("BLOB URL detected: \(url.absoluteString)")
          print("Attempting to convert blob URL to downloadable content...")
          self.handleBlobURL(url, command: command, lowercased: lowercased)
          return
        } else if scheme == "data" {
          print("DATA URL detected: attempting to process...")
          self.handleDataURL(url, command: command, lowercased: lowercased)
          return
        } else if !(["http", "https", "file"].contains(scheme.lowercased())) {
          print("WARNING: Unusual URL scheme '\(scheme)' - this may cause 'unsupported URL' error")
        }
      } else {
        print("WARNING: No URL scheme detected - this may cause 'unsupported URL' error")
      }
      
      let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
        if let error = error {
          print("Download error for \(lowercased.uppercased()) file: \(error.localizedDescription)")
          print("Error domain: \(error._domain)")
          print("Error code: \(error._code)")
          
          var errorMessage = "Download failed: \(error.localizedDescription)"
          
          // Provide specific guidance for common error types
          if error.localizedDescription.lowercased().contains("unsupported url") {
            print("DIAGNOSIS: Unsupported URL error detected")
            print("Common causes:")
            print("1. Blob URLs (blob:) - not supported by URLSession")
            print("2. Data URLs (data:) - not supported for downloads")
            print("3. Custom URL schemes - may not be downloadable")
            print("4. Malformed URLs - check URL encoding")
            errorMessage = "Unsupported URL format. Please ensure the URL uses http:// or https:// and is properly encoded."
          } else if error._code == -1002 {
            errorMessage = "Invalid URL format. Please check the URL is properly formatted."
          } else if error._code == -1003 {
            errorMessage = "Cannot find the host server. Please check the URL and internet connection."
          }
          
          DispatchQueue.main.async {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: errorMessage)
            self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
          }
          return
        }
        
        guard let localURL = localURL else {
          print("No local URL returned for \(lowercased.uppercased()) file download")
          DispatchQueue.main.async {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "No file downloaded")
            self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
          }
          return
        }
        
        print("Downloaded \(lowercased.uppercased()) file to temporary location: \(localURL.path)")
        
        // Log response details
        if let httpResponse = response as? HTTPURLResponse {
          print("HTTP Status Code: \(httpResponse.statusCode)")
          print("Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
          print("Content-Length: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "unknown")")
          
          // Log Content-Disposition header (important for attachment downloads)
          if let contentDisposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition") {
            print("Content-Disposition: \(contentDisposition)")
            if contentDisposition.lowercased().contains("attachment") {
              print("✓ File is served as attachment (download) - this is supported")
            }
          } else {
            print("Content-Disposition: not present (inline display)")
          }
        }
        
        // Validate downloaded file
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: localURL.path) else {
          print("Downloaded file does not exist at path: \(localURL.path)")
          DispatchQueue.main.async {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Downloaded file not found")
            self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
          }
          return
        }
        
        // Check file size
        do {
          let fileAttributes = try fileManager.attributesOfItem(atPath: localURL.path)
          let fileSize = fileAttributes[.size] as? Int64 ?? 0
          print("Downloaded file size: \(fileSize) bytes")
          
          if fileSize == 0 {
            print("Error: Downloaded \(lowercased.uppercased()) file is empty")
            DispatchQueue.main.async {
              let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Downloaded file is empty")
              self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
            }
            return
          }
        } catch {
          print("Could not get file attributes: \(error.localizedDescription)")
        }

        // Save to a proper file location that can be shared
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = Int(Date().timeIntervalSince1970)
        let originalName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let fileName = "\(originalName)_\(timestamp)"
        let persistentURL = documentsDir.appendingPathComponent(fileName)
        
        print("Saving \(lowercased.uppercased()) file to: \(persistentURL.path)")
        
        do {
          // Remove any existing file
          if fileManager.fileExists(atPath: persistentURL.path) {
            try fileManager.removeItem(at: persistentURL)
            print("Removed existing file at destination")
          }
          
          // Copy the downloaded file to documents directory
          try fileManager.copyItem(at: localURL, to: persistentURL)
          print("Successfully copied \(lowercased.uppercased()) file to persistent location")
          
          // Verify the copy was successful
          guard fileManager.fileExists(atPath: persistentURL.path) else {
            print("File copy verification failed - file not found at destination")
            DispatchQueue.main.async {
              let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "File copy verification failed")
              self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
            }
            return
          }
          
          // Check copied file size
          let copiedAttributes = try fileManager.attributesOfItem(atPath: persistentURL.path)
          let copiedSize = copiedAttributes[.size] as? Int64 ?? 0
          print("Copied file size: \(copiedSize) bytes")
          
          DispatchQueue.main.async {
            print("Presenting share sheet for \(lowercased.uppercased()) file")
            let activityVC = UIActivityViewController(activityItems: [persistentURL], applicationActivities: nil)
            
            // For iPad, set popover presentation
            if let popover = activityVC.popoverPresentationController {
              popover.sourceView = self.viewController.view
              popover.sourceRect = CGRect(x: self.viewController.view.bounds.midX, y: self.viewController.view.bounds.midY, width: 0, height: 0)
              popover.permittedArrowDirections = []
              print("Configured popover for iPad")
            }
            
            self.viewController.present(activityVC, animated: true) {
              print("Share sheet presented successfully")
            }

            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Share sheet presented for \(lowercased.uppercased()) file")
            self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
          }
        } catch {
          print("Failed to copy \(lowercased.uppercased()) file: \(error.localizedDescription)")
          print("Copy error domain: \(error._domain)")
          print("Copy error code: \(error._code)")
          DispatchQueue.main.async {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to save file: \(error.localizedDescription)")
            self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
          }
        }
      }
      
      print("Starting download task for \(lowercased.uppercased()) file")
      task.resume()
      return
    }

    let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
      guard let localURL = localURL, error == nil else {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: error?.localizedDescription)
        self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
        return
      }
      
      print("PDF download completed to temporary location: \(localURL.path)")
      
      // Log response details for PDF downloads
      if let httpResponse = response as? HTTPURLResponse {
        print("PDF HTTP Status Code: \(httpResponse.statusCode)")
        print("PDF Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
        print("PDF Content-Length: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "unknown")")
        
        // Log Content-Disposition header (important for attachment downloads)
        if let contentDisposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition") {
          print("PDF Content-Disposition: \(contentDisposition)")
          if contentDisposition.lowercased().contains("attachment") {
            print("✓ PDF is served as attachment (download) - this is fully supported")
          }
        } else {
          print("PDF Content-Disposition: not present (inline display)")
        }
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
  
  // MARK: - Blob URL Handling
  
  private func handleBlobURL(_ url: URL, command: CDVInvokedUrlCommand, lowercased: String) {
    print("Handling blob URL: \(url.absoluteString)")
    
    // Safely unwrap the callback ID
    guard let callbackId = command.callbackId else {
      print("ERROR: No callback ID available for blob URL processing")
      return
    }
    
    // Blob URLs need to be converted to data by the web view
    // We'll ask the web view to fetch the blob content and convert it to a data URL
    let javascript = """
      (function() {
        fetch('\(url.absoluteString)')
          .then(response => response.blob())
          .then(blob => {
            const reader = new FileReader();
            reader.onload = function() {
              window.webkit.messageHandlers.blobData.postMessage({
                callbackId: '\(callbackId)',
                dataURL: reader.result,
                originalURL: '\(url.absoluteString)',
                fileType: '\(lowercased)'
              });
            };
            reader.readAsDataURL(blob);
          })
          .catch(error => {
            window.webkit.messageHandlers.blobData.postMessage({
              callbackId: '\(callbackId)',
              error: error.message,
              originalURL: '\(url.absoluteString)'
            });
          });
      })();
    """
    
    // Execute JavaScript in the web view to convert blob to data URL
    if let webView = self.webView as? WKWebView {
      webView.evaluateJavaScript(javascript) { result, error in
        if let error = error {
          print("JavaScript execution error: \(error.localizedDescription)")
          let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to process blob URL: \(error.localizedDescription)")
          self.commandDelegate?.send(pluginResult, callbackId: callbackId)
        }
        // Result will be handled by the message handler
      }
    } else {
      print("ERROR: WebView is not WKWebView or not available for blob URL processing")
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "WKWebView not available for blob URL processing")
      self.commandDelegate?.send(pluginResult, callbackId: callbackId)
    }
  }
  
  private func handleDataURL(_ url: URL, command: CDVInvokedUrlCommand, lowercased: String) {
    print("Handling data URL...")
    
    let urlString = url.absoluteString
    
    // Parse data URL format: data:[<mediatype>][;base64],<data>
    guard urlString.hasPrefix("data:") else {
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid data URL format")
      self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
      return
    }
    
    // Extract the data part after "data:"
    let dataString = String(urlString.dropFirst(5)) // Remove "data:"
    
    guard let commaIndex = dataString.firstIndex(of: ",") else {
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid data URL format - no comma separator")
      self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
      return
    }
    
    let headerPart = String(dataString[..<commaIndex])
    let dataPart = String(dataString[dataString.index(after: commaIndex)...])
    
    print("Data URL header: \(headerPart)")
    print("Data URL data length: \(dataPart.count) characters")
    
    var fileData: Data?
    
    if headerPart.contains("base64") {
      // Base64 encoded data
      fileData = Data(base64Encoded: dataPart)
    } else {
      // URL encoded data
      if let decodedString = dataPart.removingPercentEncoding {
        fileData = decodedString.data(using: .utf8)
      }
    }
    
    guard let data = fileData, !data.isEmpty else {
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to decode data URL content")
      self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
      return
    }
    
    print("Successfully decoded data URL: \(data.count) bytes")
    
    // Save data to a temporary file and process it
    let fileManager = FileManager.default
    let tempDir = fileManager.temporaryDirectory
    let timestamp = Int(Date().timeIntervalSince1970)
    let fileName = "dataurl_\(timestamp).\(lowercased == "pdf" ? "pdf" : "dat")"
    let tempURL = tempDir.appendingPathComponent(fileName)
    
    do {
      try data.write(to: tempURL)
      print("Data URL content saved to: \(tempURL.path)")
      
      // Now process the file as if it was downloaded
      if lowercased == "pdf" {
        self.processPDFFile(at: tempURL, originalURL: url, command: command)
      } else {
        self.processNonPDFFile(at: tempURL, originalURL: url, command: command, fileType: lowercased)
      }
    } catch {
      print("Failed to save data URL content: \(error.localizedDescription)")
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to save data URL content: \(error.localizedDescription)")
      self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
    }
  }
  
  // MARK: - File Processing Helpers
  
  private func presentPDFViewer(with url: URL, originalURL: URL, command: CDVInvokedUrlCommand) {
    // Reuse existing PDF viewer presentation logic
    // This is similar to the existing PDF presentation code but extracted for reuse
    print("Presenting PDF viewer for: \(url.lastPathComponent)")
    
    // Create PDF document
    guard let document = PDFDocument(url: url) else {
      print("Failed to create PDF document from: \(url.path)")
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid PDF file")
      self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
      return
    }
    
    // Create and configure PDF view (reuse existing logic)
    let pdfView = PDFView()
    pdfView.document = document
    pdfView.autoScales = true
    
    let vc = UIViewController()
    vc.view.backgroundColor = UIColor.white
    vc.view.addSubview(pdfView)
    
    // Add constraints and setup UI (similar to existing implementation)
    pdfView.translatesAutoresizingMaskIntoConstraints = false
    
    // Create toolbar
    let toolbar = UIToolbar()
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    vc.view.addSubview(toolbar)
    
    // Setup constraints
    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
      toolbar.bottomAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.bottomAnchor),
      
      pdfView.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor),
      pdfView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
      pdfView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
      pdfView.bottomAnchor.constraint(equalTo: toolbar.topAnchor)
    ])
    
    // Setup navigation
    let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.dismissPDFView))
    vc.navigationItem.rightBarButtonItem = done
    let title = originalURL.lastPathComponent
    vc.title = title.count > 30 ? String(title.prefix(27)) + "..." : title
    
    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .fullScreen
    
    // Store references
    objc_setAssociatedObject(self, &AssociatedKeys.documentURL, url, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    objc_setAssociatedObject(self, &AssociatedKeys.navigationController, nav, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    
    // Present
    self.viewController.present(nav, animated: true) {
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "PDF opened successfully")
      self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
    }
  }
  
  private func presentShareSheet(for url: URL, command: CDVInvokedUrlCommand, fileType: String) {
    print("Presenting share sheet for \(fileType.uppercased()) file")
    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    
    // For iPad, set popover presentation
    if let popover = activityVC.popoverPresentationController {
      popover.sourceView = self.viewController.view
      popover.sourceRect = CGRect(x: self.viewController.view.bounds.midX, y: self.viewController.view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    
    self.viewController.present(activityVC, animated: true) {
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "\(fileType.uppercased()) file shared successfully")
      self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
    }
  }
  
  private func processPDFFile(at fileURL: URL, originalURL: URL, command: CDVInvokedUrlCommand) {
    print("Processing PDF file from: \(fileURL.path)")
    
    // Copy to Documents directory for persistent access
    let fileManager = FileManager.default
    let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let timestamp = Int(Date().timeIntervalSince1970)
    let fileName = "pdf_\(timestamp).pdf"
    let persistentURL = documentsDir.appendingPathComponent(fileName)
    
    do {
      if fileManager.fileExists(atPath: persistentURL.path) {
        try fileManager.removeItem(at: persistentURL)
      }
      try fileManager.copyItem(at: fileURL, to: persistentURL)
      print("PDF copied to persistent location: \(persistentURL.path)")
      
      // Now create and present the PDF viewer
      DispatchQueue.main.async {
        self.presentPDFViewer(with: persistentURL, originalURL: originalURL, command: command)
      }
    } catch {
      print("Failed to copy PDF file: \(error.localizedDescription)")
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to process PDF: \(error.localizedDescription)")
      self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
    }
  }
  
  private func processNonPDFFile(at fileURL: URL, originalURL: URL, command: CDVInvokedUrlCommand, fileType: String) {
    print("Processing non-PDF file (\(fileType)) from: \(fileURL.path)")
    
    // Copy to Documents directory for sharing
    let fileManager = FileManager.default
    let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let timestamp = Int(Date().timeIntervalSince1970)
    let originalName = originalURL.lastPathComponent.isEmpty ? "download" : originalURL.lastPathComponent
    let fileName = "\(originalName)_\(timestamp)"
    let persistentURL = documentsDir.appendingPathComponent(fileName)
    
    do {
      if fileManager.fileExists(atPath: persistentURL.path) {
        try fileManager.removeItem(at: persistentURL)
      }
      try fileManager.copyItem(at: fileURL, to: persistentURL)
      print("Non-PDF file copied to persistent location: \(persistentURL.path)")
      
      // Present share sheet
      DispatchQueue.main.async {
        self.presentShareSheet(for: persistentURL, command: command, fileType: fileType)
      }
    } catch {
      print("Failed to copy non-PDF file: \(error.localizedDescription)")
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to process file: \(error.localizedDescription)")
      self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
    }
  }
  
  // MARK: - WKScriptMessageHandler
  
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.name == "blobData",
          let messageBody = message.body as? [String: Any] else {
      print("Invalid message received: \(message.name)")
      return
    }
    
    print("Received blob data message: \(messageBody.keys)")
    
    guard let callbackId = messageBody["callbackId"] as? String else {
      print("No callback ID in blob data message")
      return
    }
    
    if let error = messageBody["error"] as? String {
      print("Blob URL processing error: \(error)")
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Blob URL error: \(error)")
      self.commandDelegate?.send(pluginResult, callbackId: callbackId)
      return
    }
    
    guard let dataURL = messageBody["dataURL"] as? String,
          let fileType = messageBody["fileType"] as? String else {
      print("Missing dataURL or fileType in blob data message")
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid blob data received")
      self.commandDelegate?.send(pluginResult, callbackId: callbackId)
      return
    }
    
    print("Converting blob to data URL successful, processing...")
    
    // Create a command object for processing
    guard let tempCommand = CDVInvokedUrlCommand(arguments: [], callbackId: callbackId, className: "PDFHandler", methodName: "downloadFile") else {
      print("Failed to create CDVInvokedUrlCommand")
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to create command object")
      self.commandDelegate?.send(pluginResult, callbackId: callbackId)
      return
    }
    
    // Process the data URL
    if let url = URL(string: dataURL) {
      self.handleDataURL(url, command: tempCommand, lowercased: fileType)
    } else {
      print("Failed to create URL from data URL string")
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to process converted blob data")
      self.commandDelegate?.send(pluginResult, callbackId: callbackId)
    }
  }
}

fileprivate struct AssociatedKeys {
  static var documentURL = "documentURL"
  static var navigationController = "navigationController"
}
