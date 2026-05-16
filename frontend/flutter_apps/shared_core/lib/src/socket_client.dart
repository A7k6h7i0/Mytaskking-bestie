import 'package:socket_io_client/socket_io_client.dart' as io;
import 'auth_store.dart';

class BestieSocket {
  final String url;
  final BestieAuthStore auth;
  io.Socket? _socket;

  BestieSocket({required this.url, required this.auth});

  io.Socket connect() {
    final token = auth.accessToken;
    if (token == null) throw StateError('Not authenticated');
    final s = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .setPath('/socket.io')
          .enableForceNew()
          .build(),
    );
    _socket = s;
    return s;
  }

  io.Socket? get socket => _socket;

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
