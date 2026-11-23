# Google Calendar two-way sync: one-time setup

The app signs in with Google on the phone and talks to the Calendar API directly. Google only allows this for apps registered in a Google Cloud project, so these steps have to be done once in [Google Cloud Console](https://console.cloud.google.com/), signed in with your account. Allow about 10 minutes.

Newer consoles group the OAuth settings under **Google Auth Platform** (Branding, Audience, Data access, Clients). Older ones call it **APIs & Services → OAuth consent screen** and **Credentials**. The fields are the same.

## 1. Create a project

Project picker (top bar) → **New project** → name it `Subway Board` → **Create**, then make sure it's selected.

## 2. Enable the Calendar API

APIs & Services → **Library** → search **Google Calendar API** → **Enable**.

## 3. Set up the consent screen

Google Auth Platform:

| Section | What to set |
|---|---|
| **Branding** | App name `Subway Board`; your email as user support email and developer contact |
| **Audience** | User type **External**; under **Test users**, add your own Google account |
| **Data access** | **Add or remove scopes** → `.../auth/calendar.events` and `.../auth/calendar.calendarlist.readonly` |

While the app is in **Testing**, only test users can sign in, and Google shows an "unverified app" warning; choose *Continue*.

## 4. Create a Web client

Google Auth Platform → **Clients** → **Create client**

| Field | Value |
|---|---|
| Application type | **Web application** |
| Name | Subway Board Web |

No origins or redirect URIs are needed for the Android app. Copy the **Client ID** (ends in `.apps.googleusercontent.com`); this is what gets pasted into the app.

If you also use the web version of Subway Board, add its address (e.g. `https://yourname.github.io`) under **Authorized JavaScript origins** and use the same Client ID in its settings.

## 5. Create an Android client

Google Auth Platform → **Clients** → **Create client**

| Field | Value |
|---|---|
| Application type | **Android** |
| Name | Subway Board Android |
| Package name | `com.arunvijey.subwayboard` |
| SHA-1 certificate fingerprint | `82:11:A8:0E:FD:8B:EF:77:84:3D:B0:82:22:D9:87:86:CF:DA:04:86` |

That fingerprint belongs to the release key (`subwayboard-release.jks`, configured through `android/key.properties`), which signs every release build. A Play Store release would be re-signed by Google, and Play's app-signing SHA-1 would need adding as well.

Nothing needs to be downloaded; the Android client just has to exist.

## 6. Turn it on in the app

Settings → Calendar sync → **Sync: Google Calendar (two-way)**

1. Paste the **Web** client ID from step 4. If a restored backup already filled in an older ID, replace it: IDs from a deleted project no longer work.
2. Tap **Connect Google**, pick your account, allow calendar access.
3. Choose which calendars to show, then **SAVE & SYNC**.

The app syncs at launch and every 10 minutes while it's open; no server is needed.

## If sign-in fails

| Message | Usual cause |
|---|---|
| "Google sign-in isn't set up for this app" | The ID pasted isn't the **Web** client, or the Android client's package name/SHA-1 doesn't match |
| "Sign-in was closed" right after picking an account | Same as above: Google reports config problems as a cancel on Android |
| Access blocked / app not verified | Your account isn't a test user (step 3), or the Calendar API isn't enabled (step 2) |
| "Restart the app to use the new Client ID" | The client ID was changed after a sign-in attempt; close and reopen the app |
| Asked to reconnect about once a week | Likely the consent screen's *Testing* status; publishing it (Audience → **Publish app**) should stop this, and personal use doesn't need Google's verification |

To get the SHA-1 again (the password is `storePassword` in `android/key.properties`):

```powershell
keytool -list -v -keystore "<path to subwayboard-release.jks>" -alias subwayboard
```
