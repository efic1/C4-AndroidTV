# Android TV / Google TV Watch Support

This change reclassifies the driver's main proxy so the device can be
selected as a **Display** in a Control4 room (and therefore appear under
the **Watch** experience), instead of only working as a hidden
set-top-box-style source. It also adds volume/mute key support, which the
`tv` proxy class requires but the previous `cable` proxy class never
exposed.

Based on: `patch-2`

## Background

The driver's proxy `5001` was declared with proxy class `cable` — Control4's
class for set-top-box/tuner-style *source* devices. A `cable`-class device
can only ever be wired in as a source feeding a separate Display device; it
can never itself be picked as the room's Display. For an all-in-one smart
TV (the TV *is* the display, not a box plugged into one), this meant the
driver could never appear as a Watch option, regardless of how the room was
configured.

`patch-2` was chosen as the base for this change (rather than `main`)
because it already uses `<method>tlsv13</method>` for the pairing/command
SSL connections. `main` still uses `<method>tlsv1</method>`, and TLS 1.0
does not reliably complete a pairing handshake against modern Android TV /
Google TV firmware. `patch-2` is also the branch this was actually tested
against.

## What changed

### `driver.xml`

- **Proxy `5001` reclassified from `cable` to `tv`** — the actual Control4
  proxy class for Display devices. Renamed from "Android Device" to
  "Android TV".
- **Capabilities rewritten to match a `tv` proxy**:
  - `video_provider_count` and `video_consumer_count` set to `0` (this
    device is a terminal display, not a video passthrough/switcher).
  - Added `has_discrete_volume_control`, `has_up_down_volume_control`,
    `has_toggle_mute_control`.
  - `audio_provider_count` kept at `1` (TV's own audio output).
- **Removed connections that no longer match the new capability counts**:
  the old video "AV Out" connection and the two "From Mini Drivers"
  video/audio consumer connections (`id 1101`, `3101`, `2000` on proxy
  `5001`).
- **UI connection (`id 5001`) reclassed from `SATELLITE` to `TV`** — the
  connection class Control4 uses to identify this device as a display
  candidate, matching what real Control4-certified TV drivers use.
- **Added a `Room Selection - Output` connection** (`id 7000`, type `7`,
  classes `AUDIO_SELECTION` / `AUDIO_VOLUME` / `VIDEO_SELECTION`) — this
  connection type is what makes a device selectable in a room's video/audio
  output picker; it was entirely absent before, since a `cable` source
  device is never picked as an output.
- **Added three new properties**: `VOLUME UP Mapping` (default `24`),
  `VOLUME DOWN Mapping` (default `25`), `MUTE Mapping` (default `164`) —
  the standard Android keycodes for volume/mute, exposed the same way the
  driver already exposes all its other key mappings.
- Bumped `<version>`.
- `OnlineCategory` changed from `media_player` to `tv`.
- `patch-2`'s existing `tlsv13` SSL method, and its passthrough/mini-app
  switcher logic (`PASSTHROUGH_PROXY`, `SWITCHER_PROXY`, the `SET_INPUT`
  handling on proxy `5002`), are untouched by this change.

### `driver.lua`

- Added handling in `ProcessInputCommand` for `VOL_UP`, `VOL_DOWN`, and
  `MUTE`/`MUTE_TOGGLE` commands, following the same
  `CMD`/`START_CMD`/`PULSE_CMD`/`STOP_CMD`/`END_CMD` pattern already used
  for every other key mapping in this driver. Without this, a `tv` proxy's
  volume slider/mute button in Navigator would do nothing, since the old
  `cable`-based driver never received these commands at all.
- Bumped `DriverVersion` (shows in Composer's "Driver Version" property —
  useful for confirming a fresh build actually loaded after re-adding the
  device).
- All of `patch-2`'s existing logic (passthrough/switcher handling,
  `RegisterRooms`, the extended device-descriptor fingerprint case) is
  untouched.

## Testing notes

- Verified `driver.xml` is well-formed XML and packages cleanly with
  Control4's official `dp3` driver packager.
- Pairing confirmed working on this `patch-2` base (this is the branch
  the reporting user's working setup was already running).
- Room video/Watch-tile behavior after the proxy reclassification has
  **not yet been confirmed end-to-end** on real hardware — the change is
  based on directly comparing this driver's structure against a real
  Control4-certified TV driver's `driver.xml`. Removing and re-adding the
  device (rather than updating an existing instance) is required for the
  proxy class change to take effect.
