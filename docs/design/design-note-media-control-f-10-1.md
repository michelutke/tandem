# Design note: Media control (F-10.1)

- **Issue:** E72-01
- **Date:** 2026-10-02
- **Phase:** 7

## Overview

F-10.1 media control allows a paired Mac to view now-playing metadata from the phone and send
transport commands (play/pause/next/previous) to the active media session. This note decides the
wire-protocol channel and message shape.

## Design decisions

### 1. New MEDIA_CONTROL channel (ID 10)

Media control gets its own channel rather than reusing NOTIFY, CONTROL, or STATUS because:

- **Feature scope and traffic patterns:** F-10.1 is a distinct capability (media session information and control) with bidirectional flow (metadata push from phone, commands from Mac). Previous feature-specific channels (NOTIFY, CLIPBOARD, FILES, SMS, CONTACTS, CALLS, STATUS) each establish this pattern: one feature → one channel.
- **Flow-control isolation:** Per SPEC.md §4 (D-01), separate channels prevent one feature's traffic from starving others. Media metadata updates and control commands should not contend with clipboard, notifications, or status messages.
- **Extensibility:** F-10.4 (multi-Mac) and future media enhancements (e.g., queue management, playback history) are easier to accommodate with a dedicated channel.

The channel is added to `Channel` enum in `protocol/proto/tandem/v1/channel.proto`:
```proto
CHANNEL_MEDIA_CONTROL = 10;
```

This extends the closed channel set documented in SPEC.md §4 from nine to ten values.

### 2. Message shape and flow

**Phone → Mac (metadata push, on active session change):**
- `NowPlaying` message: title, artist, playback state (PLAYING, PAUSED, STOPPED), and optional album and duration.
  - Sent when MediaSessionManager detects an active session or a metadata change in the current session.
  - Sent unsolicited after a MEDIA_CONTROL session enters Ready state (matching RotationChallenge pattern, D-74; see E72-01 scope note below).
  - Title and artist are untrusted peer input: SPEC.md §11 sanitization applies before rendering (E01-23).
  - Capped at 256 characters (title) and 128 characters (artist) per E01-22 resource caps.

**Mac → Phone (transport commands):**
- `PlayPause`, `Next`, `Previous`, `Stop` messages: simple signals with no payload beyond the command type.
  - Dispatched to the active media session's TransportControls.
  - If no active session or the session lacks support for the command, the message is silently dropped.

**Capability signaling:**
- If the phone lacks `READ_MEDIA_SESSION_STATE` or `BIND_NOTIFICATION_LISTENER_SERVICE` permissions, it sends `CapabilityUnavailable{MEDIA_CONTROL}` unsolicited after Ready state and never sends NowPlaying.
- This matches the pattern from E30-02 notification-listener and E72-04 focus-sync (seam pattern from E00-21).

### 3. Carrier layer: MEDIA_CONTROL channel within existing control/data connections

Media control messages ride on the same two mTLS connections established in SPEC.md §3:

- **CONTROL connection:** carries transport commands (PlayPause, Next, Previous, Stop) using the existing credit-grant flow from §4 (E01-04). Command latency is critical for user experience; interleaving with heartbeat and other control traffic is acceptable.
- **NOTIFY connection (or new DATA connection):** carries metadata pushes (NowPlaying) using the credit-grant flow. Metadata updates are lower-latency-sensitive than command acknowledgment.

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

- Update `protocol/proto/tandem/v1/envelope.proto` to add MEDIA_CONTROL payloads to the `payload` oneof (field numbers TBD, following the reserved-range pattern in §20, E01-14).
- Update `protocol/proto/tandem/v1/channel.proto` to add `CHANNEL_MEDIA_CONTROL = 10` and update the comment to reflect ten channels.
- Conformance vectors in `protocol/vectors/media_control/` for round-trip tests (E72-02 acceptance: "Media-control vectors round-trip on both codecs").

## Permissions and seams

- **Android:** `READ_MEDIA_SESSION_STATE` (new, added to the shared Android manifest via E00-28).
  Fallback: if unavailable, send `CapabilityUnavailable{MEDIA_CONTROL}` and do not attempt to read MediaSessionManager.
- **Seam:** `MediaSessionGateway` in feature-local implementation, backed by `MediaSessionManager` and `MediaController` in production, with a recording fake in `TandemTestSupport` for unit tests (E00-21 pattern).

## macOS half (F-10.1 display side)

E72-02 covers Android media-session capture and forwarding. The macOS receiver (E72-08, split in review cycle 3) will:
- Listen on MEDIA_CONTROL channel and update UI with NowPlaying metadata.
- Offer Now Playing widget and media-playback controls (play/pause, next, previous) in the app or menu bar.
- Send PlayPause, Next, Previous, Stop commands on Mac user interaction.
- Display CapabilityUnavailable as "Feature not available on this phone" if the phone signals it.

## References

- PRD F-10.1, F-10.4
- SPEC.md §4 (channels and flow control, E01-04) and D-01 (no PHOTOS channel)
- E30-02 (NotificationListenerService and capability signaling pattern)
- E72-04 (InterruptionFilterGateway seam pattern)
- E01-22 (resource caps, E01-23 untrusted-string sanitization)
