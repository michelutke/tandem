package dev.tandem.feature.messaging

import android.app.Instrumentation
import android.os.ParcelFileDescriptor

/** Inserts an inbox row through the shell uid and returns the command output once it has finished. */
internal fun Instrumentation.insertInboxSms(
    address: String,
    body: String,
): String =
    ParcelFileDescriptor
        .AutoCloseInputStream(
            uiAutomation.executeShellCommand(
                "content insert --uri content://sms/inbox " +
                    "--bind address:s:$address --bind body:s:$body --bind read:i:0",
            ),
        ).use { it.readBytes().decodeToString().trim() }
