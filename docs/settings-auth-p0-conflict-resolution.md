# Settings/Auth P0 integration plan

Do not rebase the settings branch onto auth commit `567e8f9` until the auth P0
work is declared final. Resolve the overlap after that point in one integration
commit, preserving both sides of the following contracts.

## Theme.swift

- Keep the settings branch's checked encode/write/readback transaction, verified
  persisted-byte rollback, unchanged runtime state on failure, and publish only
  after a complete ordered model match.
- Use auth's composite `SecureUser.accountIdentifier` everywhere a tab owner is
  written, including the current-account fallback for tabs whose owner is `nil`.
- Resolve an existing owner value as follows: keep an exact composite identifier;
  migrate a bare server user ID only when it matches exactly one saved account;
  never choose between duplicate bare IDs on different instances. Repair a zero-
  match or ambiguous tab through the existing deterministic invalid-owner path.
- Look up and remove account-bound tabs by composite identifier. A home-tab title
  lookup must also use the composite identifier.
- Preserve full ordered change detection over tab `name`, `kind`, composite owner,
  and `listId`, plus `mainColorHex` and `colorMode`.

## MissCatSettingsLegacyAdapters.swift

- Expose composite account identifiers in account summaries, current selection,
  design-tab owners, reaction routes, switch/delete requests, and save recovery.
- Preserve auth's `Bool` result from `changeCurrentUser`; a `false` return is an
  immediate persistence failure. After `true`, retain the settings branch's exact
  composite-ID readback verification before resetting caches or relaunching UI.
- Resolve switch, delete, design, and reaction owners by composite identifier.
- Keep the server profile response comparison against `SecureUser.userId` (the raw
  server user ID); never compare `/api/i`'s `id` with the composite identifier.
- Continue storing reaction archives by canonical instance only. The alias mover
  must not include a composite account identifier, API token, or plaintext secret
  in any emoji archive key or value.

## Integration verification

Add or retain tests for duplicate raw user IDs on two instances, unique bare-ID
theme migration, ambiguous bare-ID repair, nil-owner composite fallback, ordered
tab field changes, a `false` account-switch write, exact composite switch readback,
server user-ID profile verification, and reaction archive keys that contain only
the canonical instance. Run the focused settings/auth suites before the generic
simulator build and review the final conflict diff for accidental reintroduction
of void `changeCurrentUser` calls or bare-ID persistence.
