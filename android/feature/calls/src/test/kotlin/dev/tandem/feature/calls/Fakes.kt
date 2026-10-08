package dev.tandem.feature.calls

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

class FakeCallGateway : CallGateway {
    private val states = MutableSharedFlow<CallStateChange>(extraBufferCapacity = 16)
    override val callStates: Flow<CallStateChange> = states

    val collectorCount: Int get() = states.subscriptionCount.value
    var acceptCalls = 0
    var endCalls = 0
    var endResult = true
    var placeOutcome = PlaceOutcome.Placed
    var placeSecurityException = false
    val placed = mutableListOf<Pair<String, Int>>()

    fun emit(
        state: PhoneCallState,
        number: String? = null,
    ) {
        states.tryEmit(CallStateChange(state, number))
    }

    override fun acceptRingingCall() {
        acceptCalls++
    }

    override fun endCall(): Boolean {
        endCalls++
        return endResult
    }

    override suspend fun placeCall(
        address: String,
        subscriptionId: Int,
    ): PlaceOutcome {
        if (placeSecurityException) throw SecurityException()
        placed += address to subscriptionId
        return placeOutcome
    }
}

class FakeCallPermissions(
    var readPhoneState: Boolean = true,
    var answerPhoneCalls: Boolean = true,
    var callPhone: Boolean = true,
) : CallPermissions {
    override fun readPhoneState() = readPhoneState

    override fun answerPhoneCalls() = answerPhoneCalls

    override fun callPhone() = callPhone
}

class RecordingTapToCallNotifier : TapToCallNotifier {
    val posted = mutableListOf<Pair<String, Int>>()

    override fun post(
        address: String,
        subscriptionId: Int,
    ) {
        posted += address to subscriptionId
    }
}
