# Metric — Firebase & Account Authentication Setup Guide

"Metric" uses **Email/Password Authentication** (mapped under the hood from usernames: `username@metricapp.local`) and **Cloud Firestore**. Accounts possess permanent, stable UIDs. Everything in Firestore is strictly encrypted ciphertext.

---

### Step 1: Create a Free Firebase Project
1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Click **Add project** and name it `metric-private` (or any name you prefer).
3. **Disable Google Analytics** when prompted (ensures 0 telemetry / privacy).
4. Make sure the billing plan is set to **Spark (Free)**.

---

### Step 2: Enable Email/Password Authentication
1. In the Firebase console left menu, go to **Build** → **Authentication**.
2. Click **Get Started**, then click the **Sign-in method** tab.
3. Select **Email/Password**, toggle **Enable**, and click **Save**.
   > *Users enter only a simple Username in the app UI. The app internally maps it to a zero-knowledge account generating a permanent, stable UID.*

---

### Step 3: Create Firestore Database
1. Go to **Build** → **Firestore Database**.
2. Click **Create database**.
3. Choose a location closest to you (e.g. `nam5 (us-central)` or `asia-south1`).
4. Choose **Start in production mode**.
5. Click **Create**.

---

### Step 4: Deploy Security Rules
1. In Firestore Database, click the **Rules** tab.
2. Paste the contents of `firestore.rules` (included in this project root):
   - Restricts read/write strictly to stable authenticated account UIDs.
   - Rejects any document containing plaintext keys (`text`, `caption`, `preview`, `thumbnail`, etc.).
3. Click **Publish**.

---

### Step 5: Add Android & iOS App Configurations

#### For Android:
1. In Project Settings, click **Add app** → **Android**.
2. Package name: `com.metric.app.metric`.
3. Download `google-services.json` and place it in:
   `android/app/google-services.json`

#### For iOS:
1. Click **Add app** → **iOS**.
2. Bundle ID: `com.metric.app.metric`.
3. Download `GoogleService-Info.plist` and place it in:
   `ios/Runner/GoogleService-Info.plist`
