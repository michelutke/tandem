package dev.tandem.app

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

// Sample composable for the Robolectric + Compose UI test harness (E00-20); superseded by the
// design system components once core/designsystem lands (E00-31).
internal const val SAMPLE_BUTTON_INITIAL_LABEL = "Click me"
internal const val SAMPLE_BUTTON_CLICKED_LABEL = "Clicked"

@Composable
fun SampleButton(modifier: Modifier = Modifier) {
    var label by remember { mutableStateOf(SAMPLE_BUTTON_INITIAL_LABEL) }
    Button(onClick = { label = SAMPLE_BUTTON_CLICKED_LABEL }, modifier = modifier.padding(16.dp)) {
        Text(label)
    }
}
