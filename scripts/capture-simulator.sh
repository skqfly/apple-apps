#!/bin/bash
set -euo pipefail
app_dir="$1"
output_dir="$2"
mkdir -p "$output_dir"
simulator_id=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
all_devices=json.load(sys.stdin)["devices"]
for runtime in sorted(all_devices,reverse=True):
    if "iOS" not in runtime: continue
    phones=[d for d in all_devices[runtime] if d.get("isAvailable") and d["name"].startswith("iPhone")]
    if phones:
        preferred=next((d for d in phones if d["name"]=="iPhone 17 Pro"),phones[0])
        print(preferred["udid"]); break
')
test -n "$simulator_id"
xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl status_bar "$simulator_id" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$simulator_id" "$app_dir"
for mode in light dark; do
    xcrun simctl ui "$simulator_id" appearance "$mode"
    for tab in home blog talks photos; do
        xcrun simctl terminate "$simulator_id" top.mmddskq.qiye || true
        xcrun simctl launch "$simulator_id" top.mmddskq.qiye --tab "$tab"
        sleep 8
        xcrun simctl io "$simulator_id" screenshot "$output_dir/$tab-$mode.png"
    done
done
xcrun simctl terminate "$simulator_id" top.mmddskq.qiye || true
xcrun simctl launch "$simulator_id" top.mmddskq.qiye --tab blog --article
sleep 6
xcrun simctl io "$simulator_id" screenshot "$output_dir/article-dark.png"
xcrun simctl terminate "$simulator_id" top.mmddskq.qiye || true
xcrun simctl launch "$simulator_id" top.mmddskq.qiye --account
sleep 5
xcrun simctl io "$simulator_id" screenshot "$output_dir/account-dark.png"
xcrun simctl terminate "$simulator_id" top.mmddskq.qiye || true
xcrun simctl launch "$simulator_id" top.mmddskq.qiye --account --login
sleep 4
xcrun simctl io "$simulator_id" screenshot "$output_dir/login-dark.png"
xcrun simctl terminate "$simulator_id" top.mmddskq.qiye || true
xcrun simctl launch "$simulator_id" top.mmddskq.qiye --account --login --device-login
sleep 12
xcrun simctl io "$simulator_id" screenshot "$output_dir/device-login-dark.png"
xcrun simctl terminate "$simulator_id" top.mmddskq.qiye || true
