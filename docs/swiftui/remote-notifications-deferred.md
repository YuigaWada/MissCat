# Remote notifications are deferred

Remote push transport and the in-app push banner are intentionally out of scope
for this revision. The app ships no dormant implementation: there is no
`UIApplicationDelegateAdaptor`, application delegate, APNs registration,
Firebase/FCM dependency, messaging delegate, push mailbox, push resolver, or
push-banner state.

This does not remove the ordinary Notifications feature. Surface 33 continues
to fetch `i/notifications`, consume account-scoped realtime notification events,
render the notification list, and navigate from those list items.

Surface 34 is recorded as `runtime_owner=none` and
`migration_state=deferred`. It is excluded from the 698-case visual matrix, so
neither the migration ledger nor screenshot gate implies that push delivery is
implemented or accepted.

A future remote-notification project must start with a reviewed architecture for
direct APNs or another current transport. It must cover permission UX, token
rotation, account scoping, foreground/background delivery, deep links, unit and
E2E tests, privacy, and visual evidence. Removed legacy Firebase and push-ingress
code must not be revived as hidden scaffolding.
