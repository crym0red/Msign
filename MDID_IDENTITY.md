# MDID identity model

## First launch

A new mSign installation receives a cryptographically-random `MS-XXXXXX-XX` MDID on first use. The ID is stored in Keychain and is not derived from hardware, screen size, model, or other device fingerprints. Existing valid MDIDs are preserved for compatibility.

## Admin reassignment

Admins can change the MDID for their authenticated account from the Account screen. mSign calls `POST account.php` with:

```json
{
  "action": "admin_set_mdid",
  "token": "<session token>",
  "mdid": "MS-XXXXXX-XX"
}
```

The server must authenticate the session as an administrator and atomically update the account's MDID plus any MDID-based role/staff mapping. It should reject collisions with another account/device unless an explicit administrative migration policy permits the change.

The response should contain the canonical MDID:

```json
{ "ok": true, "mdid": "MS-XXXXXX-XX" }
```

mSign only writes the new MDID locally after receiving a valid server response, then refreshes the account profile and server-side role gate using the new MDID.

## Important

The MDID is an identifier, not a secret. Authorization must remain server-side. Do not treat possession of an MDID as proof of account ownership.
