# Borderless Overview preview

An isolated, interactive design preview. The live app, routes, authentication, storage, APIs, and schemas are unchanged. All records are explicitly labeled sample data; the account greeting is a sample name. Changes exist only in React memory and reset on reload.

## Run

```sh
node --import tsx design-preview/build.mts
python3 -m http.server 3015 --bind 127.0.0.1 --directory build/fintrack-preview
```

Open http://localhost:3015/. The bundle reuses installed React, Lucide, and the existing finance model and calculation engine. No new dependencies are required. Outfit is bundled locally.

## Scope

Warm ivory canvas, borderless surfaces, teal unallocated-money card, compact supporting totals, pastel quick actions, next payments, budgets, recent activity, expandable spending check, bottom navigation, and a yellow bottom-right transaction action. Desktop uses two columns and header navigation.

Expense/income entry, payment recording, linking, skipping, reports, balance visibility, and sample reset are interactive. Navigation to Plans, Budgets, and Activity scrolls within the single Overview preview. These are not replacements for the real application's routes or settings.

`nextPaymentPerPlan` selects the oldest unpaid occurrence for each plan, excluding paid/received and skipped records. The full occurrence collection remains available to the existing calculations. No financial logic is changed.

## Validation

Browser reviewed at 360, 390, 430, 768, and 1440px: no horizontal overflow, and visible buttons have at least 44px height. A 390×420 form retains reachable submission controls; required-field validation preserves the entered amount. Sample add, payment advancement, skip advancement, and linking were exercised in the browser. Native dialogs provide focus containment and Escape dismissal; focus indicators and reduced-motion support are retained. A physical phone's software keyboard has not been tested.

Schedule unit tests cover overdue, due today, recurring, received/paid, skipped, paused, and completed plans, and verify filtering does not affect finance calculations. Screenshots are saved under `artifacts/ui/borderless-overview-*.jpg`.

This is the requested design-review stage. Applying it to the actual screens and verifying authenticated production-data workflows are subsequent work. No production deployment was performed.
