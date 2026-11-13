#!/bin/bash
set -euo pipefail
simulator_id=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
for runtime, devices in sorted(json.load(sys.stdin)["devices"].items(), reverse=True):
    if "iOS" not in runtime:
        continue
    phones = [d for d in devices if d.get("isAvailable") and d["name"].startswith("iPhone")]
    if phones:
        preferred = next((d for d in phones if d["name"] == "iPhone 17 Pro"), phones[0])
        print(preferred["udid"])
        break
')
test -n "$simulator_id"
collect_results() {
    mkdir -p "$GITHUB_WORKSPACE/dist"
    if [ -d "$RUNNER_TEMP/QiyeLongPhotoHitArea.xcresult" ]; then
        cp -R "$RUNNER_TEMP/QiyeLongPhotoHitArea.xcresult" "$GITHUB_WORKSPACE/dist/InteractionTests.xcresult"
        xcrun xcresulttool export attachments --path "$RUNNER_TEMP/QiyeLongPhotoHitArea.xcresult" --output-path "$GITHUB_WORKSPACE/dist/interaction-attachments" || true
    fi
}
recording_pid=""
finish() {
    if [ -n "$recording_pid" ]; then
        kill -INT "$recording_pid" 2>/dev/null || true
        wait "$recording_pid" || true
    fi
    collect_results
}
trap finish EXIT
mkdir -p "$GITHUB_WORKSPACE/dist"
xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl io "$simulator_id" recordVideo --codec h264 "$GITHUB_WORKSPACE/dist/interaction-preview.mov" &
recording_pid=$!
rm -rf "$RUNNER_TEMP/QiyeLongPhotoHitArea.xcresult"
xcodebuild test \
    -project Qiye.xcodeproj -scheme Qiye -configuration Debug \
    -destination "platform=iOS Simulator,id=${simulator_id}" \
    -derivedDataPath "$RUNNER_TEMP/SimulatorBuild" \
    -parallel-testing-enabled NO \
    -only-testing:QiyeUITests \
    -resultBundlePath "$RUNNER_TEMP/QiyeLongPhotoHitArea.xcresult" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES

# Result bundle and screenshots are exported by the EXIT trap.
