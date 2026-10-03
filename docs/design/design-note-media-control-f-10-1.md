# Design note: Media control (F-10.1)

- **Issue:** E72-01
- **Date:** 2026-10-02
- **Phase:** 7

## Overview

F-10.1 media control allows a paired Mac to view now-playing metadata from the phone and send
transport commands (play/pause/next/previous) to the active media session. This note decides the
wire-protocol channel and message shape.

## Design decisions

### 1. Media control rides the STATUS channel

SPEC.md §4 ("Channel enumeration") declares the channel set closed and exhaustive for this protocol
version: a peer rejects any channel value outside the nine defined ones (`UNKNOWN_CHANNEL`), so a new
channel value would break v1 peers and need a protocol version bump. Media control therefore reuses
an existing channel. It goes on `STATUS`, the device-state domain that already carries `DeviceStatus`
and `Ring`/`RingStop`, rather than NOTIFY, CONTROL or CLIPBOARD:

- **Domain fit:** now-playing metadata is device state pushed phone to Mac, and transport commands are
  small Mac-to-phone device actions, the same shape as `Ring`/`RingStop`.
- **Flow control:** `STATUS` has its own credit ledger (SPEC.md §4, D-01), so media traffic cannot
  starve notifications, clipboard or files.
- **Payload range:** Envelope field numbers 130-139 are reserved for `media_control.proto`; the field
  number, not the channel, identifies the message type.

No `Channel` enum change is made.

### 2. Message shape and flow

**Phone → Mac (metadata push, on active session change):**
- `NowPlaying` message: title, artist, playback state (PLAYING, PAUSED, STOPPED), and optional album and duration.
  - Sent when MediaSessionManager detects an active session or a metadata change in the current session.
  - Sent unsolicited after a session enters Ready state (matching RotationChallenge pattern, D-74; see E72-01 scope note below).
  - Title and artist are untrusted peer input: SPEC.md §11 sanitization applies before rendering (E01-23).
  - Capped at 256 characters (title) and 128 characters (artist) per E01-22 resource caps.

**Mac → Phone (transport commands):**
- `PlayPause`, `Next`, `Previous`, `Stop` messages: simple signals with no payload beyond the command type.
  - Dispatched to the active media session's TransportControls.
  - If no active session or the session lacks support for the command, the message is silently dropped.

**Capability signaling:**
- If the phone lacks `READ_MEDIA_SESSION_STATE` or `BIND_NOTIFICATION_LISTENER_SERVICE` permissions, it sends `CapabilityUnavailable{FEATURE_MEDIA_CONTROL}` unsolicited after Ready state and never sends NowPlaying.
- This matches the pattern from E30-02 notification-listener and E72-04 focus-sync (seam pattern from E00-21).

### 3. Carrier layer: STATUS channel on the existing connection

Media control messages ride the `STATUS` channel of the mTLS connection established in SPEC.md §3, using
the existing credit-grant flow from §4 (E01-04). Commands and metadata share that one channel and ledger.

**Alternative considered and rejected:** A dedicated media connection. This adds listener port and connection-setup complexity for a low-bandwidth feature that already has two multiplexed connections available (SPEC.md §3, ADR-002). Reusing the existing control/data pair matches SPEC.md D-03 (one listener port, one audited codepath).

## Proto structure (E72-02 implementation)

E72-02 will add to `protocol/proto/tandem/v1/`:

- New file: `protocol/proto/tandem/v1/media_control.proto` with messages:
  ```proto
  enum PlaybackState {
    PLAYBACK_STATE_UNSPECIFIED = 0;
    PLAYBACK_STATE_PLAYING = 1;
    PLAYBACK_STATE_PAUSED = 2;
    PLAYBACK_STATE_STOPPED = 3;
  }

  message NowPlaying {
    string title = 1;          // <= 256 chars
    string artist = 2;         // <= 128 chars
    PlaybackState state = 3;
    optional string album = 4; // <= 128 chars
    optional int64 duration_ms = 5;
  }

  message PlayPause {}
  message Next {}
  message Previous {}
  message Stop {}
  message CapabilityUnavailable {
    enum Feature {
      FEATURE_UNSPECIFIED = 0;
      FEATURE_MEDIA_CONTROL = 1;
    }
    Feature feature = 1;
  }
  ```

- Update `protocol/proto/tandem/v1/envelope.proto` to add MEDIA_CONTROL payloads to the `payload` oneof (fields 130-135, reserved range 130-139).
- Conformance vectors in `protocol/vectors/media_control/` for round-trip tests (E72-02 acceptance: "Media-control vectors round-trip on both codecs").

## Permissions and seams

- **Android:** `READ_MEDIA_SESSION_STATE` (new, added to the shared Android manifest via E00-28).
  Fallback: if unavailable, send `CapabilityUnavailable{FEATURE_MEDIA_CONTROL}` and do not attempt to read MediaSessionManager.
- **Seam:** `MediaSessionGateway` in feature-local implementation, backed by `MediaSessionManager` and `MediaController` in production, with a recording fake in `TandemTestSupport` for unit tests (E00-21 pattern).

## macOS half (F-10.1 display side)

E72-02 covers Android media-session capture and forwarding. The macOS receiver (E72-08, split in review cycle 3) will:
- Listen on the STATUS channel for the media-control payloads and update UI with NowPlaying metadata.
- Offer Now Playing widget and media-playback controls (play/pause, next, previous) in the app or menu bar.
- Send PlayPause, Next, Previous, Stop commands on Mac user interaction.
- Display CapabilityUnavailable as "Feature not available on this phone" if the phone signals it.

## References

- PRD F-10.1, F-10.4
- SPEC.md §4 (channels and flow control, E01-04) and D-01 (no PHOTOS channel)
- E30-02 (NotificationListenerService and capability signaling pattern)
- E72-04 (InterruptionFilterGateway seam pattern)
- E01-22 (resource caps, E01-23 untrusted-string sanitization)
