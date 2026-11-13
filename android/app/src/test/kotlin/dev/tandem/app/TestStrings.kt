package dev.tandem.app

import androidx.annotation.StringRes
import androidx.test.platform.app.InstrumentationRegistry

internal fun appString(
    @StringRes id: Int,
    vararg args: Any,
): String = InstrumentationRegistry.getInstrumentation().targetContext.getString(id, *args)
