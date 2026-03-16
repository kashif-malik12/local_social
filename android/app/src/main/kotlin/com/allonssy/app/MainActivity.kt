package com.allonssy.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {

    private enum class PendingCaptureMode { PHOTO, VIDEO }

    private var pendingPhotoResult: MethodChannel.Result? = null
    private var pendingPhotoFile: File? = null
    private var pendingVideoResult: MethodChannel.Result? = null
    private var pendingVideoFile: File? = null
    private var pendingGalleryImagesResult: MethodChannel.Result? = null
    private var pendingGalleryVideoResult: MethodChannel.Result? = null
    private var pendingCaptureMode: PendingCaptureMode? = null
    private val bgExecutor = Executors.newSingleThreadExecutor()

    private lateinit var takePhotoLauncher: ActivityResultLauncher<Uri>
    private lateinit var takeVideoLauncher: ActivityResultLauncher<Intent>
    private lateinit var requestCameraPermissionLauncher: ActivityResultLauncher<Array<String>>
    private lateinit var pickImagesLauncher: ActivityResultLauncher<PickVisualMediaRequest>
    private lateinit var pickVideoLauncher: ActivityResultLauncher<PickVisualMediaRequest>

    override fun onCreate(savedInstanceState: Bundle?) {
        requestCameraPermissionLauncher =
            registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
                val mode = pendingCaptureMode
                pendingCaptureMode = null

                val hasCamera = grants[Manifest.permission.CAMERA] == true
                val hasAudio = mode != PendingCaptureMode.VIDEO ||
                    grants[Manifest.permission.RECORD_AUDIO] == true

                if (!hasCamera || !hasAudio) {
                    pendingPhotoResult?.error("CAMERA_DENIED", "Camera permission denied", null)
                    pendingVideoResult?.error(
                        "CAMERA_DENIED",
                        if (!hasAudio) "Microphone permission denied" else "Camera permission denied",
                        null
                    )
                    pendingPhotoResult = null
                    pendingPhotoFile = null
                    pendingVideoResult = null
                    return@registerForActivityResult
                }

                when (mode) {
                    PendingCaptureMode.PHOTO -> launchPhotoCapture()
                    PendingCaptureMode.VIDEO -> launchVideoCapture()
                    null -> Unit
                }
            }

        takePhotoLauncher = registerForActivityResult(ActivityResultContracts.TakePicture()) { success ->
            val file = pendingPhotoFile
            if (success && file != null && file.exists() && file.length() > 0) {
                pendingPhotoResult?.success(file.absolutePath)
            } else {
                pendingPhotoResult?.success(null)
            }
            pendingPhotoResult = null
            pendingPhotoFile = null
        }

        takeVideoLauncher = registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            val pending = pendingVideoResult
            val file = pendingVideoFile
            val videoUri = result.data?.data
            pendingVideoResult = null
            pendingVideoFile = null

            if (result.resultCode == Activity.RESULT_OK && file != null) {
                resolveCapturedVideoFile(
                    file = file,
                    fallbackUri = videoUri,
                    pending = pending,
                )
            } else if (result.resultCode == Activity.RESULT_OK && videoUri != null) {
                copyUriToCache(
                    uri = videoUri,
                    prefix = "VIDEO_",
                    suffix = ".mp4",
                    onSuccess = { path -> pending?.success(path) },
                    onError = { code, message -> pending?.error(code, message, null) },
                )
            } else {
                pending?.success(null)
            }
        }

        pickImagesLauncher = registerForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(2)) { uris ->
            val pending = pendingGalleryImagesResult
            pendingGalleryImagesResult = null

            if (uris.isEmpty()) {
                pending?.success(emptyList<String>())
                return@registerForActivityResult
            }

            copyUrisToCache(
                uris = uris,
                prefix = "GALLERY_IMG_",
                suffix = ".jpg",
                onSuccess = { paths -> pending?.success(paths) },
                onError = { code, message -> pending?.error(code, message, null) },
            )
        }

        pickVideoLauncher = registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
            val pending = pendingGalleryVideoResult
            pendingGalleryVideoResult = null

            if (uri == null) {
                pending?.success(null)
                return@registerForActivityResult
            }

            copyUriToCache(
                uri = uri,
                prefix = "GALLERY_VIDEO_",
                suffix = ".mp4",
                onSuccess = { path -> pending?.success(path) },
                onError = { code, message -> pending?.error(code, message, null) },
            )
        }

        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.local_social/camera")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capturePhoto" -> capturePhoto(result)
                    "captureVideo" -> captureVideo(result)
                    "pickImages" -> pickImages(result)
                    "pickVideoFromGallery" -> pickVideoFromGallery(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun capturePhoto(result: MethodChannel.Result) {
        if (pendingPhotoResult != null) {
            result.error("BUSY", "Camera already open", null)
            return
        }
        pendingPhotoResult = result
        if (!ensureCapturePermissions(PendingCaptureMode.PHOTO)) return
        launchPhotoCapture()
    }

    private fun launchPhotoCapture() {
        try {
            val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val file = File.createTempFile("PHOTO_${ts}_", ".jpg", cacheDir)
            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
            pendingPhotoFile = file
            takePhotoLauncher.launch(uri)
        } catch (e: Exception) {
            pendingPhotoResult?.error("CAMERA_ERROR", e.message, null)
            pendingPhotoResult = null
            pendingPhotoFile = null
        }
    }

    private fun captureVideo(result: MethodChannel.Result) {
        if (pendingVideoResult != null) {
            result.error("BUSY", "Camera already open", null)
            return
        }
        pendingVideoResult = result
        if (!ensureCapturePermissions(PendingCaptureMode.VIDEO)) return
        launchVideoCapture()
    }

    private fun launchVideoCapture() {
        try {
            val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val file = File.createTempFile("VIDEO_${ts}_", ".mp4", cacheDir)
            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
            pendingVideoFile = file

            val intent = Intent(MediaStore.ACTION_VIDEO_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_DURATION_LIMIT, 10)
                putExtra(MediaStore.EXTRA_OUTPUT, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                clipData = android.content.ClipData.newRawUri("", uri)
            }
            takeVideoLauncher.launch(intent)
        } catch (e: Exception) {
            pendingVideoResult?.error("VIDEO_ERROR", e.message, null)
            pendingVideoResult = null
            pendingVideoFile = null
        }
    }

    private fun pickImages(result: MethodChannel.Result) {
        if (pendingGalleryImagesResult != null) {
            result.error("BUSY", "Gallery already open", null)
            return
        }
        pendingGalleryImagesResult = result
        pickImagesLauncher.launch(
            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
        )
    }

    private fun pickVideoFromGallery(result: MethodChannel.Result) {
        if (pendingGalleryVideoResult != null) {
            result.error("BUSY", "Gallery already open", null)
            return
        }
        pendingGalleryVideoResult = result
        pickVideoLauncher.launch(
            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly)
        )
    }

    private fun ensureCapturePermissions(mode: PendingCaptureMode): Boolean {
        val permissions = if (mode == PendingCaptureMode.VIDEO) {
            arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
        } else {
            arrayOf(Manifest.permission.CAMERA)
        }

        val allGranted = permissions.all { permission ->
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        }
        if (allGranted) return true

        pendingCaptureMode = mode
        requestCameraPermissionLauncher.launch(permissions)
        return false
    }

    private fun copyUrisToCache(
        uris: List<Uri>,
        prefix: String,
        suffix: String,
        onSuccess: (List<String>) -> Unit,
        onError: (String, String?) -> Unit,
    ) {
        bgExecutor.execute {
            try {
                val paths = uris.map { uri ->
                    copyUriToCacheInternal(uri, prefix, suffix).absolutePath
                }
                runOnUiThread { onSuccess(paths) }
            } catch (e: Exception) {
                runOnUiThread { onError("PICKER_ERROR", e.message) }
            }
        }
    }

    private fun copyUriToCache(
        uri: Uri,
        prefix: String,
        suffix: String,
        onSuccess: (String) -> Unit,
        onError: (String, String?) -> Unit,
    ) {
        bgExecutor.execute {
            try {
                val file = copyUriToCacheInternal(uri, prefix, suffix)
                runOnUiThread { onSuccess(file.absolutePath) }
            } catch (e: Exception) {
                runOnUiThread { onError("PICKER_ERROR", e.message) }
            }
        }
    }

    private fun resolveCapturedVideoFile(
        file: File,
        fallbackUri: Uri?,
        pending: MethodChannel.Result?,
    ) {
        bgExecutor.execute {
            try {
                var attempts = 0
                while (attempts < 20) {
                    if (file.exists() && file.length() > 0) {
                        runOnUiThread { pending?.success(file.absolutePath) }
                        return@execute
                    }
                    Thread.sleep(150)
                    attempts += 1
                }

                if (fallbackUri != null) {
                    copyUriToCache(
                        uri = fallbackUri,
                        prefix = "VIDEO_",
                        suffix = ".mp4",
                        onSuccess = { path -> pending?.success(path) },
                        onError = { code, message -> pending?.error(code, message, null) },
                    )
                } else {
                    runOnUiThread { pending?.success(null) }
                }
            } catch (e: Exception) {
                runOnUiThread { pending?.error("VIDEO_ERROR", e.message, null) }
            }
        }
    }

    private fun copyUriToCacheInternal(uri: Uri, prefix: String, suffix: String): File {
        val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val tmp = File.createTempFile("${prefix}${ts}_", suffix, cacheDir)
        contentResolver.openInputStream(uri)?.use { input ->
            tmp.outputStream().use { out -> input.copyTo(out) }
        } ?: throw IllegalStateException("Unable to read selected media")
        return tmp
    }
}
