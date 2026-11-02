# media_kit_video 2.0.1, Liquiflux copy

Upstream: https://pub.dev/packages/media_kit_video 2.0.1 (MIT, see LICENSE). Used through
`dependency_overrides` in app/pubspec.yaml. Only `windows/` differs from upstream:

- `angle_surface_manager.*`: after mpv draws a frame (`Draw`), it is copied into one of three
  shared textures on the render thread, and the copy is waited for with a D3D11 event query
  before that texture becomes the front one. It never writes the texture Flutter last took
  (`Acquire`), so a frame Flutter is still drawing from is never overwritten. Upstream copied
  into a single shared texture from Flutter's raster thread (`Read`) with only a Flush, so Flutter (another D3D device) could
  sample a half-copied frame (tearing), and the raster thread waited on the lock while mpv
  rendered.
- `video_output.*`: one Flutter descriptor per ring texture; the texture callback returns the
  one `Acquire()` names.
- `LIQUIFLUX_VIDEO_LEGACY=1` in the environment brings back upstream's hand-over, for A/B tests.

To update media_kit_video, re-apply these changes (search for "Liquiflux").
