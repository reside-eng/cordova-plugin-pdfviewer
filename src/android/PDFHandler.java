package com.pdfviewer;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Environment;
import android.util.Log;

import androidx.core.content.FileProvider;

import org.apache.cordova.*;
import org.json.JSONArray;

import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;

public class PDFHandler extends CordovaPlugin {
  @Override
  public boolean execute(String action, JSONArray args, final CallbackContext callbackContext) {
    if (action.equals("downloadFile")) {
      final String fileUrl = args.optString(0);
      cordova.getThreadPool().execute(() -> downloadAndOpen(fileUrl, callbackContext));
      return true;
    }
    return false;
  }

  private void downloadAndOpen(String fileUrl, CallbackContext callbackContext) {
    try {
      URL url = new URL(fileUrl);
      HttpURLConnection connection = (HttpURLConnection) url.openConnection();
      connection.connect();
      File path = new File(cordova.getContext().getExternalFilesDir(null), "downloaded.pdf");
      FileOutputStream output = new FileOutputStream(path);
      InputStream input = connection.getInputStream();
      byte[] buffer = new byte[4096];
      int len;
      while ((len = input.read(buffer)) > 0) output.write(buffer, 0, len);
      output.close(); input.close();

      Intent intent = new Intent(cordova.getContext(), Class.forName("com.afreakyelf.viewer.PdfViewerActivity"));
      intent.putExtra("pdfPath", path.getAbsolutePath());
      intent.putExtra("title", "PDF Viewer");
      intent.putExtra("showShareButton", true);
      intent.putExtra("showPrintButton", true);
      intent.putExtra("showSearchButton", true);
      cordova.getActivity().startActivity(intent);
      callbackContext.success("PDF opened successfully");
    } catch (Exception e) {
      callbackContext.error("Failed: " + e.getMessage());
    }
  }
}