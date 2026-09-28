package dev.tandem.app

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import dagger.hilt.android.AndroidEntryPoint
import dev.tandem.core.ui.TandemActivity

// Launcher activity (E00-03): a blank screen proving the real `TandemApplication` Hilt component
// initializes on-device. Superseded by onboarding (F-4.1) once core/designsystem lands (E00-31).
@AndroidEntryPoint
class MainActivity : TandemActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            Surface(modifier = Modifier.fillMaxSize()) {}
        }
    }
}
