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
3. **SHA-1 Fingerprint (MANDATORY for Google Sign-In & Google Drive backup)**:
   - Click **Add fingerprint**
   - Add your debug keystore SHA-1:
     `52:E5:ED:46:45:13:78:13:D1:3E:81:FC:9D:3D:B2:76:CE:F4:2C:96`
   - (Optional) Add SHA-256:
     `54:E6:47:48:BC:7B:A2:FC:A7:03:45:89:97:27:EC:61:B7:09:67:8C:81:E6:6A:F8:D0:93:93:44:36:43:0C:18`
4. Download the generated `google-services.json` (which will contain the `oauth_client` array) and place it in:
   `android/app/google-services.json`
5. Enable the **Google Drive API**:
   - Go to Google Cloud Console (same project: `metric-app-af543`):
     https://console.cloud.google.com/apis/library/drive.googleapis.com
   - Click **Enable**.

#### For iOS:
1. Click **Add app** → **iOS**.
2. Bundle ID: `com.metric.app.metric`.
3. Download `GoogleService-Info.plist` and place it in:
   `ios/Runner/GoogleService-Info.plist`
