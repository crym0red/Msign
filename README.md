# CLI Compatibility Harness

This package provides a repository-local compatibility test.

It deliberately does **not** replace macOS's `/System/Library/CoreServices/SystemVersion.plist`,
patch `buddy3`, redirect its filesystem calls, or alter FairPlay/DRM behavior.

The root `SystemVersion.plist` is consumed only by `tools/version_compat_shim.py`.

Supported test profiles in the shim:
- 15.4 -> iOS-15.4
- 16.2 -> iOS-16.2
- 26.0.1 -> iOS-26.0.1

You can also provide `requested_version` when manually dispatching the workflow.

## MDID identity

New installations mint a cryptographically-random `MS-XXXXXX-XX` MDID on first use. The ID is stored in Keychain and is not derived from hardware or display fingerprints.

Administrators can reassign the MDID of their authenticated admin account from Settings → Account. The app calls `account.php` with `action=admin_set_mdid`; the server must atomically update the account MDID and its MDID-based role mapping before returning the canonical MDID. mSign only changes its local Keychain value after that server response.

See `MDID_IDENTITY.md` for the API contract.
