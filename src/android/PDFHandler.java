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
      String extension = fileUrl.substring(fileUrl.lastIndexOf('.') + 1).toLowerCase();
      File path = new File(cordova.getContext().getExternalFilesDir(null), "downloaded." + extension);
      FileOutputStream output = new FileOutputStream(path);
      InputStream input = connection.getInputStream();
      byte[] buffer = new byte[4096];
      int len;
      while ((len = input.read(buffer)) > 0) output.write(buffer, 0, len);
      output.close(); input.close();

      Intent intent;
      if ("pdf".equals(extension)) {
        intent = new Intent(cordova.getContext(), Class.forName("com.afreakyelf.viewer.PdfViewerActivity"));
        intent.putExtra("pdfPath", path.getAbsolutePath());
        intent.putExtra("title", "PDF Viewer");
        intent.putExtra("showShareButton", true);
        intent.putExtra("showPrintButton", true);
        intent.putExtra("showSearchButton", true);
      } else {
        intent = new Intent(Intent.ACTION_SEND);
        intent.setType("application/octet-stream");
        Uri fileUri = FileProvider.getUriForFile(cordova.getContext(), cordova.getContext().getPackageName() + ".provider", path);
        intent.putExtra(Intent.EXTRA_STREAM, fileUri);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
      }
      cordova.getActivity().startActivity(intent);
      callbackContext.success("PDF opened successfully");
    } catch (Exception e) {
      callbackContext.error("Failed: " + e.getMessage());
    }
  }
}