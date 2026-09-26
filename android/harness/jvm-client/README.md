# harness/jvm-client

JVM CLI over the real core/* modules (E15-21). Run: ./gradlew :harness:jvm-client:run --args="--identity-file <path>"; stdin commands CONNECT <host> <port> <fp>, PAIR <uri>, CONFIRM, DISCONNECT, EXIT. On startup, prints `harness-identity-spki: <hex>` (own identity fingerprint, same format as the Mac driver's hook) so a driver script can seed it into a peer's trust store (E12-13).
