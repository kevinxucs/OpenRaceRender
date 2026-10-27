# Videos without a camera

Import telemetry and/or audio, add still images or draw text/shapes/widgets, set the project length in Setup if needed, then export normally. A camera file is no longer required. Preview plays the composition with its audio; file export uses the same renderer and source clocks. A blank scene can produce an opaque black video.

Still-only or source-free designs default to a 60-second project. Recorded data/audio determine automatic length when present; manual or input-bound lengths take precedence. Set In/Out marks, time spans or lap ranges to render a shorter selection. A full-canvas image or shape supplies a background; otherwise it is black. All ordinary grouping/timeline, source timing, picture, output workspace/border and audio controls continue to apply. This exports normal H.264/AAC video, not a transparency-preserving video codec.

An internal tiny original black clip supplies AVFoundation's video timing when there is no real camera track. Its time range is stretched to the project length, while the compositor renders graphics at the selected preview/output frame rate. The clip is hidden from the drawing model, reused within the process, recovered if its temporary file is removed, and never saved as an input, template role or external project dependency. Files live under the system temporary directory and are subject to macOS cleanup. There is no full-session dummy video to encode first.

Camera-free support does not conceal broken camera files: missing required sources still fail preflight, unreadable assets fail decoding, and an input falsely declared as video with no readable video track is explicitly refused. Relink/remove that camera input to render a different composition.

## Validation

The supplied guide's Basics/Display Toolbox/general Create Video pages were read. The guide motivates independent display/media composition but has no dedicated camera-free export chapter. No matching native camera-free workflow or native parity claim has been verified while CUA remains unavailable.

Three core and one editor tests cover still/default/manual/data-derived duration, clock reuse/missing-temp recovery, continuous timed red/green frames across a two-second camera-free composition, unchanged project/no generated dependency persistence, marked export setup and an actual ready-to-play editor item. The full local suite passes 330 tests with the authorized library and graphics services.

`python3 scripts/validate-camera-free.py` generates only original disposable telemetry/art/audio, checks marked full-session and nonzero chunk encoded frames against snapshots, confirms telemetry and timeline advance, checks audible output and metadata, renders blank no-input video, and verifies an invalid camera is refused without an output file. Logs and snapshots stay under ignored build/validation/camera-free.

Live editor playback/audio audition remains unverified because CUA reports cgWindowNotFound. Actual AVFoundation composed-frame reads and editor player readiness are tested; they do not establish onscreen native playback parity.
