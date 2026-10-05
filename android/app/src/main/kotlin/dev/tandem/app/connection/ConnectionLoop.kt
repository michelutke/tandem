package dev.tandem.app.connection

/** What [dev.tandem.app.service.TandemService] drives: dial while it runs, hold nothing once stopped. */
interface ConnectionLoop {
    fun start()

    fun stop()
}
