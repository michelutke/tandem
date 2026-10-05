package dev.tandem.feature.input

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import java.util.concurrent.atomic.AtomicInteger

class ButtonTestActivity : Activity() {
    val clickCount = AtomicInteger()
    lateinit var button: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        button =
            Button(this).apply {
                text = "tap"
                setOnClickListener { clickCount.incrementAndGet() }
            }
        setContentView(button)
    }
}
