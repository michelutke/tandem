package dev.tandem.core.crypto

/**
 * The identity key could not be found or read while a paired peer exists (SPEC.md invariants 3, 5).
 * The key is never regenerated in that case: a new SPKI would make every paired Mac reject this phone.
 */
class IdentityKeyUnavailableException : IllegalStateException("Identity key unavailable while peers are paired")
