package com.pdfviewer;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.net.Uri;
import android.os.Environment;
import android.util.Log;

import androidx.core.content.FileProvider;


import org.apache.cordova.*;
import org.json.JSONArray;

import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.List;

public class PDFHandler extends CordovaPlugin {
    private static final String TAG = "PDFHandler";

    @Override
    public boolean execute(String action, JSONArray args, final CallbackContext callbackContext) {
        Log.d(TAG, "execute called with action: " + action);
        if ("downloadFile".equals(action)) {
            final String fileUrl = args.optString(0);
            Log.d(TAG, "downloadFile requested for URL: " + fileUrl);
            cordova.getThreadPool().execute(() -> downloadAndOpen(fileUrl, callbackContext));
            return true;
        }
        Log.w(TAG, "Unknown action: " + action);
        return false;
    }

    private void downloadAndOpen(String fileUrl, CallbackContext callbackContext) {
        Log.d(TAG, "Starting download for: " + fileUrl);
        HttpURLConnection connection = null;
        FileOutputStream output = null;
        InputStream input = null;
        try {
            URL url = new URL(fileUrl);
            connection = (HttpURLConnection) url.openConnection();
            connection.connect();

            String extension = fileUrl.substring(fileUrl.lastIndexOf('.') + 1).toLowerCase();
            String originalFilename = fileUrl.substring(fileUrl.lastIndexOf('/') + 1);
            File path = new File(cordova.getContext().getExternalFilesDir(null), originalFilename);

            Log.d(TAG, "Saving file as: " + path.getAbsolutePath());

            output = new FileOutputStream(path);
            input = connection.getInputStream();
            byte[] buffer = new byte[4096];
            int len;
            while ((len = input.read(buffer)) > 0) {
                output.write(buffer, 0, len);
            }
            output.close();
            input.close();

            Log.d(TAG, "File downloaded successfully: " + path.getAbsolutePath());

            Uri fileUri = FileProvider.getUriForFile(
                cordova.getContext(),
                cordova.getContext().getPackageName() + ".cdv.core.file.provider",
                path
            );

            Intent intent;
            Activity activity = cordova.getActivity();

            if ("pdf".equals(extension)) {
                Log.d(TAG, "Attempting to open PDF with Google Docs.");
                // Try Google Docs first
                Intent googleDocsIntent = new Intent(Intent.ACTION_VIEW);
                googleDocsIntent.setDataAndType(fileUri, "application/pdf");
                googleDocsIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NO_HISTORY);
                googleDocsIntent.setPackage("com.google.android.apps.docs");

                // Check if Google Docs is available
                if (googleDocsIntent.resolveActivity(activity.getPackageManager()) != null) {
                    Log.d(TAG, "Opening PDF via Google Docs with public URL.");
                    intent = googleDocsIntent;
                    // intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                } else {
                    Log.d(TAG, "Google Docs not available, using chooser.");
                    Intent chooserIntent = new Intent(Intent.ACTION_VIEW);
                    chooserIntent.setDataAndType(fileUri, "application/pdf");
                    chooserIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NO_HISTORY);
                    intent = Intent.createChooser(chooserIntent, "Open PDF with");
                }
            } else {
                Log.d(TAG, "Showing chooser for non-PDF file.");
                Intent shareIntent = new Intent(Intent.ACTION_SEND);
                shareIntent.setType("application/octet-stream");
                shareIntent.putExtra(Intent.EXTRA_STREAM, fileUri);
                shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                intent = Intent.createChooser(shareIntent, "Open file with");
            }

            if (intent.resolveActivity(activity.getPackageManager()) != null) {
                activity.startActivity(intent);
                Log.d(TAG, "Intent started successfully.");
                callbackContext.success("File opened successfully");
            } else {
                Log.e(TAG, "No app found to handle the intent.");
                callbackContext.error("No app found to open this file type.");
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to download or open file: " + e.getMessage(), e);
            callbackContext.error("Failed: " + e.getMessage());
        } finally {
            try {
                if (output != null) output.close();
            } catch (IOException ignored) {}
            try {
                if (input != null) input.close();
            } catch (IOException ignored) {}
            if (connection != null) connection.disconnect();
        }
    }

}