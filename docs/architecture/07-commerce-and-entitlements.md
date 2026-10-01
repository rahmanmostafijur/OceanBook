# 07 — Commerce and Entitlements

Covers deliverable **H** (subscription architecture), payment security and the entitlement model.

---

## 1. Principles

1. **Entitlements are derived, never asserted.** No client call, and no field on a subscription, directly grants access. Access comes only from `entitlements` rows, which are (re)computed from verified provider state, purchases, promotions or audited admin grants.
2. **The provider is the source of truth for billing state.** We mirror it, verify it, and reconcile it. We never compute renewals ourselves for store subscriptions.
3. **Payment logic is decoupled from the subscription model** through a provider abstraction. Adding bKash/SSLCommerz or a web checkout means adding a provider, not changing tables.
4. **Everything is idempotent.** Retries, duplicate webhooks and out-of-order events converge to the same state.

## 2. Model recap

```text
entitlement_definitions  (books.premium, qbank.premium, quizzes.premium, downloads.offline, analytics.advanced)
        ▲
plan_entitlements ── subscription_plans ── products ── store_products (per provider)
                                              │
users ── subscriptions ── subscription_events          payments
  │
  └── entitlements (key or resource; source_type + source_id; window)
```

Example plans (data, not code):

| Plan key | Entitlements | Limits |
|----------|--------------|--------|
| `free` | — | Free and registered content only |
| `basic_monthly` | `books.premium` | read online only; no downloads |
| `premium_monthly` / `premium_annual` | `books.premium`, `qbank.premium`, `quizzes.premium`, `downloads.offline`, `analytics.advanced` | `max_devices: 3`, `max_active_downloads: 20`, `offline_days: 30` |
| `student_monthly` | as premium | `max_devices: 2`; eligibility rule `requires_student_verification` (verification flow is a later decision) |

Changing what "Premium" includes is a row edit in `plan_entitlements`, followed by a recompute job for affected users.

## 3. Provider abstraction

```python
class PaymentProvider(Protocol):
    key: ProviderKey                                   # 'google_play' | 'app_store' | 'sslcommerz' | 'bkash'

    async def verify_purchase(self, user: User, claim: PurchaseClaim) -> VerifiedPurchase: ...
    async def fetch_subscription(self, provider_subscription_id: str) -> ProviderSubscriptionState: ...
    async def acknowledge(self, verified: VerifiedPurchase) -> None: ...      # Play requires acknowledgement within 3 days
    async def parse_notification(self, request: RawWebhook) -> ProviderNotification: ...  # verifies signature
    def normalise(self, state: ProviderSubscriptionState) -> NormalisedSubscription: ...
```

Implementations: `GooglePlayProvider` (Play Developer API, `purchases.subscriptionsv2`, `purchases.products`), `AppStoreProvider` (App Store Server API, StoreKit 2 JWS transactions, Server Notifications V2; Apple's official server library for signature verification), later `SslCommerzProvider` / `BkashProvider` for web checkout.

Everything downstream of `normalise()` is provider-agnostic: `SubscriptionService.apply(NormalisedSubscription)` updates `subscriptions`, appends `subscription_events`, records `payments`, then calls `EntitlementService.recompute(user_id, source)`.

## 4. Status model

| Normalised status | Access | Google Play (subscriptionsv2 `subscriptionState`) | App Store |
|-------------------|--------|---------------------------------------------------|-----------|
| `pending_verification` | none yet (or a short provisional grant, see §6) | `PENDING` | — |
| `active` | yes | `ACTIVE` | active, auto-renew on |
| `canceled` | **yes until period end** | `CANCELED` (renewal off, not expired) | auto-renew off, not expired |
| `in_grace` | yes until `grace_until` | `IN_GRACE_PERIOD` | in billing grace period |
| `on_hold` | no | `ON_HOLD` | billing retry (no grace) |
| `paused` | no | `PAUSED` | — |
| `expired` | no | `EXPIRED` | expired |
| `revoked` | no, immediately | voided purchase / revoked | `REVOKE` / refund |

The mapping is checked against current provider docs at Phase 4 start, because providers add states.

## 5. Purchase flow (Android example)

```mermaid
sequenceDiagram
  participant App
  participant API
  participant Play as Google Play
  participant DB

  App->>API: GET /plans (store product ids) + obfuscated account id for this user
  App->>Play: launchBillingFlow(product, base plan, obfuscatedAccountId)
  Play-->>App: purchase (purchaseToken)
  App->>API: POST /purchases/google-play/verify {purchase_token} (Idempotency-Key)
  API->>Play: purchases.subscriptionsv2.get(token)
  Play-->>API: state, line items, expiry, externalAccountIdentifiers
  API->>API: check package, product ∈ store_products, account binding matches caller
  API->>DB: upsert subscription, event, payment; recompute entitlements (one transaction + outbox)
  API->>Play: acknowledge (if not acknowledged)
  API-->>App: entitlements + subscription summary
  Note over Play,API: Later: RTDN via Pub/Sub → /webhooks/google-play → re-fetch → apply
```

- `linkedPurchaseToken` handling: upgrades, downgrades and resubscribes produce new tokens linked to old ones. We update `provider_subscription_id` to the latest token and keep the chain in events, so one logical subscription doesn't become two.
- If verification fails transiently, the API returns `202` with `status: pending_verification`. The client shows "Confirming your purchase…" and the reconciliation job retries. The client never unlocks content on its own.

iOS follows the same shape: StoreKit 2 transaction JWS → `/purchases/app-store/verify` → server verifies and/or calls the App Store Server API (`Get Transaction Info` / `Get All Subscription Statuses`), with `appAccountToken` = our per-user UUID.

## 6. Entitlement derivation

> **Revised 2026-10-01:** Every source (including subscriptions) emits `entitlement_events`, which are projected into `entitlements` (§8). Store integrations move to Phase 5. See [12-phase0-revisions](12-phase0-revisions.md).

```text
recompute(user_id):
  desired = set()
  for s in subscriptions(user) where status in (active, canceled, in_grace):
      end = max(current_period_end, grace_until)
      for k in plan_entitlements(s.plan): desired += (key=k, source=(subscription, s.id), [s.current_period_start, end], limits)
  for p in payments(user) where status = succeeded and product.type = one_time:
      for g in product.grants: desired += (resource or key, source=(purchase, p.id), [p.purchased_at, p.purchased_at + g.duration?])
  promotions / trials / admin grants are explicit rows: kept unless expired or revoked

  current = entitlements(user) where revoked_at is null and source_type in (subscription, purchase)
  revoke  (current − desired)   with reason
  insert  (desired − current)   (unique index uq_entitlements_source makes this idempotent)
  update windows where changed
  emit ENTITLEMENT_CHANGED if anything changed → cache invalidation, access re-check of download grants
```

- Runs in the same transaction as the subscription change, under a per-user advisory lock.
- An optional **provisional grant** (e.g. 10 minutes) for `pending_verification` purchases is a product decision. Default: off.
- Losing an entitlement does not delete downloaded files instantly. The next licence renewal returns `ENTITLEMENT_LOST`, the app locks those books, and they unlock automatically if the user resubscribes.

## 7. Reconciliation

| Job | Schedule | What |
|-----|----------|------|
| Due-renewal check | Hourly | Subscriptions with `current_period_end` in the past 2 h / next 1 h: re-fetch provider state |
| Full sweep | Daily, spread across the day | All non-terminal subscriptions re-fetched (rate-limited to provider quotas) |
| Voided purchases | Daily | Play Voided Purchases API; App Store refund notifications fallback → revoke |
| Pending verification | Every 5 min with backoff | Retry verifications |
| Webhook inbox | Continuous | Retry `failed` with backoff; alert after 5 failures |
| Revenue reports | Daily | Import store financial reports to fill `payments.amount_minor` (store prices vary by region and tax) |

Metrics: verification failure rate, webhook lag, reconciliation diffs (any diff between our state and the provider's is logged and counted; a sustained non-zero rate pages on-call).

## 8. Edge cases covered

Upgrade/downgrade (proration handled by the store, our plan switches at the effective time), resubscribe after expiry, cancel then uncancel, grace period ending in recovery or hold, account hold → recovery, pause/resume (Play), refund (revoke immediately), chargeback, family sharing (App Store: `inAppOwnershipType = FAMILY_SHARED`, a configurable decision per product), same store account on two app accounts (binding mismatch ⇒ rejected; restore is offered to the original account only), purchase made while logged out (blocked in UI; the Subscribe button requires login), sandbox/test purchases (flagged by environment, never granted in production), price changes (handled by stores; `store_products` rows are never edited in place).

## 9. Store policy and web payments

- In-app purchases of digital content on Android/iOS use Play Billing / Apple IAP. **Whether and how the apps may link to web checkout** (reader-app rules, regional programmes) changes over time and by country. It is a **Phase 4 research task against current official policy**, not something to assume now.
- A web checkout (bKash, Nagad, cards via SSLCommerz), if offered on a website, uses the same `PaymentProvider` interface. Gateway callbacks are never trusted alone: the server calls the gateway's validation API before recording a payment.
- Plan prices displayed in the app always come from the store SDK (localised price strings), not from our DB.

## 10. Testing

- Provider adapters tested against **recorded, anonymised fixture payloads** for each state and notification type, including signature verification with test keys.
- `SubscriptionService` state machine: property-based tests generate random event sequences (including duplicates and reordering). Invariant: the final state equals applying the latest verified provider state, and entitlements match the derivation spec.
- End-to-end in staging with Play license testers and App Store sandbox / StoreKit testing in Xcode, covering purchase → renewal (accelerated) → cancel → expire → resubscribe → refund.
