# Play Store Readiness Checklist

## Build and artifact
- [x] Release App Bundle built successfully
- [x] Release APK built successfully
- [x] Bundle copied to upload folder
- [x] APK copied to upload folder
- [x] SHA-256 checksum generated

## Policy and disclosures
- [x] Privacy policy present in repository (`PRIVACY_POLICY.md`)
- [x] Data safety declaration draft present (`DATA_SAFETY.md`)
- [x] App requests network and storage-related permissions only

## Store listing
- [ ] Verify final app name and short description
- [ ] Verify full description and category
- [ ] Upload screenshots for phone and tablet
- [ ] Upload 512x512 icon and feature graphic
- [ ] Verify contact email and privacy policy URL

## Release quality
- [x] Analyzer clean
- [x] Test suite passes
- [x] Windows release build passes
- [x] Android AAB build passes
- [x] Android APK build passes

## Final pre-submit checks
- [ ] Confirm signing key and upload key ownership
- [x] Confirm app version code is higher than previous release
- [ ] Validate in internal testing track first
- [ ] Roll out staged production release
