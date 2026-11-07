# Long portrait photo hit-area regression

`LongPhotoHitAreaTests.testLongPortraitDraftDoesNotInterceptWebsiteSegmentTap` launches the real `top.mmddskq.qiye` app, opens a draft as a positive control, closes it, and taps the physical center of the 网站 source segment. It asserts that 网站 becomes selected, the draft disappears, and photo details stay closed. It switches back to confirm that the draft is retained. Screenshots of the positive control, the grid before switching, the website source after switching, and the final state are retained in the `.xcresult`; a failure also retains the accessibility hierarchy.

## Debug fixture contract

The app must implement this contract before running the test. The test does not skip if fixture support is missing.

- Launch arguments: `--tab photos --uitest-long-photo`. The test also forces Simplified Chinese and portrait orientation.
- In a `#if DEBUG` path, `--uitest-long-photo` creates exactly one local draft, independent of existing user drafts, and uses an isolated temporary directory. Do not remove or overwrite real drafts. Repeated launches must produce the same single fixture.
- Use a stable UUID (for example `11111111-1111-1111-1111-111111111111`) and an actual tall portrait image for both full image and thumbnail, for example 360 × 3600 pixels. Preserve the tall aspect ratio through the normal thumbnail loader; do not replace it with a square placeholder. A deterministic date/title drawn into the fixture image makes screenshots easier to review. The test needs no access to the system photo library.
- Keep the normal photo grid, image loader, button actions, detail presentation, and source picker in use. The fixture may initially select 待发布; the test also explicitly selects it when needed.
- Disable photo refresh networking for the fixture, or keep its results from changing the local fixture or layout during the test. Existing bundled website photos are sufficient for the website source.
- On the segmented `Picker` after `.pickerStyle(.segmented)`, set `.accessibilityIdentifier("photo-source-picker")`.
- Keep the source option labels 网站 and 待发布 (the latter may include a count). The test locates segment buttons by their labels inside the identified picker, since identifiers on SwiftUI `Text` options may not propagate.
- On the actual local draft `Button`, set `.accessibilityIdentifier("photo-draft")` or `.accessibilityIdentifier("photo-draft-\(draft.id.uuidString)")`. Exactly one matching draft button must be visible.
- On the root of the presented `PhotoDetailScreen`, set `.accessibilityIdentifier("photo-detail-screen")` so it exists in the accessibility tree while details are presented. Keep its existing 关闭 toolbar button accessible by that label. Do not use `.accessibilityElement(children: .ignore)` to hide its descendants.

## Run on a Mac or GitHub macOS runner

From the repository root, choose an available iPhone simulator running iOS 17 or later:

```sh
xcrun simctl list devices available
```

Set `SIMULATOR_ID` to that simulator's UDID, then run:

```sh
xcodebuild test \
  -project apps/qiye/Qiye.xcodeproj \
  -scheme Qiye \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
  -parallel-testing-enabled NO \
  -only-testing:QiyeUITests/LongPhotoHitAreaTests/testLongPortraitDraftDoesNotInterceptWebsiteSegmentTap \
  -resultBundlePath /tmp/QiyeLongPhotoHitArea.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Use a fresh result bundle path for each run. The test target is `QiyeUITests`, bundle identifier `top.mmddskq.qiye.uitests`, deployment target iOS 17.0, with `TEST_TARGET_NAME = Qiye`. Its source is explicitly listed in its Sources phase under `UITests`, outside the app's synchronized `Sources` and `Resources` groups. The shared Qiye scheme includes it only for testing, not archiving.

To validate the regression itself, run the same test once with the old unconstrained long-image hit area and once with the clipping/content-shape fix. The old version must fail at the source-selection/detail assertions and the fixed version must pass. Simulator execution and this before/after check require Xcode and are not performed by the Linux-only project setup.
