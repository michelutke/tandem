package dev.tandem.feature.files

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import dev.tandem.protocol.v1.PhotoAccess

/**
 * Maps the runtime media grants (F-7.4) to the [PhotoAccess] reported in every `PhotoPageResult`:
 * API 34+ with only `READ_MEDIA_VISUAL_USER_SELECTED` granted is PARTIAL, any full read grant is
 * FULL, nothing granted is NONE. [sdkInt] is injected so tests cover each API level.
 */
@SuppressLint("InlinedApi") // constants are inlined at compile time and only read behind sdkInt checks
class MediaPermissionChecker(
    private val context: Context,
    private val sdkInt: Int = Build.VERSION.SDK_INT,
) {
    fun requiredPermissions(): List<String> =
        when {
            sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                listOf(
                    Manifest.permission.READ_MEDIA_IMAGES,
                    Manifest.permission.READ_MEDIA_VIDEO,
                    Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                )
            }

            sdkInt >= Build.VERSION_CODES.TIRAMISU -> {
                listOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
            }

            else -> {
                listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
            }
        }

    fun access(): PhotoAccess =
        when {
            hasFullAccess() -> PhotoAccess.PHOTO_ACCESS_FULL
            hasOnlyUserSelectedAccess() -> PhotoAccess.PHOTO_ACCESS_PARTIAL
            else -> PhotoAccess.PHOTO_ACCESS_NONE
        }

    private fun hasFullAccess(): Boolean =
        if (sdkInt >= Build.VERSION_CODES.TIRAMISU) {
            isGranted(Manifest.permission.READ_MEDIA_IMAGES) || isGranted(Manifest.permission.READ_MEDIA_VIDEO)
        } else {
            isGranted(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    private fun hasOnlyUserSelectedAccess(): Boolean =
        sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            isGranted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)

    private fun isGranted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
}
