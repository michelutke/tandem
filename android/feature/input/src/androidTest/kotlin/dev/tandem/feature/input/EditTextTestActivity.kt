package dev.tandem.feature.input

import android.app.Activity
import android.os.Bundle
import android.widget.EditText

class EditTextTestActivity : Activity() {
    lateinit var editText: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        editText = EditText(this).apply { setText(INITIAL_TEXT) }
        setContentView(editText)
        editText.requestFocus()
    }

    companion object {
        const val INITIAL_TEXT = "before"
    }
}
