# 💰 FinTrack

**Simple finance tracking for everyday life.**

FinTrack helps you track income, expenses, upcoming payments, savings,
and budgets --- all from one clean dashboard. Available on **Web** and
**Android**.

## 🚀 Try FinTrack

🌐 **Web App:** [fintrack.eucodes.tech](https://fintrack.eucodes.tech)

📱 **Android APK:** [Download APK](https://github.com/jazeelwayanad/personal-fintrack/releases/latest)

FinTrack 1.2.0 uses Android build 7 and finance capability 2.

## ✨ Features

-   💸 Track income & expenses
-   📅 Plan EMIs, bills & subscriptions
-   💰 Protect your savings
-   📊 Manage category budgets
-   🧮 Check available credit before spending
-   🔔 Get payment reminders
-   🔄 Sync across Web & Android
-   👤 Manage your account & profile
-   💬 Send feedback from the app

## 🛠️ Built With

**Next.js** · **Flutter** · **PostgreSQL** · **Firebase** ·
**Cloudinary**

## 💻 Run Locally

``` bash
pnpm install
cp .env.example .env.local
pnpm db:generate
pnpm db:migrate
pnpm dev
```

## 📱 Android

``` bash
cd mobile/fintrack
flutter pub get
flutter run --dart-define=API_BASE_URL=https://fintrack.eucodes.tech
```

### 📦 Build APK

``` bash
flutter build apk --release --dart-define=API_BASE_URL=https://fintrack.eucodes.tech
```

APK output:

``` text
mobile/fintrack/build/app/outputs/flutter-apk/app-release.apk
```

## 🔐 Security

Keep database credentials, Firebase keys, Cloudinary secrets, and other
private keys out of GitHub.

## 🌍 Live

👉 **[fintrack.eucodes.tech](https://fintrack.eucodes.tech)**

------------------------------------------------------------------------

### ❤️ FinTrack

**Plan better. Spend smarter. Stay in control.**
