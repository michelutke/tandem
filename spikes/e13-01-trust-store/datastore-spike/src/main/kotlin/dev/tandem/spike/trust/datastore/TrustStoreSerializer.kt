package dev.tandem.spike.trust.datastore

import androidx.datastore.core.CorruptionException
import androidx.datastore.core.Serializer
import dev.tandem.spike.trust.datastore.proto.TrustStore
import java.io.InputStream
import java.io.OutputStream
import com.google.protobuf.InvalidProtocolBufferException

object TrustStoreSerializer : Serializer<TrustStore> {
    override val defaultValue: TrustStore = TrustStore.getDefaultInstance()

    override suspend fun readFrom(input: InputStream): TrustStore =
        try {
            TrustStore.parseFrom(input)
        } catch (exception: InvalidProtocolBufferException) {
            throw CorruptionException("Cannot read TrustStore proto.", exception)
        }

    override suspend fun writeTo(t: TrustStore, output: OutputStream) {
        t.writeTo(output)
    }
}
