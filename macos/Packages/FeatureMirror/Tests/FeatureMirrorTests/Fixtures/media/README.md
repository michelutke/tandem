# Media fixtures

`h264-720p-30f.annexb` (shared with E61-06), generated once with:

```sh
ffmpeg -f lavfi -i testsrc=size=1280x720:rate=30 -frames:v 30 -pix_fmt yuv420p -c:v libx264 \
  -profile:v baseline -g 30 -bf 0 -x264-params "keyint=30:scenecut=0:slices=1" \
  -f h264 h264-720p-30f.annexb
```

`hevc-720p-30f.annexb` (E61-06), generated once with:

```sh
ffmpeg -f lavfi -i testsrc=size=1280x720:rate=30 -frames:v 30 -pix_fmt yuv420p -c:v libx265 -tag:v hvc1 \
  -preset ultrafast -x265-params "keyint=30:min-keyint=30:scenecut=0:bframes=0:repeat-headers=1:log-level=error" \
  -f hevc hevc-720p-30f.annexb
```

`h264-720p-30f-corrupt.annexb` is `h264-720p-30f.annexb` with the slice payload of the 15th NAL unit
(frame 10, bytes after the 4-byte header) replaced by alternating `0x00 0xFF`.

`timestamp-overlay-800x16.pgm` (E61-08), binary PGM (P5, 8-bit luma) of the timestamp overlay for
`frameIndex = 123456789`, `clockMs = 1700000123456`. Layout: 96 cells of 8x8 px in a row at the top-left,
each cell white (255) for bit 1 and black (0) for bit 0, the 32-bit frame index first, then the 64-bit clock
value, both MSB first; every other pixel is 0. The Android `TimestampOverlayEncoder` test and the macOS
`TimestampOverlayDecoder` test both read this one file (the Android build points `tandem.overlayFixture` here).
