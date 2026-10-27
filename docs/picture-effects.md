# Chroma key and colorize

Select a video/image input or display and expand its picture controls. Input settings affect all displays using that physical source. Display settings apply afterward to that widget only. Edits use existing Undo and display timeline inheritance; Reset clears the effects along with other picture adjustments.

Enable **Chroma key**, set the key with the color chooser, six-digit hex, individual 0–255 RGB components, or **Pick key color from screen…**. Color range compares normalized RGB chromaticity, brightness range compares maximum RGB component, and edge softness feathers the two thresholds. All three UI fields are percentages. A black key uses brightness alone. Keying multiplies existing alpha and runs before that layer's crop, brightness/contrast/saturation/hue and sharpness. Sample an unadjusted source when possible: display keying sees the source's already-adjusted picture.

Enable **Colorize** for a brightness-preserving tint. **Full spectrum** maps brightness around the hue wheel; Amount blends with the original RGB. It preserves keyed transparency. The algorithm is an independent implementation; neither native threshold equivalence nor spill suppression is claimed.

Video, images and portable source-adjusted template artwork use the same encoded RGB processing. Video's host decoder and source color metadata still affect incoming RGB. One generated ProRes 4444 fixture produced a different AVFoundation RGB decode than FFmpeg, so effect acceptance uses H.264 camera-style media; this is not proof of universal codec color equivalence.

## Persistence and compatibility

`.orrp` and native template/style JSON retain settings. Source effects can be baked into portable image artwork. Invalid colors or out-of-range values stop snapshot/export with an error. Existing projects without effects retain their defaults.

RaceRender's key/spectrum record flags and exact algorithm have not been verified. Unchanged opaque imported records remain retained with the existing additional-picture-operation warning; they are not interpreted as supported effects. Rebuilt `.rrp`/`.rrt`/`.rro` export refuses newly edited key/colorize settings rather than dropping them. Use `.orrp` for these edits. A native project sample has been requested; none is available at this checkpoint.

## Validation

The guide's InputFileEdit picture section was read from the supplied local mirror. Native/editor live checks and the system screen sampler remain unverified because CUA returns `cgWindowNotFound`; no live/native pixel-parity claim is made.

Six core tests and two editor tests cover raw-color ordering, independent tolerances/soft alpha, tint/spectrum/amount, original transparency, encoded RGB consistency between image widgets and portable artwork, validation/persistence/native refusal, field clamps, timing preservation, timeline reset and Undo. The complete suite passes 313 tests locally.

`python3 scripts/validate-picture-effects.py` generates only original disposable media. It compares key/tint/compositing and timed key removal to independent solid-color references, source/display equivalence, marked encoded frames, and grayscale spectrum imagery to Python's HSV conversion. Existing image-control and source-tool media acceptance checks are also run. Logs and images stay under ignored `build/validation/picture-effects`.
