package dev.tandem.feature.pairing.scan

import android.content.Context
import android.content.ContextWrapper
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.LifecycleOwner
import java.util.concurrent.Executors

/**
 * The real frame source (E14-10): binds a CameraX `Preview` (into a [PreviewView] viewfinder) and
 * an `ImageAnalysis` running [ZxingQrAnalyzer] to the local [LifecycleOwner], restricted to the
 * back camera. [ScannerScreen] takes this as an overridable slot precisely so Compose `ui:` tests
 * never reach this function at all (E00-20) — they substitute a fake that calls [onResult]
 * directly, with no camera, no [ProcessCameraProvider] and no `androidx.camera` type involved.
 */
@Composable
fun CameraXFrameSource(
    onResult: (ScanResult) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = context.asLifecycleOwner()

    AndroidView(
        modifier = modifier.fillMaxSize(),
        factory = { viewContext ->
            val previewView = PreviewView(viewContext)
            val cameraProviderFuture = ProcessCameraProvider.getInstance(viewContext)
            cameraProviderFuture.addListener(
                {
                    val cameraProvider = cameraProviderFuture.get()
                    val preview =
                        Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
                    // 640x480 (CameraX's default analysis size) is too coarse for a dense, dotted pairing
                    // QR: ask for ~1080p and decode off the main thread, delivering hits back on it.
                    val analysis =
                        ImageAnalysis
                            .Builder()
                            .setResolutionSelector(
                                ResolutionSelector
                                    .Builder()
                                    .setResolutionStrategy(
                                        ResolutionStrategy(
                                            Size(ANALYSIS_WIDTH, ANALYSIS_HEIGHT),
                                            ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER,
                                        ),
                                    ).build(),
                            ).setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                            .build()
                            .also {
                                it.setAnalyzer(
                                    analysisExecutor,
                                    ZxingQrAnalyzer(onResult = { result -> viewContext.mainExecutor.execute { onResult(result) } }),
                                )
                            }

                    cameraProvider.unbindAll()
                    cameraProvider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analysis,
                    )
                },
                viewContext.mainExecutor,
            )
            previewView
        },
    )
}

/** Compose's `LocalContext` can be a wrapped `Context`; unwrap until the real `LifecycleOwner`. */
private tailrec fun Context.asLifecycleOwner(): LifecycleOwner =
    when (this) {
        is LifecycleOwner -> this
        is ContextWrapper -> baseContext.asLifecycleOwner()
        else -> error("no LifecycleOwner found in the Context chain")
    }

private const val ANALYSIS_WIDTH = 1920
private const val ANALYSIS_HEIGHT = 1080

/** One decode thread for the process: the analyzer is KEEP_ONLY_LATEST, so frames never queue up. */
private val analysisExecutor = Executors.newSingleThreadExecutor()
