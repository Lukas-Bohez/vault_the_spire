# VaultTheSpire — Google Play Store Readiness Checklist

## 1. Google Play Developer Account
- [ ] Register at play.google.com/console ($25 one-time fee)
- [ ] Verify identity and payment details
- [ ] Accept Google Play Developer Distribution Agreement

## 2. App Content & Policy Compliance
- [ ] Write and publish a Privacy Policy (required — must be hosted at a public URL)
- [ ] Write Terms of Service clearly stating prohibited uses, including:
  - [ ] No illegal content of any kind
  - [ ] No CSAM (explicitly named — zero tolerance)
  - [ ] No copyright infringement
  - [ ] No harassment or hate speech
- [ ] Complete the Content Rating Questionnaire in Play Console (IARC rating)
- [ ] Ensure app does not violate Google Play's User Generated Content policy
- [ ] Add in-app reporting mechanism for abusive content/users
- [ ] Document how abuse reports are handled and actioned

## 3. Store Listing
- [ ] App name: VaultTheSpire
- [ ] Short description (80 chars max)
- [ ] Full description (4000 chars max) — highlight privacy, encryption, P2P
- [ ] Feature graphic (1024x500px)
- [ ] App icon (512x512px, PNG)
- [ ] At least 2 screenshots per device type (phone required, tablet optional)
- [ ] Privacy Policy URL added to store listing

## 4. App Bundle / APK
- [ ] Build release AAB: `flutter build appbundle --release`
- [ ] Sign the AAB with a release keystore (keep keystore backed up securely!)
- [ ] Enable Google Play App Signing in Console
- [ ] Set applicationId in build.gradle (e.g. com.quizthespire.vaultthespire)
- [ ] Set versionCode and versionName correctly
- [ ] Test release build on a physical device before upload

## 5. Permissions Audit
- [ ] Review all permissions declared in AndroidManifest.xml
- [ ] Remove any permissions not actively used
- [ ] Add runtime permission requests with clear explanations to the user
- [ ] Ensure INTERNET permission is declared
- [ ] Justify any sensitive permissions if prompted during review

## 6. Testing
- [ ] Set up Internal Testing track in Play Console
- [ ] Upload AAB to Internal Testing and test on multiple devices
- [ ] Test on Android 8, 10, 12, and 14 (cover a wide range)
- [ ] Fix any crashes reported in Android Vitals
- [ ] Set up Closed Testing (beta) track before full release

## 7. Data Safety Form (required since 2022)
- [ ] Complete Data Safety section in Play Console
- [ ] Declare what data is collected (if any)
- [ ] Declare whether data is shared with third parties
- [ ] Declare encryption practices (highlight SQLCipher, E2E encryption)
- [ ] Declare whether users can request data deletion

## 8. Launch
- [ ] Submit for review (typically 1-7 days for new apps)
- [ ] Monitor for policy violation emails from Google
- [ ] Set up staged rollout (e.g. 10% → 50% → 100%) for first release
- [ ] Respond to early user reviews promptly
- [ ] Monitor Android Vitals for crashes and ANRs post-launch

## 9. In-app feature roadmap (next sprints)
- [x] Auto-open channel chat pane when selecting a channel on the server sidebar
- [x] Persist server list + channels in local encrypted DB (SQLCipher)
- [x] Persist chat messages in local encrypted DB (SQLCipher)
- [x] Add proper invite join flow with 1-click import + validation error UX
- [x] Add server/channel create/delete and rename UI actions
- [ ] Add ephemeral private DMs + @ mentions
- [ ] Add dark theme and high contrast test coverage
- [ ] Add unit tests for server/chat service and widget integration

## 10. Release 2.0.0 readiness
- [ ] Bump package version to 2.0.0 in pubspec.yaml
- [ ] Update CHANGELOG.md with v2.0.0 features and migration notes
- [ ] End-to-end test for server/chat persistence + SQLCipher database migration
- [ ] Update docs for desktop + Android permissions + SQLCipher key management
- [ ] Verify all platform builds (Android, iOS, Linux, macOS, Windows, Web) pass
- [ ] Final security audit for cached user data and permissions
- [ ] Add a non-blocking in-app update UX or version check notice
