# connect.mytaskking.com — Calls API (for the Flutter app)

Base URL: `https://connect.mytaskking.com`
Signaling: Socket.IO, namespace `/public` (default Socket.IO path `/socket.io/`)
Media: mediasoup SFU — audio (Opus) + video (VP8/H264)

No auth on any endpoint today — anyone with a room code can join.

## Architecture in one paragraph

The server keeps one mediasoup **Router** per room. Each client opens a Socket.IO
connection, joins a room, then creates two **WebRTC transports** through mediasoup
(one to send its own mic/cam, one to receive everyone else's). Media itself never
touches Socket.IO — it flows over real WebRTC (SRTP/DTLS) directly between the
client and the server's mediasoup worker. Socket.IO only carries the
signaling handshake (SDP-equivalent parameters, "here's a new producer", etc).
The server also auto-starts a server-side recording (separate audio/video `.webm`
per participant) the moment the first person joins a room.

---

## REST endpoints

All under `/api`.

### `POST /api/room`
Create or reuse a room.

Request body (optional):
```json
{ "roomId": "123-456-789" }
```
If `roomId` is omitted, the server generates one (`###-###-###` digit format).

Response:
```json
{ "success": true, "roomId": "123-456-789", "message": "Room ready" }
```

### `GET /api/room/:roomId`
```json
{ "roomId": "123-456-789", "active": true, "activeStreams": 2, "recordingId": "rec_123-456-789_1699999999999" }
```

### `GET /api/recordings`
All recordings on the server.
```json
{ "success": true, "count": 3, "recordings": [ { "id": "...", "roomId": "...", "startTime": "...", "participants": ["..."], "files": [ { "name": "...", "url": "/api/recordings/.../files/...", "kind": "audio|video", "participantId": "..." } ] } ] }
```

### `GET /api/recordings/room/:roomId`
Same shape, filtered to one room.

### `GET /api/recordings/:recordingId`
Single recording's detail (same object shape as above).

### `DELETE /api/recordings/:recordingId`
```json
{ "success": true, "message": "Recording ... deleted successfully", "recordingId": "..." }
```

### `GET /api/recordings/:recordingId/files/:fileName`
Streams the raw file (`Content-Type: audio/webm` or `video/webm`, `Accept-Ranges: bytes`).

---

## Socket.IO signaling (`/public` namespace)

Connect with: `https://connect.mytaskking.com/public`

### Server → client events

| Event | Payload | When |
|---|---|---|
| `config` | `{ iceServers: { iceServers: [...], iceCandidatePoolSize: 10 } }` | right after connecting |
| `newProducer` | `{ producerId, socketId, userName, kind: "audio"\|"video" }` | another participant starts sending a track |
| `userJoined` | `{ socketId, userName, participantCount }` | someone else joins the room |
| `userLeft` | `{ socketId, participantCount }` | someone else leaves |

### Client → server events (all use a Socket.IO ack callback)

| Event | Request | Ack response |
|---|---|---|
| `joinRoom` | `{ roomId, userName }` | `{ success: true, routerRtpCapabilities, existingProducers: [{producerId, socketId, kind, userName}], participantCount }` or `{ success: false, error }` |
| `createWebRTCTransport` | `{ roomId, direction: "send"\|"recv" }` | `{ params: { id, iceParameters, iceCandidates, dtlsParameters } }` or `{ error }` |
| `connectTransport` | `{ roomId, transportId, dtlsParameters, direction }` | `{ success: true }` or `{ error }` |
| `produce` | `{ roomId, transportId, kind, rtpParameters }` | `{ id }` or `{ error }` |
| `consume` | `{ roomId, producerId, rtpCapabilities }` | `{ id, producerId, kind, rtpParameters }` or `{ error }` |
| `resumeConsumer` | `{ consumerId }` | `{ success: true }` or `{ error }` |

---

## Call flow (both web and Flutter follow the same sequence)

1. Connect socket → receive `config` (cache ICE servers).
2. `POST /api/room` to get a `roomId` (or let the user type one, and skip straight to `joinRoom` — the server lazily creates the room's mediasoup router on first join either way).
3. Emit `joinRoom` → get `routerRtpCapabilities` + `existingProducers`.
4. Load a mediasoup `Device` with `routerRtpCapabilities`.
5. Create the **send** transport (`createWebRTCTransport` with `direction: "send"`), wire its `connect` and `produce` events to `connectTransport` / `produce`.
6. Create the **recv** transport the same way with `direction: "recv"`.
7. Grab mic/camera, call `sendTransport.produce({ track })` for each track.
8. For every entry in `existingProducers`, and for every future `newProducer` event: call `consume` → `recvTransport.consume(...)` → attach the resulting track to a stream → emit `resumeConsumer`.
9. Update UI on `userJoined` / `userLeft`.

---

## Flutter implementation

mediasoup's client protocol is not plain WebRTC SDP — it hands you raw
`iceParameters`/`iceCandidates`/`dtlsParameters`/`rtpParameters` that a
mediasoup-aware client library assembles into a real `RTCPeerConnection`
under the hood. Don't hand-roll this. Use:

- **`flutter_webrtc`** — the actual `RTCPeerConnection`/`MediaStream`/`getUserMedia` primitives for Flutter.
- **`mediasoup_client_flutter`** — a Dart port of the JS `mediasoup-client` (`Device`, `Transport`, `Producer`, `Consumer`), built on top of `flutter_webrtc`. Same concepts/API shape as the JS client below, just Dart syntax.
- **`socket_io_client`** — Socket.IO client for Dart, same wire protocol as the JS server expects.

`pubspec.yaml`:
```yaml
dependencies:
  flutter_webrtc: ^0.11.0
  mediasoup_client_flutter: ^1.0.0   # check pub.dev for the latest compatible version
  socket_io_client: ^2.0.3
```

### 1. Connect + get ICE config

```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

final socket = IO.io(
  'https://connect.mytaskking.com/public',
  IO.OptionBuilder().setTransports(['websocket']).build(),
);

Map<String, dynamic>? iceServers;
socket.on('config', (data) {
  iceServers = data['iceServers'];
});

socket.onConnect((_) => print('connected: ${socket.id}'));
```

### 2. Create/join a room

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<String> createRoom() async {
  final res = await http.post(
    Uri.parse('https://connect.mytaskking.com/api/room'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({}),
  );
  return jsonDecode(res.body)['roomId'];
}

Future<Map<String, dynamic>> joinRoom(String roomId, String userName) {
  final completer = Completer<Map<String, dynamic>>();
  socket.emitWithAck('joinRoom', {'roomId': roomId, 'userName': userName},
      ack: (data) => completer.complete(data));
  return completer.future;
}
```

### 3. Load the mediasoup Device

```dart
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';

final device = Device();

Future<void> init(String roomId, String userName) async {
  final joinResult = await joinRoom(roomId, userName);
  await device.load(
    routerRtpCapabilities: RtpCapabilities.fromMap(joinResult['routerRtpCapabilities']),
  );
}
```

### 4. Send transport (your own mic/cam)

```dart
Future<Transport> createSendTransport(String roomId) async {
  final completer = Completer<Map<String, dynamic>>();
  socket.emitWithAck(
    'createWebRTCTransport',
    {'roomId': roomId, 'direction': 'send'},
    ack: (data) => completer.complete(data),
  );
  final res = await completer.future;
  final p = res['params'];

  final transport = device.createSendTransport(
    id: p['id'],
    iceParameters: IceParameters.fromMap(p['iceParameters']),
    iceCandidates: (p['iceCandidates'] as List)
        .map((c) => IceCandidate.fromMap(c))
        .toList(),
    dtlsParameters: DtlsParameters.fromMap(p['dtlsParameters']),
    iceServers: iceServers, // pass through what 'config' gave you
  );

  transport.on('connect', (Map data) async {
    final ack = Completer<Map<String, dynamic>>();
    socket.emitWithAck('connectTransport', {
      'roomId': roomId,
      'transportId': transport.id,
      'dtlsParameters': data['dtlsParameters'].toMap(),
      'direction': 'send',
    }, ack: (d) => ack.complete(d));
    await ack.future;
    data['callback']();
  });

  transport.on('produce', (Map data) async {
    final ack = Completer<Map<String, dynamic>>();
    socket.emitWithAck('produce', {
      'roomId': roomId,
      'transportId': transport.id,
      'kind': data['kind'],
      'rtpParameters': data['rtpParameters'].toMap(),
    }, ack: (d) => ack.complete(d));
    final res = await ack.future;
    data['callback'](res['id']);
  });

  return transport;
}
```

### 5. Recv transport + consuming remote participants

```dart
Future<Transport> createRecvTransport(String roomId) async {
  final completer = Completer<Map<String, dynamic>>();
  socket.emitWithAck(
    'createWebRTCTransport',
    {'roomId': roomId, 'direction': 'recv'},
    ack: (data) => completer.complete(data),
  );
  final res = await completer.future;
  final p = res['params'];

  final transport = device.createRecvTransport(
    id: p['id'],
    iceParameters: IceParameters.fromMap(p['iceParameters']),
    iceCandidates: (p['iceCandidates'] as List)
        .map((c) => IceCandidate.fromMap(c))
        .toList(),
    dtlsParameters: DtlsParameters.fromMap(p['dtlsParameters']),
    iceServers: iceServers,
  );

  transport.on('connect', (Map data) async {
    final ack = Completer<Map<String, dynamic>>();
    socket.emitWithAck('connectTransport', {
      'roomId': roomId,
      'transportId': transport.id,
      'dtlsParameters': data['dtlsParameters'].toMap(),
      'direction': 'recv',
    }, ack: (d) => ack.complete(d));
    await ack.future;
    data['callback']();
  });

  return transport;
}

Future<void> consumeStream(
  Transport recvTransport,
  String roomId,
  String producerId,
) async {
  final ack = Completer<Map<String, dynamic>>();
  socket.emitWithAck('consume', {
    'roomId': roomId,
    'producerId': producerId,
    'rtpCapabilities': device.rtpCapabilities.toMap(),
  }, ack: (d) => ack.complete(d));
  final data = await ack.future;

  final consumer = await recvTransport.consume(
    id: data['id'],
    producerId: data['producerId'],
    kind: RTCRtpMediaTypeExtension.fromString(data['kind']),
    rtpParameters: RtpParameters.fromMap(data['rtpParameters']),
  );

  // consumer.track is the remote MediaStreamTrack — attach it to an
  // RTCVideoRenderer (video) or just let it play (audio).

  socket.emitWithAck('resumeConsumer', {'consumerId': consumer.id}, ack: (_) {});
}
```

### 6. Producing your own mic/cam

```dart
import 'package:flutter_webrtc/flutter_webrtc.dart';

Future<void> startProducing(Transport sendTransport, {bool video = true}) async {
  final stream = await navigator.mediaDevices.getUserMedia({
    'audio': true,
    'video': video,
  });

  for (final track in stream.getAudioTracks()) {
    await sendTransport.produce(track: track, stream: stream);
  }
  if (video) {
    for (final track in stream.getVideoTracks()) {
      await sendTransport.produce(track: track, stream: stream);
    }
  }
}
```

### 7. Wiring it together

```dart
socket.on('newProducer', (data) {
  consumeStream(recvTransport, roomId, data['producerId']);
});

socket.on('userJoined', (data) {
  // update participant count / UI
});

socket.on('userLeft', (data) {
  // remove that participant's tile
});

// On room entry, after joining:
for (final p in joinResult['existingProducers']) {
  consumeStream(recvTransport, roomId, p['producerId']);
}
```

---

## Notes / gotchas

- `direction` in `createWebRTCTransport`/`connectTransport` must be exactly `"send"` or `"recv"` — the server keys its internal transport map on `roomId|socketId|direction`.
- `kind` is always `"audio"` or `"video"` (lowercase), matching mediasoup's own convention.
- The server has **no reconnection/resume logic** — if the socket disconnects, you must rejoin from scratch (`joinRoom` again) and recreate both transports.
- Recording is automatic and server-side — the Flutter app doesn't need to do anything to trigger it. Use the `/api/recordings/*` endpoints if the app needs to show/download past recordings.
- No authentication today — don't rely on room codes for privacy beyond obscurity.
