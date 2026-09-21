# Odomind Pro — App Store Connect setup

What the app expects, what has been done, and what only the account holder can
do. Written so the remaining steps can be completed without re-deriving any of
it.

## Status

| Step | State |
| --- | --- |
| Product identifiers chosen and compiled into the app | Done — `ProProduct` in `Odomind/Features/Pro/Entitlements.swift` |
| StoreKit 2 purchase, restore, renewal and revocation handling | Done |
| Local StoreKit configuration for development | Done — `Odomind/Resources/Odomind.storekit`, referenced by the shared scheme |
| Paywall, entitlement gates, lapse behaviour | Done |
| Subscription group created in App Store Connect | **Owner action — blocked** |
| Two auto-renewable subscriptions created and priced | **Owner action — blocked** |
| Paid Applications Agreement accepted, banking and tax complete | **Owner action — blocked** |
| Sandbox tester account created | **Owner action — blocked** |
| Real sandbox and TestFlight purchase verified | **Blocked on the above** |

The blocked rows need an App Store Connect session with the account holder's
credentials and, in the case of the agreements, a legal acceptance. Nothing in
this repository can or should do either, and an API key with App Store Connect
access is deliberately not used to accept an agreement on someone's behalf.

**Until those rows are done, the paywall will not show a price.** It is written
for exactly that: `Product.products(for:)` returns nothing, and the screen says
subscription details are unavailable and offers to retry. It does not show a
placeholder price, because a price the App Store did not supply is a fiction.

## Exactly what to create

**Subscription group**

| Field | Value |
| --- | --- |
| Reference name | `Odomind Pro` |
| Group must contain both products | Yes — same group, same service level |

Both durations sit in one group at the same level on purpose: switching between
monthly and yearly is then a plan change Apple handles, not a second purchase.

**Subscriptions**

| Field | Monthly | Yearly |
| --- | --- | --- |
| Product ID | `com.idlery.odomind.pro.monthly` | `com.idlery.odomind.pro.yearly` |
| Reference name | Odomind Pro Monthly | Odomind Pro Yearly |
| Duration | 1 month | 1 year |
| Proposed US price | $2.99 | $19.99 |
| Display name | Odomind Pro | Odomind Pro |

The product IDs must match the strings above exactly. They are compiled into
the app, and a mismatch shows up as "subscription details unavailable" with no
further explanation.

**Prices are a hypothesis, not a finding.** $2.99 and $19.99 are a starting
point to validate, chosen against a market where CARFAX Car Care advertises
free reminders and history and Simply Auto sells a lower-priced annual plan.
That is a reason to keep the core free and useful; it is not evidence that this
price is right. Every price the owner actually sees comes from StoreKit, so
changing it in App Store Connect changes the app with no new build.

**Storefronts.** Set the US price and let Apple's automatic price matrix fill
the rest unless there is a reason not to. The app never hardcodes a currency.

**Description** (both products, 45-character display name limit, 4000-character
description):

> Odomind Pro adds automatic maintenance updates, on-device receipt scanning,
> spending trends and service reports, and unlimited vehicles. Everything you
> have already recorded stays on your device and stays yours, subscription or
> not.

## Review notes

Paste this into App Store Connect's review notes so a reviewer can reach the
paid screens:

> Odomind Pro is reachable without an account. Open the app, tap **Calendar**,
> then the gear in the top right, then **Odomind Pro**. The same screen appears
> from **Garage → Add a vehicle** once two vehicles exist.
>
> The app requires no sign-in. All records are stored locally. Restoring
> purchases is on the Pro screen and on the paywall.

A screenshot of the paywall is required. Capture it from the Screenshots
workflow (`paywall-light.png` / `paywall-dark.png`) rather than by hand, so it
matches what ships.

## What is behind the paywall, and what is not

Implemented and gated:

| Feature | Where |
| --- | --- |
| Automatic maintenance-catalog updates | Settings → Maintenance updates |
| On-device receipt text extraction into a reviewed draft | Log service → Scan a receipt |
| Spending trends and the service dossier | Garage → a vehicle → Spending |
| More than the free vehicle allowance | Garage → Add a vehicle |

Free, and staying free: vehicle lookup, starter plans, custom jobs,
specifications, service records, receipt attachments, reminders, the in-app
calendar, individual and batch Apple Calendar export, parts searches and nearby
retailers, appearance, CSV and PDF export, and full local backup and restore.

Not built, and therefore **not advertised anywhere in the app**: managed
two-way calendar sync, cloud sync, family sharing of a garage, automatic
mileage tracking, and live nationwide price comparison. See
`docs/BUILD-2-NOTES.md` for why managed calendar sync was deferred.

## The free allowance, and existing users

New installs get two vehicles. Anyone upgrading from Build 1 gets whatever they
already had: on the first Build 2 launch, `recordGrandfatheredAllowanceIfNeeded`
records the garage size once and latches it, so a later deletion cannot shrink
it. That is covered by `testTheAllowanceIsRecordedOnceAndNeverShrinks`.

Nothing is ever deleted or locked because a limit was introduced or a
subscription lapsed. On lapse: existing records stay editable, reminders keep
firing, Pro-generated reports and drafts stay readable, and only *new* premium
actions and adding beyond the allowance stop. `ProPolicy.lapsePromise` is the
one place that promise is worded, and both the paywall and Settings quote it.

## Testing

**Local, no account needed.** The scheme points at
`Odomind/Resources/Odomind.storekit`, so running from Xcode exercises purchase,
cancellation, restore and renewal against StoreKit's local test environment.
Xcode's **Debug → StoreKit → Manage Transactions** window can expire, refund
and revoke a transaction to exercise those paths.

This proves the *app's* handling. It proves nothing about App Store Connect —
a local configuration file will happily sell a product that does not exist in
the real store. The sandbox run below is the one that checks that.

**Sandbox.** Create a sandbox tester in **Users and Access → Sandbox**, sign
into it on a device under **Settings → Developer → Sandbox Apple Account**, then
run a TestFlight build and buy.

**TestFlight purchases are test transactions.** Nobody is charged, and
subscription periods are accelerated: a one-month subscription renews every five
minutes and auto-cancels after six renewals; a one-year subscription renews
every hour. Expect a subscription to lapse during a long test session — that is
the accelerated clock, not a bug, and it is a good chance to check that the
lapse behaviour above actually holds. Apple documents the current rates at
<https://developer.apple.com/help/app-store-connect/test-in-app-purchases/test-in-app-purchases>;
recheck them, because they have changed before.

## Release

Production submission and release are a separate decision from this beta. This
milestone ships to TestFlight only.
