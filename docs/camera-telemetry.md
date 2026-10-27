# Embedded GoPro camera data (F30)

Add a GoPro movie normally. If its progressive MP4/MOV index contains a `gpmd` track, a nonmodal banner offers **Add camera data** or **Skip**. Existing movies have **Add embedded camera data…** in their input inspector. Extraction runs in a worker; failure leaves the project intact. Adding it is one undoable change. External RCZ/CSV sources and their display mappings remain available. When this is the first data input, previously unassigned data widgets receive it.

The new data input references the original movie, so no private CSV or duplicate video is written. Its saved camera identity links it to that physical clip’s source trim, project delay, rate, joined position and loops. Its offset is a residual synchronization adjustment; the data-event wizard and frame nudges work in that clock. Verify a visible event: recording together does not guarantee zero sensor latency. Source trim/rate controls belong to the camera. To relink or remove the camera, first remove its linked data input, then add data from the replacement. This prevents stale telemetry being silently paired with a different movie.

Each physical movie has its own data source. Joining camera clips does not concatenate their data into one table. Choose the appropriate data input per display/timeline segment. Embedded data is retained in `.orrp` projects; reusable templates strip camera identities and source paths. Native RRP export refuses this new association because its encoding has not been verified.

Supported streams:

- GPS5: latitude, longitude, altitude, 2D/3D speed, fix and dilution of precision; GPSU provides UTC.
- GPS9: the newer nine-field GPS layout, including UTC, fix and dilution. Preferred when both GPS layouts occur in a packet.
- ACCL and GYRO: three camera axes, in m/s² and rad/s. These intentionally have no longitudinal/lateral vehicle-G assignments. Existing GPS-derived motion remains available when usable GPS exists.

Invalid GPS fixes produce missing coordinates/speed. DOP is dimensionless and is not automatically assigned to GPS accuracy in meters. Movie time zero, leading empty edits, metadata timestamps, gaps and the movie duration are retained. Sensors are sampled uniformly within each metadata packet; per-sensor latency and timestamp jitter are not calibrated. UTC anchors the movie clock. A recording without GPS yields motion channels only; external logger data may still be needed for speed, position and engine channels.

The reader skips video payloads and reads a bounded movie index and metadata packets. It supports 32/64-bit chunk offsets and simple rate-one edit lists. Fragmented MP4, multiple metadata tracks/devices with the same stream key, complex edits, non-GoPro embedded formats, orientation-to-vehicle calibration and cross-file sensor concatenation are outside this implementation. Oversized/malformed indexes and sample layouts fail with a diagnostic. Limits are 64 MiB movie index, 256 MiB encoded metadata, 16 MiB per packet, two million decoded sensor samples and one million merged rows.

`OpenRaceRender inspect-data camera.mp4 --time 90` inspects embedded channels directly. Ordinary Add input/Finder still treats movies as videos.

## Validation

Original synthetic tests cover GPS5/GPS9 scaling, invalid fixes, movie-zero/UTC, camera axes, 64-bit offsets, malformed inputs, linked rate/trim/loop synchronization, saved associations and portable templates. Editor tests cover optional import, external mapping, persistence, Undo and atomic failures. `scripts/validate-camera-telemetry.py` constructs an original video/metadata track and independent CSV, then compares exact snapshots through rate/trim/loop changes and marked/full/chunk encoded output.

The user's Road Test GoPro recording was read locally: 109,102 merged rows across 538.78825 seconds, ACCL/GYRO present, GPS absent. At packet 90's exact timestamp, our indexing/scaled values agree with GoPro's separate sample MP4 reader within 4e-12. No private media or telemetry is committed. Native RR3 and live GUI validation remain unavailable because the computer-use service returns `cgWindowNotFound`; native pixel parity is not claimed.

Implementation references: [GoPro GPMF format and decoder](https://github.com/gopro/gpmf-parser), [GoPro's sample movie reader](https://github.com/gopro/gpmf-parser/blob/main/demo/GPMF_mp4reader.c), and the locally mirrored RaceRender data-acquisition/multiple-input guides. The pinned, permissively licensed decoder and attribution are recorded in [third-party notices](../THIRD_PARTY_NOTICES.md).
