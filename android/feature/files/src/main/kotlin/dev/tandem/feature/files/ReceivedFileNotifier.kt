package dev.tandem.feature.files

/** Tells the user a verified file was published; [contentUri] is the entry [DownloadsPublisher] returned (E40-13). */
fun interface ReceivedFileNotifier {
    fun notifyReceived(
        name: String,
        mime: String,
        contentUri: String,
    )
}
