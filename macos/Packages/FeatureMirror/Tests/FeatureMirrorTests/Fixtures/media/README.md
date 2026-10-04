# Media fixtures

`h264-720p-30f.annexb` (shared with E61-06), generated once with:

```sh
ffmpeg -f lavfi -i testsrc=size=1280x720:rate=30 -frames:v 30 -pix_fmt yuv420p -c:v libx264 \
  -profile:v baseline -g 30 -bf 0 -x264-params "keyint=30:scenecut=0:slices=1" \
  -f h264 h264-720p-30f.annexb
```
