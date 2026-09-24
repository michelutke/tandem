plugins {
    id("tandem.android.library")
}

android {
    namespace = "dev.tandem.core.protocol"
}

dependencies {
    api(libs.protobuf.javalite)
    api(libs.protobuf.kotlin.lite)
}
