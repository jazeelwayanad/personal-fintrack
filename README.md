# FinTrack

FinTrack is a personal finance planner for the web and Android. It records actual income and expenses, reserves upcoming EMIs and subscriptions, protects savings, tracks category budgets, and checks a proposed expense before recording it. Amounts are INR; dates and reminders use Asia/Kolkata.

## Development

Use Node 24, pnpm 12.3.4, PostgreSQL, and Flutter 3.44 or newer. The Next.js project lives at the repository root; the Android app is in [`mobile/fintrack`](mobile/fintrack).

```sh
pnpm install --frozen-lockfile
cp .env.example .env.local
# Set DATABASE_URL, AUTH_SECRET, MOBILE_AUTH_SECRET and CRON_SECRET in .env.local.
pnpm db:generate
pnpm db:migrate
pnpm dev
```

If this is an existing database created before migrations were added, back it up and compare it with the baseline schema before marking `20261005000000_baseline` as applied. Then run `pnpm db:migrate`. Do **not** run the baseline migration over existing tables.

For the Android app:

```sh
cd mobile/fintrack
flutter pub get
flutter run --dart-define=API_BASE_URL=https://your-fintrack-server.example
flutter build apk --release --dart-define=API_BASE_URL=https://your-fintrack-server.example
```

The release APK is created at `mobile/fintrack/build/app/outputs/flutter-apk/app-release.apk`. The private test build uses Android's debug signing key. Keep the default HTTPS server unless you have a preview backend; local HTTP is accepted only in Flutter debug mode. The website and Android app sign into the same FinTrack account.

Run checks with `pnpm lint`, `pnpm test`, `pnpm build`, `flutter analyze`, and `flutter test` from the appropriate project directory. The database integration suite runs only against the isolated PostgreSQL database on `localhost:55432`: `RUN_DATABASE_TESTS=1 pnpm exec dotenv run -q -f .env.local -- pnpm test`.

## Financial behavior

A monthly salary plan sets the payday cycle, but increases the balance only after **Received** is confirmed. Other planned income is also excluded until receipt. Unpaid expenses due through the next payday, including overdue ones, are reserved. The spending check protects those bills, the savings amount, and the unspent balances of other category budgets. A scheduled expense is linked to one actual transaction; its paid amount lowers cash and releases its reservation. The **Already spent** action can record a real expense even when planned spending is blocked.

The mobile ledger is stored in account-specific SQLite and the web ledger in account-specific IndexedDB. Both keep outgoing edits across restarts and sync on launch, resume/focus, after edits, and reconnect. Settings shows conflicts for review. Legacy browser records can be imported from the previous FinTrack database through Settings after signing into the correct account. Existing server records are imported automatically on the first versioned sync.

## Notifications and deployment

In-app reminders work without push permission. The Android app is registered in Firebase as `com.jazeelwayanad.fintrack`, and its non-secret `google-services.json` is included in the Android project. The server reads its private Firebase service-account JSON from Vercel's `FIREBASE_SERVICE_ACCOUNT` secret; never commit that key. Build the APK with `flutter build apk --release`. A foreground message is displayed locally; Android handles background notification display. The app registers or removes its token after the user enables notifications or signs out. The FinTrack server URL is built into the app, so the sign-in screen does not require a server setting.

For browser push, generate a VAPID key pair and set `NEXT_PUBLIC_WEB_PUSH_KEY`, `WEB_PUSH_PRIVATE_KEY`, and `WEB_PUSH_SUBJECT=mailto:you@example.com` on Vercel. The site uses its PWA service worker to display and open reminders.

The daily reminder route is scheduled at 03:00 UTC (about 08:30 India time) through `vercel.json`. Set a unique `CRON_SECRET` in Vercel to protect that route. The Vercel Hobby scheduler may execute later within the hour. Delivery history prevents a successful daily summary from being sent twice to one device. Missing Firebase or VAPID configuration does not stop in-app reminders.

Before production deployment: back up the current PostgreSQL database, verify the additive migration against a copy, configure the new secrets, deploy the backend, and test one account on a preview deployment. Then release the website and Android private-test APK. Do not put `DATABASE_URL` or any server secret into `--dart-define` or the Android package.
