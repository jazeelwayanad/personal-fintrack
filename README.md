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

## Borderless web interface

The authenticated web screens share warm ivory and white surfaces, dark teal, mint and yellow accents, visible focus rings, and a rounded mobile navigation dock. Overview, Plans, Transactions, Reports, Settings, Account, and sign-in use the updated design. Add transaction stays above the dock, with safe-area spacing; forms retain values on errors and guard against duplicate submissions.

**Available credit** is the display label for the existing unallocated-money calculation: recorded balance minus unpaid scheduled expenses, protected savings, and remaining category-budget reserves. It does not change the finance engine or add a borrowing facility.

Overview and the Plans payment schedule display only the oldest unpaid occurrence per plan, including overdue payments. Paying, linking, or skipping advances the displayed occurrence. Reports, reservations, reminders, and the backend retain the complete occurrence collection. No schema migration is required.

The interface reads the existing account-specific store and uses the authenticated `/api/v1/sync` service; no preview sample data enters the application. The isolated `design-preview` remains available separately.

## Account details and Cloudinary profile photos

My account displays editable name, email, and optional phone, with upload/change/remove photo actions. Changing the sign-in email requires the current password; edits refresh the web session from server-side account data. Account endpoints reuse the existing web-session/bearer authentication and origin checks.

Apply the additive `20261007000000_account_profile` and `20261007010000_cloudinary_profile` migrations with `pnpm db:migrate` before deploying this feature. They add optional profile details and Cloudinary references without changing financial records. The old binary field is retained only for compatibility; all new uploads use Cloudinary.

Configure these server-only values in `.env.local` and in the deployment environment, then restart the server:

```dotenv
CLOUDINARY_CLOUD_NAME=your-cloud-name
CLOUDINARY_API_KEY=your-api-key
CLOUDINARY_API_SECRET=your-api-secret
```

No unsigned upload preset is needed. The browser resizes a JPG/PNG/WebP photo (up to 10 MB) to a 512px square JPEG and sends it to the authenticated FinTrack endpoint. The server validates the content and a 512 KB maximum, signs the upload, and stores an authenticated Cloudinary asset. The database stores its public ID and format rather than image bytes. Private photos are delivered through the owner-authenticated photo endpoint using a short-lived signed Cloudinary download request. Secrets and Cloudinary download signatures are never returned to the browser.

Cloudinary upload/signature/access documentation: https://cloudinary.com/documentation/authentication_signatures and https://cloudinary.com/documentation/control_access_to_media . Photos are not public CDN assets; private delivery consumes Cloudinary API bandwidth. Replaced photos are removed on a best-effort basis; if cleanup fails, a generic server log indicates that an unused asset needs cleanup in Cloudinary. Explicit removal preserves the reference if Cloudinary deletion fails, allowing a retry. Legacy database photos remain readable until replaced or removed.

Without configuration, account editing still works and the screen clearly indicates that photo uploads are unavailable. Test storage requests are mocked; live Cloudinary validation requires real credentials. The build regenerates Prisma's client so cached deployments always use the current schema.

Android 1.1.1 (build 5) uses the production API, the Available credit label, one unpaid payment per plan, borderless surfaces, and an accessible yellow Add transaction action. The APK retains the existing private-test signing key; it is not a Play Store release.

### In-app feedback
Signed-in users can send suggestions and issue reports from My account. Feedback is stored separately from ledger records, with the account, topic, message, app version and date. No financial records are attached. Apply the additive `20261007020000_feedback` migration before publishing this endpoint. Retries use one submission ID; accounts are limited to five messages per hour.

Developers with database access can review the most recent 50 submissions using `node --env-file=<private-environment-file> scripts/feedback-inbox.mjs`. This is a private developer tool, not a public inbox or a new user/admin permission. Feedback is not emailed automatically.
