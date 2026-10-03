package dev.tandem.app.connection

object NoOpConnectionLoop : ConnectionLoop {
    override fun start() = Unit

    override fun stop() = Unit
}
