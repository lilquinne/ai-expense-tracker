package com.example.expense_tracker

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private var scanResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spendly/documents").setMethodCallHandler { call, result ->
            when (call.method) {
                "scan" -> {
                    if (scanResult != null) { result.error("busy", "A scan is already open", null) }
                    else {
                        scanResult = result
                        val options = GmsDocumentScannerOptions.Builder()
                            .setGalleryImportAllowed(false).setPageLimit(1)
                            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL).build()
                        GmsDocumentScanning.getClient(options).getStartScanIntent(this)
                            .addOnSuccessListener { sender ->
                                try { startIntentSenderForResult(sender, 7412, null, 0, 0, 0) }
                                catch (e: Exception) { scanResult?.error("camera", e.message, null); scanResult = null }
                            }.addOnFailureListener { e -> scanResult?.error("scanner", e.message, null); scanResult = null }
                    }
                }
                "renderPdf" -> {
                    val path = call.argument<String>("path")
                    if (path == null) { result.error("pdf", "Choose a PDF file", null) }
                    else Thread {
                        try {
                            val file = File(path)
                            require(file.length() <= 25L * 1024 * 1024) { "PDF must be 25 MB or smaller" }
                            val images = mutableListOf<String>()
                            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                                PdfRenderer(descriptor).use { pdf ->
                                    require(pdf.pageCount in 1..10) { "Import one invoice with 1â€“10 pages" }
                                    for (i in 0 until pdf.pageCount) {
                                        pdf.openPage(i).use { page ->
                                            val scale = 2400.0 / maxOf(page.width, page.height)
                                            val bitmap = Bitmap.createBitmap((page.width * scale).toInt().coerceAtLeast(1), (page.height * scale).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
                                            bitmap.eraseColor(Color.WHITE)
                                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                            val image = File.createTempFile("invoice-", ".jpg", cacheDir)
                                            image.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it) }
                                            bitmap.recycle(); images.add(image.absolutePath)
                                        }
                                    }
                                }
                            }
                            runOnUiThread { result.success(images) }
                        } catch (e: Exception) { runOnUiThread { result.error("pdf", e.message ?: "Cannot read this PDF", null) } }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 7412) {
            val pending = scanResult; scanResult = null
            if (resultCode != Activity.RESULT_OK) { pending?.success(null); return }
            try {
                val scan = GmsDocumentScanningResult.fromActivityResultIntent(data)
                val paths = scan?.pages?.map { page ->
                    val file = File.createTempFile("receipt-", ".jpg", cacheDir)
                    contentResolver.openInputStream(page.imageUri).use { input -> file.outputStream().use { output -> requireNotNull(input).copyTo(output) } }
                    file.absolutePath
                } ?: emptyList()
                pending?.success(paths)
            } catch(e: Exception) { pending?.error("scan", e.message, null) }
        }
    }
}
