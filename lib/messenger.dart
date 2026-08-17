import 'package:flutter/material.dart';

/// Lets async code show messages without holding on to a stale BuildContext.
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showMessage(String message, {SnackBarAction? action}) {
  final state = messengerKey.currentState;
  if (state == null) return;
  state.hideCurrentSnackBar();
  state.showSnackBar(SnackBar(content: Text(message), action: action));
}
