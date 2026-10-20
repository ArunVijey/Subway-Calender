// Google sign-in and Calendar API calls for two-way sync.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

const kExpired = 'Google session expired. Tap the top bar to reconnect';

class GoogleAuth {
  static const scopes = [
    'https://www.googleapis.com/auth/calendar.events',
    'https://www.googleapis.com/auth/calendar.calendarlist.readonly',
  ];

  String? _initFor;
  GoogleSignInAccount? _account;
  String? _token;

  bool get connected => _account != null && _token != null;
  String? get email => _account?.email;

  Future<void> _init(String clientId) async {
    if (clientId.isEmpty) throw 'Paste your OAuth Client ID first';
    if (_initFor == clientId) return;
    // The sign-in library can only be set up once per launch.
    if (_initFor != null) throw 'Restart the app to use the new Client ID';
    await GoogleSignIn.instance.initialize(serverClientId: clientId);
    _initFor = clientId;
  }

  /// Silent reconnect at startup. Returns whether a usable session exists.
  Future<bool> restore(String clientId) async {
    try {
      await _init(clientId);
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      _token = (await _account?.authorizationClient.authorizationForScopes(scopes))?.accessToken;
    } catch (e) {
      debugPrint('google restore: $e');
      _token = null;
    }
    return connected;
  }

  /// Interactive sign-in + calendar permission. Must be called from a tap.
  Future<void> connect(String clientId) async {
    await _init(clientId);
    try {
      _account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      _token = (await _account!.authorizationClient.authorizeScopes(scopes)).accessToken;
    } on GoogleSignInException catch (e) {
      _token = null;
      throw switch (e.code) {
        GoogleSignInExceptionCode.canceled => 'Sign-in was closed (if you did pick an account, check the Android client in Google Cloud)',
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          "Google sign-in isn't set up for this app. Check the Client ID and the Android client in Google Cloud",
        GoogleSignInExceptionCode.uiUnavailable => 'Google sign-in is not available on this phone',
        _ => 'Google sign-in failed${e.description != null ? ': ${e.description}' : ''}',
      };
    }
  }

  Future<void> disconnect() async {
    _token = null;
    final had = _account != null;
    _account = null;
    if (had) {
      try {
        await GoogleSignIn.instance.disconnect();
      } catch (e) {
        debugPrint('google disconnect: $e');
      }
    }
  }

  /// A current access token (refreshed silently when it has expired).
  Future<String> _fresh() async {
    final a = _account;
    if (a == null) throw kExpired;
    final auth = await a.authorizationClient.authorizationForScopes(scopes);
    if (auth == null) {
      _token = null;
      throw kExpired;
    }
    return _token = auth.accessToken;
  }

  /// Calls the Calendar API. Returns decoded JSON, or null for 204 / a missing
  /// item when [missingOk].
  Future<Map<String, dynamic>?> api(String path, {String method = 'GET', Map<String, dynamic>? body, bool missingOk = false}) async {
    final token = await _fresh();
    final req = http.Request(method, Uri.parse('https://www.googleapis.com/calendar/v3$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = jsonEncode(body);
    final http.Response r;
    try {
      r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 30)));
    } on TimeoutException {
      throw 'Google timed out';
    } catch (_) {
      throw 'Could not reach Google';
    }
    if (r.statusCode == 401) {
      _token = null;
      throw kExpired;
    }
    if ((r.statusCode == 404 || r.statusCode == 410) && missingOk) return null;
    if (r.statusCode < 200 || r.statusCode >= 300) {
      var m = 'Google error ${r.statusCode}';
      try {
        m = (jsonDecode(r.body)['error']['message'] as String?) ?? m;
      } catch (_) {}
      throw m;
    }
    if (r.statusCode == 204 || r.body.isEmpty) return null;
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
