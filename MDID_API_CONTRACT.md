# mSign MDID API contract

The mSign client now expects the existing `account.php` endpoint to support one additional authenticated action:

## `POST account.php`

Request:

```json
{
  "action": "admin_set_mdid",
  "token": "<authenticated-session-token>",
  "mdid": "MS-ABCDEF-23"
}
```

Requirements:

1. Authenticate `token` as a live mSign account session.
2. Require the authenticated account to have the `admin` role server-side.
3. Validate the requested MDID as `MS-[A-Z0-9]{6}-[A-Z0-9]{2}`.
4. Reject a collision with another account/active device unless an explicit admin migration policy permits it.
5. Update the account's MDID and the MDID-based role/staff mapping atomically.
6. Write an audit record containing the admin account, old MDID, new MDID, and timestamp. Do not log passwords or session tokens.
7. Return the canonical MDID only after the transaction commits.

Success:

```json
{
  "ok": true,
  "mdid": "MS-ABCDEF-23"
}
```

Error examples should use an appropriate HTTP status and a JSON object such as:

```json
{
  "error": "MDID already belongs to another account"
}
```

## Why the client changes locally only after success

`mSign` first asks the server to perform the administrative migration. If the server rejects it, the local MDID is untouched. After a successful response, mSign writes the canonical MDID to Keychain and immediately re-checks the account profile and `roles/check.php` using the new MDID.

## First-launch behavior

New installations generate their MDID locally with `SecRandomCopyBytes`; the MDID is not derived from hardware identifiers. The ID is persisted in Keychain so the same installation keeps its identity until an authorized server-side reassignment occurs.
