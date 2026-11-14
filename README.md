# Local Produce Connect

A Flutter marketplace using Firebase Authentication and Cloud Firestore for
accounts, listings, and vendor map locations. Cart, order, reservation, review,
chat, favorite, and notification workflows currently use in-memory data and
are not synchronized across devices or app restarts.

## Run

```powershell
flutter pub get
flutter run
```

Enable Email/Password in Firebase Authentication and configure Firestore for the
existing Firebase project. Deploy the Firestore security rules with:

```powershell
firebase deploy --project new-project-c0fa2 --only firestore:rules
```

Firebase Auth registrations send an email verification link. Users must verify
their email before using protected buyer or vendor features; the app refreshes
the Auth status when resumed and does not store a client-editable verification
flag in Firestore. Configure the Firebase Authentication email template and
deploy the updated rules before release. Phone OTP, trusted administrator
claims, vendor verification review, reports, and account blocking are not part
of this phase.
Firebase Auth applies its own anti-abuse limits to verification-email requests;
the app has no resend cooldown, and those service limits cannot be disabled by
changing the email address or editing this Flutter client.
Account deletion is currently unavailable and its profile control is disabled
until a trusted backend can delete the Firebase Auth account and cascade the
requested Firestore cleanup. The selected policy removes related transaction
records for both participants and hides chat history only for the deleting
account.

The app does not upload image files. Listing and profile photo fields accept a
public HTTPS image URL from an external host. No image-hosting provider
is configured in this project, so vendors must host images elsewhere; leaving a
photo URL blank displays the listing placeholder. No Firebase Storage or
Storage rules are used.

Firestore listings created before the privacy update may still contain the
public `owner_email` field. Remove that field from existing listing documents
in the Firebase console or through a trusted migration before considering those
records free of vendor email addresses.

Location lookup and map tiles use public online services and require an
internet connection. The OpenStreetMap tile server has a usage policy; use an
appropriate tile provider for production traffic.

This project is Android-only.

## Build and verification

```powershell
flutter analyze
flutter test
flutter build apk --release
```
"# capstone" 
"# capstone" 
"# capstone" 
"# capstone" 
"# capstone" 
