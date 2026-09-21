# TestFlight from Windows

GitHub's macOS runner builds and signs Odomind. You do not need a Mac. This setup assumes you already registered `com.idlery.odomind` and created its App Store Connect app record under your paid developer team.

## 1. Make this workflow available

Merge the TestFlight setup pull request into the repository's default branch (currently `claude/laughing-franklin-89ryeu`). Manual workflows must exist on the default branch before GitHub displays their Run workflow button. Wait for the normal **CI** workflow to pass for the commit you will upload. This workflow intentionally refuses to upload a commit whose latest push/manual CI run is missing, running, or failed.

The upload workflow does not run on pushes or pull requests. It only accepts manual runs from the default branch. It builds the exact selected commit, checks the signing profile, overrides signing/build-number settings at build time, and uploads to App Store Connect. It does not change your project generator, create/revoke Apple certificates, or release the app to the App Store.

## 2. Create the GitHub environment

Open repository **Settings → Environments → New environment** and name it `testflight`.

Set deployment branches/tags to **Selected branches and tags**, and allow only the current default branch. Update that restriction if the default branch changes. Optional required reviewers can provide another release approval if your team uses them.

In that environment, add one **environment variable**:

| Name | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Your 10-character Team ID from Apple Developer → Account → Membership details. It is not your numeric App Store app ID or API Issuer ID. |

Add these six **environment secrets**:

| Name | Value |
| --- | --- |
| `ASC_KEY_ID` | The Key ID for a team App Store Connect API key. |
| `ASC_ISSUER_ID` | The Issuer ID on the Team Keys page. |
| `ASC_PRIVATE_KEY` | The entire downloaded `.p8` text, including BEGIN/END PRIVATE KEY lines. Do not base64-encode this one. |
| `BUILD_CERTIFICATE_BASE64` | Base64 of the distribution certificate **and private key** exported as a password-protected `.p12`. A downloaded `.cer` alone is insufficient. |
| `P12_PASSWORD` | The password protecting that `.p12`. |
| `BUILD_PROVISION_PROFILE_BASE64` | Base64 of an App Store Connect `.mobileprovision` for `com.idlery.odomind`, using that distribution certificate. |

Do not put these private files or secret values in repository files, issues, chat messages, or screenshots. Secret values cannot be read back from GitHub after saving. If reusing a credential from another app, use your securely saved original value/file; GitHub cannot reveal the old secret for you.

## 3. App Store Connect API key

Open [App Store Connect → Users and Access](https://appstoreconnect.apple.com/access/users), then **Integrations → App Store Connect API → Team Keys**. Request API access if necessary.

Generate a key named `Odomind GitHub Upload` with **Developer** access for uploading builds. This workflow manages testers in the App Store Connect UI, so it does not need an Admin key. Use a **team key**, since this workflow requires an Issuer ID.

Download the `.p8` once and store it securely. Copy the Key ID, Issuer ID, and full `.p8` text into the three `ASC_...` secrets above. A suitably permissioned existing team key can also be reused if you still have its private key.

Apple's [API-key instructions](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/) explain access and one-time downloads.

## 4. Distribution certificate without a Mac

If you already have a valid **Apple Distribution** `.p12` and its password from another app in the same Apple team, reuse them and go to step 5. A cloud-managed certificate without an exportable private key is not sufficient for this manual-signing workflow. Do not revoke another app's certificate to make room.

Otherwise, use OpenSSL locally on Windows (for example, the OpenSSL included in Git for Windows). Open **Git Bash** and check `openssl version`. Keep these files in a private folder outside all repositories:

```bash
mkdir -p ~/odomind-signing
cd ~/odomind-signing
openssl genrsa -aes256 -out distribution.key 2048
openssl req -new -sha256 -key distribution.key -out distribution.csr
```

The first command asks you to choose a private-key passphrase. The second asks for it again and then certificate-request fields; use your own name/organization and email. Leave the optional challenge password empty. Keep `distribution.key` and its passphrase: the certificate cannot sign apps without the matching key.

Open [Apple Developer → Certificates](https://developer.apple.com/account/resources/certificates/list), click **+**, choose **Apple Distribution**, and upload **only** `distribution.csr`. Download the issued certificate into your private folder as `distribution.cer`.

Back in the same Git Bash folder:

```bash
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -inkey distribution.key -in distribution.pem -out distribution.p12 -name 'Odomind Distribution'
```

Enter the private-key passphrase, then choose a nonempty export password. The export password is `P12_PASSWORD`. These commands keep passwords out of shell command history.

If macOS later reports a PKCS12 import compatibility error despite the correct password, recreate the P12 using OpenSSL 3's `-legacy` export option and replace the matching GitHub secret. Do not keep retrying unrelated certificates.

## 5. Odomind provisioning profile

In [Apple Developer → Profiles](https://developer.apple.com/account/resources/profiles/list):

1. Click **+**.
2. Under Distribution, choose **App Store Connect**.
3. Select the explicit App ID **`com.idlery.odomind`**.
4. Choose the exact Apple Distribution certificate whose private key is in your `.p12`.
5. Name the profile `Odomind App Store` and generate it.
6. Download it into the private signing folder as `Odomind.mobileprovision`.

Do not select Development or Ad Hoc. There is no device-UDID registration step for TestFlight. See [Apple's profile instructions](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/).

## 6. Copy the two files into GitHub secrets

Open **PowerShell** (not Git Bash). Adjust the paths if you saved files elsewhere. Each command places one value on your clipboard without printing it:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\odomind-signing\distribution.p12")) | Set-Clipboard
```

Paste into `BUILD_CERTIFICATE_BASE64`, then run:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\odomind-signing\Odomind.mobileprovision")) | Set-Clipboard
```

Paste into `BUILD_PROVISION_PROFILE_BASE64`. Store the `.p12` export password in `P12_PASSWORD`. Keep your encrypted originals and passwords in secure storage for renewal or recovery.

GitHub's [signing guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications) documents the certificate/profile secret approach. The workflow creates its temporary keychain password itself; you do not need a `KEYCHAIN_PASSWORD` secret.

## 7. Upload

Open **Actions → TestFlight → Run workflow**. Select the default branch. Enter `1` for the first build, or a new higher build number for subsequent uploads (the workflow accepts 1–9999). Click Run workflow.

If CI is still running or failed, wait for it to pass/fix it, then start a new TestFlight run. Do not remove that gate to hide a test failure. Re-running an upload that already reached Apple may require a new build number.

The runner needs a stable Xcode 26+ installation. If none exists on `macos-15`, update the runner image deliberately and recheck the app before release. The current workflow prints the actual selected toolchain.

The workflow checks certificate/profile compatibility, archives the Release scheme, exports an IPA, and uploads it. Its success means the upload command succeeded; Apple processing and distribution are subsequent steps. No credentials, IPA, or archive are published as workflow artifacts.

## 8. Install on your iPhone

In **App Store Connect → Odomind → TestFlight**, wait for processing and resolve any outstanding compliance questions. Create an internal testing group, add your eligible App Store Connect account and the build, then accept the invitation using the TestFlight app on your iPhone. This does not publish Odomind on the App Store.

## Validation status

This workflow requires your signing credentials for end-to-end validation. Static checks cannot establish that Apple's archive validation, certificate chain, account permissions, or upload processing will succeed. Any actual first-run failure must be resolved from that run's log. The existing normal CI remains the app's build/test gate.
