package dev.tandem.app.onboarding

/** Test fake (E20-14 tdd) standing in for [SdkVersionProvider] against real `Build.VERSION.SDK_INT`. */
class FakeSdkVersionProvider(
    private val sdkInt: Int,
) : SdkVersionProvider {
    override fun sdkInt(): Int = sdkInt
}
