# Google Calendar two-way sync: one-time setup

The app signs in with Google on the phone and talks to the Calendar API directly. Google only allows this for apps registered in your Google Cloud project, so these steps have to be done once in [Google Cloud Console](https://console.cloud.google.com/), signed in with your account.

Use the **same project** as the web app. It already has the Calendar API enabled and a **Web** OAuth client.

## 1. Add an Android client

APIs & Services → **Credentials** → **Create credentials** → **OAuth client ID**

| Field | Value |
|---|---|
| Application type | **Android** |
| Name | Subway Board Android |
| Package name | `com.arunvijey.subwayboard` |
| SHA-1 certificate fingerprint | `18:C3:3F:A3:56:F2:9A:E2:53:54:DA:36:0F:BC:7D:3E:3F:0D:A4:34` |

That fingerprint belongs to the debug signing key on this PC, which signs the builds installed so far. A Play Store release will be signed with a different key, and its SHA-1 will need a second Android client (or an extra fingerprint) at that point.

Nothing needs to be downloaded; the Android client just has to exist.

## 2. Check the consent screen

APIs & Services → **OAuth consent screen**

- If the app is in **Testing**, make sure your Google account is listed under **Test users**.
- Scopes used: `.../auth/calendar.events` and `.../auth/calendar.calendarlist.readonly` (the same as the web app).
- Google shows an "unverified app" warning while testing; choose *Continue*.

## 3. Turn it on in the app

Settings → Calendar sync → **Sync: Google Calendar (two-way)**

1. Paste the **Web** client ID (Credentials → the client of type *Web application*, ends in `.apps.googleusercontent.com`). It's the same value the web app's settings use. Restoring a web app backup fills it in automatically.
2. Tap **Connect Google**, pick your account, allow calendar access.
3. Choose which calendars to show, then **SAVE & SYNC**.

## If sign-in fails

| Message | Usual cause |
|---|---|
| "Google sign-in isn't set up for this app" | The ID pasted isn't the **Web** client, or the Android client's package name/SHA-1 doesn't match |
| "Sign-in was closed" right after picking an account | Same as above: Google reports config problems as a cancel on Android |
| Access blocked / app not verified | Your account isn't a test user on the consent screen |
| "Restart the app to use the new Client ID" | The client ID was changed after a sign-in attempt; close and reopen the app |

To get the SHA-1 again (for example on another PC):

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```
