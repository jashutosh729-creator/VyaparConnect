# VyaparConnect MVP

VyaparConnect is a Flutter and Firebase B2B marketplace MVP for retailers and manufacturers.

## Firebase project

- Firebase project: `vyaparconnect-jashu-2026`
- Android application ID: `com.example.b2b_marketaplace`
- Firestore database: default database in `asia-south1` (Mumbai)
- Firestore rules are deployed from `firestore.rules`.

FlutterFire configuration is generated in `lib/firebase_options.dart`.

## Finish Authentication setup

Open [Firebase Authentication](https://console.firebase.google.com/project/vyaparconnect-jashu-2026/authentication/providers), choose **Get started** if asked, then enable **Email/Password** under Native providers and save.

## Run

From the project root:

```powershell
flutter pub get
flutter run
```

To create an Android debug APK:

```powershell
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

## MVP features

- Email/password authentication and retailer/manufacturer registration
- Role-specific home navigation
- Firestore product catalog, search, product creation and deletion
- Retailer cart and order placement
- Manufacturer order accept/reject and retailer status tracking
- Firestore real-time messages and price proposals

Images, payments, admin approval UI, and push notifications are outside this MVP.
