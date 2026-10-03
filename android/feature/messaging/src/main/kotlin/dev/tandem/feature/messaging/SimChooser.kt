package dev.tandem.feature.messaging

import dev.tandem.protocol.v1.SendSmsErrorCode

/** E50-05 picks the subscription a `SendSmsRequest` sends through (docs/protocol/SPEC.md #sms-channel "Send"). */
sealed interface SimChoice {
    /** Send through [subscriptionId]; 0 means the default `SmsManager`. */
    class Use(
        val subscriptionId: Int,
    ) : SimChoice

    class Reject(
        val errorCode: SendSmsErrorCode,
    ) : SimChoice
}

object SimChooser {
    fun choose(
        requestedSubscriptionId: Int,
        active: List<SimInfo>,
        defaultSubscriptionId: Int,
    ): SimChoice =
        when {
            active.isEmpty() -> {
                SimChoice.Use(DEFAULT_MANAGER)
            }

            requestedSubscriptionId != DEFAULT_MANAGER -> {
                if (active.any { it.subscriptionId == requestedSubscriptionId }) {
                    SimChoice.Use(requestedSubscriptionId)
                } else {
                    SimChoice.Reject(SendSmsErrorCode.SEND_SMS_ERROR_CODE_INVALID_SUBSCRIPTION)
                }
            }

            active.any { it.subscriptionId == defaultSubscriptionId } -> {
                SimChoice.Use(defaultSubscriptionId)
            }

            active.size == 1 -> {
                SimChoice.Use(DEFAULT_MANAGER)
            }

            else -> {
                SimChoice.Reject(SendSmsErrorCode.SEND_SMS_ERROR_CODE_SUBSCRIPTION_REQUIRED)
            }
        }

    private const val DEFAULT_MANAGER = 0
}
