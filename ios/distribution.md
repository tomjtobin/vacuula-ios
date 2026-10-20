# Distribution troubleshooting

## “Copy failed” while creating an IPA

A confirmed local packaging failure occurs when Apple's `/usr/bin/rsync` starts a subprocess that resolves to Homebrew's incompatible `rsync`. Distribution logs show:

```text
rsync: on remote machine: --extended-attributes: unknown option
Step IDEDistributionCreateIPAStep failed: Copy failed
```

The app record and signing can succeed before this failure. It does not indicate a malformed project or an App Store binary rejection.

Save work and completely quit Xcode. From the repository root, launch it with Apple tools first in its process PATH:

```sh
./tools/open-xcode-for-distribution.sh /Applications/Xcode.app
```

Pass the actual Xcode application path if installed elsewhere. Then open Organizer and retry distributing the existing archive. A new archive is needed only to include newer app changes. This launcher changes the environment of the newly launched Xcode process; it does not uninstall/unlink Homebrew tools or modify shell/launchd settings. Normal launches may restore the original PATH ordering, so use this launcher for distribution if needed.

For command-line archive export, similarly put `/usr/bin:/bin:/usr/sbin:/sbin` before Homebrew in PATH for the `xcodebuild -exportArchive` invocation.

Validation on the affected Mac reproduced the failure with a temporary local copy using the exact rsync flags from Xcode; the identical copy passed with Apple tools first. A successful copy is not proof that a subsequent upload or App Store validation has completed.

## App record already exists

If record creation rejects a duplicate SKU, bundle ID or name, check the existing record in App Store Connect. Keep the existing `com.vacuula.ios` identifier and retry distribution against that record. Do not create replacement identifiers to work around an existing app record.
