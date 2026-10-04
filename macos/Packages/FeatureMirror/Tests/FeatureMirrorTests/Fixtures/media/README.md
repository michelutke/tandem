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
