# iOS IPA Packaging

This project includes a GitHub Actions workflow for producing an iOS IPA artifact:

- Workflow: `.github/workflows/build-ios-ipa.yml`
- Script: `scripts/package-ios-ipa.sh`

The workflow can be run manually from GitHub Actions, and it also runs on tags matching `v*`.

## Quick Choice

If you only need an IPA file as a CI artifact and do not need to install it on a device, you can run the workflow without configuring signing secrets. It will build an unsigned IPA:

```text
VVTerm-unsigned.ipa
```

Unsigned IPAs are useful for archiving build output or for later re-signing. They cannot be installed on a real device, uploaded to TestFlight, or submitted to the App Store.

## Export Method

The workflow input `export_method` controls how Xcode exports a signed archive.

Use these values as a rule of thumb:

- `development`: best for installing on your own development devices.
- `ad-hoc`: best for distributing to registered test devices.
- `app-store-connect`: best for TestFlight or App Store upload-ready signing.
- `enterprise`: only for Apple Developer Enterprise Program accounts.

If no signing credentials are configured, the workflow falls back to an unsigned IPA and `export_method` does not materially affect the output.

## Recommended: Automatic Signing With App Store Connect API Key

For CI signing without manually uploading provisioning profiles, configure these three GitHub repository secrets:

```text
APP_STORE_CONNECT_API_KEY_BASE64
APP_STORE_CONNECT_API_KEY_ID
APP_STORE_CONNECT_API_ISSUER_ID
```

`APP_STORE_CONNECT_API_KEY_BASE64` should be the base64-encoded contents of the `.p8` key file from App Store Connect.

Example local encoding command:

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

With these secrets present, the workflow passes `-allowProvisioningUpdates` plus the App Store Connect API key parameters to `xcodebuild`, allowing Xcode to create or download provisioning profiles for:

```text
app.agatha.VivyTerm
app.agatha.VivyTerm.liveactivity
```

## Manual Signing Secrets

If you prefer manual signing, configure these secrets instead:

```text
IOS_SIGNING_CERTIFICATE_BASE64
IOS_SIGNING_CERTIFICATE_PASSWORD
IOS_SIGNING_KEYCHAIN_PASSWORD
IOS_APP_PROVISIONING_PROFILE_BASE64
IOS_LIVE_ACTIVITY_PROVISIONING_PROFILE_BASE64
IOS_APP_PROVISIONING_PROFILE_NAME
IOS_LIVE_ACTIVITY_PROVISIONING_PROFILE_NAME
APPLE_TEAM_ID
```

The certificate should be a base64-encoded `.p12`. Provisioning profiles should be base64-encoded `.mobileprovision` files.

`IOS_LIVE_ACTIVITY_PROVISIONING_PROFILE_BASE64` and `IOS_LIVE_ACTIVITY_PROVISIONING_PROFILE_NAME` are required when exporting a signed build that includes the Live Activity extension.

## Unsigned IPA Fallback

When none of the signing credentials are available, the workflow automatically sets:

```text
UNSIGNED_IPA=1
```

The script then builds with code signing disabled and packages the built app into a standard IPA layout:

```text
Payload/VVTerm.app
```

This avoids CI failure when the goal is only to keep an IPA-shaped build artifact.

## Local Script Usage

Signed archive and export:

```bash
scripts/package-ios-ipa.sh \
  .build/archives/VVTerm-iOS.xcarchive \
  .build/output \
  .build/ExportOptions.plist \
  VVTerm.xcodeproj \
  VVTerm
```

Unsigned IPA:

```bash
UNSIGNED_IPA=1 scripts/package-ios-ipa.sh \
  .build/archives/VVTerm-iOS.xcarchive \
  .build/output \
  "" \
  VVTerm.xcodeproj \
  VVTerm
```

