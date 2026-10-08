# Apple on-device vision probe

Isolated iPhone app that runs the frozen [photo screening set](../photo_screening/README.md) through `SystemLanguageModel.default` with an image `Attachment` (iOS 27). Never references Private Cloud Compute; no network code; no Sekret data. Results: [v1 did not advance](RESULTS-2026-10-08.md); [narrowed v2 did not advance](RESULTS-V2-2026-10-08.md).

Build with Xcode 27 without changing the system default, then install and run with the phone connected and unlocked:

```sh
export DEVELOPER_DIR="/Applications/<Xcode 27>.app/Contents/Developer"
xcodebuild -project experiments/apple_vision/ios/SekretVisionEval.xcodeproj -scheme SekretVisionEval \
  -configuration Release -sdk iphoneos -derivedDataPath experiments/apple_vision/ios/build \
  DEVELOPMENT_TEAM=<team> -allowProvisioningUpdates build
python3 -I experiments/apple_vision/run-phone.py --device <CoreDevice UDID> [--skip-install]
```

The app reuses the `com.ricejy.sekret.localeval` app ID because of the free-profile app limit. A freshly installed free-profile build must be verified online once (open it on the phone); after that `--skip-install` runs it in Airplane Mode. Launch with `--diagnostic` for a stage-by-stage check on the development turtle image. On iOS 27.0, `tokenCount(for:)` fails with `ModelManagerError 1001` whenever the prompt contains an image; generation itself works.
