# Spike E13-01: DataStore vs Room for Android trust-store persistence

**Backlog:** `docs/planning/backlog/phase-1.yaml` id `E13-01` (GitHub #167)
**PRD:** F-1.2 (trust store), invariant 3 (CLAUDE.md: trust bound to SPKI fingerprint only)
**Question:** Proto DataStore or Room for the Android trust store (E13-02) -- migration story,
query needs, atomic unpair-delete, and JVM testability?

**Recommendation: GO with Room** (`androidx.room:room-runtime` + KSP, driven by
`androidx.sqlite:sqlite-bundled`'s `BundledSQLiteDriver` in tests). Both candidates satisfy the
E13-01 go/no-go ("must delete a record atomically before `unpair()` returns"); Room is chosen for
its off-the-shelf `Migration` runner (a closer fit to E13-03's ask than hand-rolled proto
compatibility) and its `@Transaction`-wrapped DAO methods (a natural fit for the D-34 atomic pin
swap). See "Decision" below for the full trade-off.

Spike code: `spikes/e13-01-trust-store/` (standalone Gradle project, AGP not applied -- plain
`kotlin("jvm")` modules only, matching how the real question needs to be answered: can the trust
store's CRUD/migration logic be tested without Robolectric). Not part of the real `android/`
module tree.

## Environment

- `JAVA_HOME=/Users/miggi/Library/Java/JavaVirtualMachines/corretto-21.0.8/Contents/Home` (Corretto 21.0.8).
- Gradle 9.7.1 (wrapper copied from `spikes/e03-03-keystore-sslsocket/`), Kotlin `2.4.20` (matches
  `android/gradle/libs.versions.toml`).
- `datastore-spike/`: `androidx.datastore:datastore:1.2.1`, `com.google.protobuf:protobuf-javalite:4.36.2`
  + `com.google.protobuf` Gradle plugin `0.10.0` (protoc `4.36.2`). No KSP, no annotation
  processing at all -- protobuf codegen is a separate `protoc` invocation, decoupled from the
  Kotlin compiler.
- `room-spike/`: `androidx.room:room-runtime:2.8.5`, `androidx.room:room-compiler:2.8.5` via
  `com.google.devtools.ksp` `2.3.10`, `androidx.sqlite:sqlite-bundled:2.7.1` for
  `BundledSQLiteDriver` in both `main` and `test` source sets.
- Both modules: `org.jetbrains.kotlinx:kotlinx-coroutines-core`/`-test` `1.11.0`, JUnit 5 (`6.1.3`
  BOM), `useJUnitPlatform()`. No Robolectric, no `androidx.test`, no Android Gradle plugin, no
  emulator, anywhere in either module.
- Verified: `./gradlew :datastore-spike:test :room-spike:test` -- 10 + 9 tests, all green, from a
  clean build. Commands reproduced during this spike:
  ```sh
  export JAVA_HOME=/Users/miggi/Library/Java/JavaVirtualMachines/corretto-21.0.8/Contents/Home
  cd spikes/e13-01-trust-store
  ./gradlew clean :datastore-spike:test :room-spike:test
  ```

## What was built

Both modules implement the same shape: the E13-02 peer record
`{deviceId, displayName, spkiSha256, pairedAt, lastSeen, capabilities}`, keyed only by the
fingerprint (`spkiSha256Hex` here; the real code gets the 32-byte `SpkiFingerprint` value type
from E10-03/E13-02), with `put`/`get`/`list`/`delete` plus a `swapPin(old, new)` operation
prototyping the D-34/E70 atomic pin swap, and one migration test each prototyping E13-03 (a field
added after v1, existing records preserved, new field defaulted).

- **DataStore**: `datastore-spike/src/main/proto/trust_store.proto` (`TrustStore { repeated
  PeerRecordProto records }`, proto3), a `Serializer<TrustStore>`
  (`TrustStoreSerializer.kt`), and `DataStoreTrustStore.kt` wrapping
  `DataStoreFactory.create(...)` with `updateData { ... }` transactions for every write
  (including `swapPin`, which removes the old fingerprint and adds the new record in one
  `updateData` call).
- **Room**: `room-spike/src/main/kotlin/.../PeerRecordEntity.kt` (`@Entity`, `spkiSha256Hex` as
  `@PrimaryKey`), `PeerRecordDao.kt` (`@Insert(OnConflictStrategy.REPLACE)`, `@Query` lookups, a
  `@Transaction fun swapPin(...)` calling `deleteByFingerprint` then `upsert` in one DB
  transaction), `TrustDatabase.kt`, and `RoomTrustStore.kt` opening either a file-backed or
  in-memory `TrustDatabase` via `Room.databaseBuilder<TrustDatabase>(...)`/
  `Room.inMemoryDatabaseBuilder<TrustDatabase>()`, both with `.setDriver(BundledSQLiteDriver())`.

Test files: `DataStoreTrustStoreTest.kt` + `TrustStoreMigrationTest.kt` (10 tests),
`RoomTrustStoreTest.kt` + `TrustDatabaseMigrationTest.kt` (9 tests). Every E13-02/E13-03/E13-05
acceptance bullet has a corresponding test in both modules: put/get by fingerprint, unknown
fingerprint returns null, list after two puts, put-replaces-existing, reopen-survives-restart,
unpair-then-get-same-process, unpair-then-reopen, atomic pin swap, and the v1->v2 migration.

## Finding 1: neither technology needs Robolectric on the JVM (corrects an assumption in E13-02)

E13-02's own description says tests need "Robolectric, E00-20, only if E13-01 picks Room" --
that assumption predates Room's multiplatform rewrite. As of Room 2.7 (`BundledSQLiteDriver`,
officially documented for "Test on your host machine (JVM)" in Room's testing guide) Room runs on
plain JVM JUnit with **no Context, no Android framework class, no Robolectric**, exactly like
DataStore always could. Both `datastore-spike` and `room-spike` are plain `kotlin("jvm")` modules
with zero Android/Robolectric dependency, and both suites pass:

| | tests | total suite time (JUnit XML) | notes |
|---|---|---|---|
| DataStore | 10 | ~0.16 s | flat; no per-test outlier |
| Room | 9 | ~0.36 s | first test ~0.31 s (one-time native-lib extraction for `BundledSQLiteDriver`), rest 3-12 ms |

This removes what would otherwise have been the deciding factor. **E13-02's TDD notes should drop
the "Robolectric only if Room" caveat regardless of which store is picked.**

## Finding 2: migration story differs in kind, not just mechanism

- **DataStore**: proto3 field addition is wire-compatible by construction -- there is no
  "migration runner" to write. `TrustStoreMigrationTest` writes bytes with a frozen
  `TrustStoreV1Fixture` message (no `pending_rotation` field) and reads them back through the
  current `TrustStoreSerializer`/`TrustStore`; the new field silently defaults to `false`. This is
  free for additive changes and impossible to forget to wire up (there's no registry to miss an
  entry in), but it has no explicit hook for anything beyond "new field, static default" --  a
  rename, a type change, or a computed migration (derive a new column from two old ones) needs
  bespoke code layered on top, and an accidentally-reused field number silently corrupts data
  instead of failing loudly.
- **Room**: `TrustDatabaseMigrationTest` opens a real v1 database (`TrustDatabaseV1`, one entity,
  `version = 1`), closes it, then opens the same file with `TrustDatabaseV2` (added
  `pendingRotation` column) via an explicit `Migration(1, 2)` that runs
  `ALTER TABLE peer_record ADD COLUMN pendingRotation INTEGER NOT NULL DEFAULT 0`. This is exactly
  the "schema-version field and migration runner" E13-03 asks for, as a first-class Room concept:
  every version bump is a registered `Migration` object, and Room fails loudly (throws) if a
  migration is missing or the destination schema doesn't match what a migration produces, rather
  than silently reading stale/wrong data. Room also has a bundled schema-export +
  `MigrationTestHelper` story for asserting a written migration's *end schema* matches the
  `@Database` declaration bit-for-bit (not exercised in this spike to keep scope small, but it
  exists off the shelf).

Given E13-03 explicitly wants a versioned migration runner (not just "new fields default"), Room's
built-in mechanism is a closer match than building an equivalent runner by hand on top of proto
compatibility.

## Finding 3: atomicity -- both satisfy the go/no-go, expressed differently

- **DataStore**: `DataStore.updateData` is a suspending, single-writer transaction (internal
  `Mutex`) whose result is committed to disk via an atomic temp-file-then-rename; two
  "concurrent" callers (`concurrentPutAndDelete_bothSerializeThroughUpdateData_noLostUpdate`)
  serialize through it with no lost update. `delete()` and `swapPin()` are both single
  `updateData` calls, so a caller awaiting `unpair()`/`swapPin()` sees the change committed to
  disk before the suspend function returns.
- **Room**: a single DAO `@Query("DELETE ...")` call is already atomic (SQLite treats one
  statement as an implicit transaction). The D-34 pin swap needs two statements (delete old row,
  insert new row) to be indivisible, which is exactly what `@Transaction fun swapPin(...)` gives:
  a reader can never observe both fingerprints, or neither, mid-swap.

Both are a "Go" on the E13-01 acceptance bullet. Room's version is arguably more legible (the
transaction boundary is a language-level annotation over two named DAO calls, vs. hand-rolled list
filtering inside a builder lambda), but this is a style preference, not a capability gap.

## Finding 4: query needs

The epic scope is "few records" with only two access patterns (get-by-fingerprint, list-all), so
this is not a real discriminator. DataStore's `get`/`list` do a linear scan of the in-memory
`recordsList` (fine at this scale); Room's `@PrimaryKey`-indexed lookup is technically higher
throughput but the difference is unmeasurable at expected trust-store sizes (single digits to low
tens of paired devices). If the store ever needs filtering/sorting beyond what's scoped today,
Room's SQL gives that for free; DataStore would need to load-and-filter in Kotlin.

## Finding 5: dependency weight

`./gradlew :<module>:dependencies --configuration runtimeClasspath`, resolved jar sizes from the
Gradle cache:

| Artifact | Size | Notes |
|---|---|---|
| `datastore-jvm:1.2.1` | 5.2 KB | thin facade |
| `datastore-core-jvm:1.2.1` | 166 KB | pulls in `okio` + `kotlinx-serialization-json` transitively (used internally, not by our code) |
| `protobuf-javalite:4.36.2` | 999 KB | **already a dependency of the real `android/` project** (`libs.versions.toml` pins `protobuf = "4.35.0"`) for the wire protocol codec -- not incremental weight if DataStore is chosen |
| `room-runtime-jvm:2.8.5` | 305 KB | |
| `sqlite-bundled-jvm:2.7.1` | 3.6 MB | JNI-compiled SQLite for the host JVM -- **test-only weight**: production Android builds use the tiny `androidx.sqlite:sqlite-framework` `AndroidSQLiteDriver` (wraps the OS's built-in SQLite), so `sqlite-bundled` should be scoped `testImplementation`/`kspTest` only, never shipped in the release APK |

Net: DataStore's production-relevant new weight is ~171 KB (protobuf is sunk cost either way).
Room's production-relevant new weight is ~305 KB (room-runtime) plus whatever the KSP-generated
`_Impl` class adds (not measured; expected to be small for one entity/one DAO). The 3.6 MB
`sqlite-bundled` jar is real but confined to the test classpath.

## Finding 6: KSP / Kotlin 2.4.20 compatibility

`android/gradle/libs.versions.toml` pins `kotlin = "2.4.20"`. KSP decoupled its version numbering
from the Kotlin compiler version as of KSP 2.3.0 (no more `<kotlin-version>-<ksp-version>` combined
tags); Kotlin's own quickstart docs pair `kotlin("jvm") version "2.4.20"` with
`id("com.google.devtools.ksp") version "2.3.10"` directly. That combination is what `room-spike`
uses, `androidx.room:room-compiler:2.8.5` (the current stable Room release) ran under it with no
warnings or version-mismatch errors, in both the `main` and `test` source sets (the latter needed
its own `kspTest(...)` dependency -- easy to forget, see "Gotchas" below). DataStore needs no KSP
at all, so it carries zero exposure to this compatibility axis; that is a real, if narrow,
advantage for DataStore in a repo that must track fast-moving Kotlin releases.

## Finding 7: encryption at rest

Neither library bakes in encryption; both would need the same shape of extra work, which is out
of scope for E13-01/E13-02/E13-06 and consistent with the Mac side's own decision (E50-09: "no
application-level encryption in v1 (FileVault assumed)"). For the record:

- DataStore: a custom `Serializer` can wrap `readFrom`/`writeTo` around a Keystore-backed AES
  `Cipher` (e.g. via Tink's `Aead`), decrypting/encrypting the proto bytes transparently.
- Room: historically `SQLCipher` (`net.zetetic:android-database-sqlcipher`) supplied an encrypting
  `SupportSQLiteOpenHelper.Factory`; that interface predates Room's 2.7 driver-based
  (`SQLiteDriver`/`SQLiteConnection`) architecture used in this spike, and SQLCipher's compatibility
  with the new driver API was not verified here -- flagged as an open question for whoever picks
  this up in a future phase, not a blocker for E13-01/E13-02 (Android relies on file-based
  encryption at the OS level for v1, matching D-28's scope).

## Decision

**Room**, for E13-02 onward:

1. `Migration` is a closer, off-the-shelf match for E13-03's "schema-version field and migration
   runner" than layering an equivalent runner on top of proto's automatic (additive-only)
   compatibility, and fails loudly instead of silently on a schema mismatch -- the safer failure
   mode for a trust store.
2. `@Transaction`-wrapped DAO methods are a direct, idiomatic expression of the D-34 atomic pin
   swap.
3. The historic reason to prefer DataStore -- avoiding Robolectric -- no longer applies (Finding 1);
   both are equally plain-JVM-testable.
4. The extra cost (KSP toolchain coupling, a 3.6 MB test-only native SQLite jar) is acceptable and
   test-scoped.

E13-02 should also update its own TDD note to remove the "Robolectric, E00-20, only if E13-01
picks Room" caveat -- it does not apply to either outcome.

## Gotchas for whoever implements E13-02

- KSP must be added to **both** `ksp(...)` (main) and `kspTest(...)` (test) configurations if any
  `@Database`/`@Dao`/`@Entity` lives in test sources (e.g. a migration-fixture schema); forgetting
  `kspTest` fails at runtime with a `ClassNotFoundException` for the generated `_Impl`, not at
  compile time, since `kspTestKotlin` is silently `SKIPPED` rather than erroring.
- `Room.inMemoryDatabaseBuilder<T>()`/`Room.databaseBuilder<T>(name)` (the generic, no-`Context`
  entry points from Room's KMP-unified API) work in a plain single-target `kotlin("jvm")` module
  with **no** `@ConstructedBy`/`expect`/`actual` boilerplate -- that machinery is only required for
  genuine multi-target Kotlin Multiplatform projects (no JVM reflection on Native targets); Android
  (a single JVM-family target) does not need it.
- DataStore enforces at most one live `DataStore` instance per file per process
  (`IllegalStateException: There are multiple DataStores active for this file`); a test that wants
  to prove "survives restart" cannot simply construct a second `DataStoreTrustStore` over the same
  path in the same test process -- read the persisted bytes back directly instead (see
  `readPersistedRecords()` in `DataStoreTrustStoreTest.kt`). This is not a limitation in production
  (a real restart is a fresh process), only a test-construction detail.
- The protobuf Gradle plugin's Kotlin DSL errors ("Cannot add a PluginOptions with name 'java' as
  one already exists") if you call `builtins { id("java") { option("lite") } }` -- the `java`
  builtin already exists by default for a Kotlin/JVM project; configure it via
  `task.builtins.getByName("java") { option("lite") }` instead.
