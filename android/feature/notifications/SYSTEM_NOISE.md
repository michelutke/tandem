# System noise: default notification filter (E30-03)

Before any notification reaches the NOTIFY channel, `NotificationFilter.shouldForward` applies the
default filter. A notification is dropped (never mapped, never forwarded) when it matches any of
these rules; a notification from any other app is forwarded by default:

1. Tandem's own package.
2. Packages `android` and `com.android.systemui` (system UI media/volume/USB/foreground-service
   notifications).
3. Any notification carrying `FLAG_FOREGROUND_SERVICE`, from any app.
4. Group-summary notifications (`FLAG_GROUP_SUMMARY`) — their children are still forwarded
   individually; only the summary itself is dropped.
5. `MediaStyle` notifications — media control is a separate future feature (F-10.1).

This is the complete rule set; it is authoritative in `docs/protocol/SPEC.md`'s NOTIFY section,
which cross-references this file. A per-app allow/deny setting (E30-04) overrides this default
filter and is phone-side only.

Implementation: `dev.tandem.feature.notifications.NotificationFilter`.
