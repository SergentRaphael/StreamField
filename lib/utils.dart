import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Transforme une erreur technique en message compréhensible.
String friendlyError(Object e) {
  if (e is TimeoutException) return 'Le serveur met trop de temps à répondre.';
  if (e is SocketException || e is http.ClientException || e is HandshakeException) {
    return 'Connexion impossible. Vérifie le lien et ta connexion internet.';
  }
  if (e is FormatException) return 'La réponse du serveur est illisible.';
  return e.toString().replaceFirst('Exception: ', '');
}
