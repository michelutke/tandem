package dev.tandem.app.service

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow

/** Test fake (E20-02 tdd): the "E13-02 fake" [ServiceStarterTest] and [TandemServiceTest] use. */
class FakePairedPeerRepository(
    private val hasPairedPeer: MutableStateFlow<Boolean>,
) : PairedPeerRepository {
    constructor(hasPairedPeer: Boolean) : this(MutableStateFlow(hasPairedPeer))

    override fun observeHasPairedPeer(): Flow<Boolean> = hasPairedPeer
}
