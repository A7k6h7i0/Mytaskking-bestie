# MyTaskKing — WebRTC Calling System (connect.mytaskking.com)

Complete reference for how voice/video calls work in this project: backend-driven lifecycle, mediasoup SFU media on **connect.mytaskking.com**, Flutter client, names, join/leave, and step-by-step implementation.

---

## 1. Architecture in one picture

MyTaskKing uses **two separate systems**:

| Layer | Server | Purpose |
|-------|--------|---------|
| **Call business logic** | MyTaskKing API (`/api/v1/calls`, `/api/v1/meetings`) + Socket.IO on API host | Invite, ring, roster, hang up, mute, buzzer, FCM push |
| **WebRTC media (SFU)** | **connect.mytaskking.com** | mediasoup router, ICE/TURN, audio/video tracks |

Media never flows through the main API socket. The API only tells clients **which room to join** and **who is in the call**. Actual audio/video uses WebRTC via mediasoup on connect.

```
┌─────────────┐     POST /calls/initiate      ┌──────────────────┐
│   Caller    │ ─────────────────────────────►│  MyTaskKing API  │
│  (Flutter)  │                               │  (port 4000)     │
└─────────────┘                               └────────┬─────────┘
       │                                                 │
       │◄── token: { mediaEngine, connectUrl,          │
       │              roomId, joinToken, mediaPeerId } ──┤
       │                                                 │
       │  socket: call.incoming ─────────────────────────►│ Callee
       │  FCM: type=call.incoming ──────────────────────►│ Callee
       │                                                 │
       │  POST /calls/:id/join (server roster)           │
       │                                                 │
       │  Socket.IO ──► connect.mytaskking.com/public    │
       │  joinRoom → createWebRTCTransport → produce     │
       │  WebRTC SRTP/DTLS (mic/camera)                  ▼
       │                                    ┌──────────────────────────┐
       └───────────────────────────────────►│ connect.mytaskking.com   │
                                            │ mediasoup SFU per room   │
                                            └──────────────────────────┘
```

**Primary engine:** mediasoup (Flutter: `mediasfu_mediasoup_client` + `flutter_webrtc`)  
**Legacy fallback:** Agora RTC if token has no `mediaEngine: 'mediasoup'`

---

## 2. connect.mytaskking.com — what it is

External SFU service. **No mediasoup worker code lives in this repo** — only an HTTP adapter in the backend.

| Item | Value |
|------|-------|
| REST base | `https://connect.mytaskking.com` |
| Signaling socket | `https://connect.mytaskking.com/public` (Socket.IO namespace `/public`) |
| Room = one call/meeting | Same string as `Call.channelName` (e.g. `call_abc123xyz`) |
| Auth on SFU today | None on connect service; join JWT is signed by MyTaskKing backend (optional) |
| ICE/TURN | Emitted on SFU socket event `config` after connect |
| Recording | Server-side auto `.webm` per participant; listed via `/api/recordings` |

Full SFU API spec is also in repo root: **`calls.md`**.

---

## 3. Backend — key files

| File | Role |
|------|------|
| `backend/src/modules/calls/calls.routes.js` | REST routes, FCM on initiate, socket emits |
| `backend/src/modules/calls/calls.service.js` | Call DB, initiate/join/leave, roster, mediasoup room |
| `backend/src/services/mediasoup.js` | `ensureRoom`, `generateMediaSession`, join JWT |
| `backend/src/modules/meetings/meetings.routes.js` | Meeting tokens (same mediasoup SFU) |
| `backend/src/sockets/index.js` | App Socket.IO: `call.signal`, `call.screenShare`, etc. |
| `backend/src/services/fcm.js` | Push `call.incoming`, `call.ended` |
| `backend/src/config/index.js` | `MEDIASOUP_*` env vars |

---

## 4. Backend environment variables

Add to `backend/.env`:

```env
MEDIASOUP_CONNECT_API_URL=https://connect.mytaskking.com
MEDIASOUP_SOCKET_URL=https://connect.mytaskking.com/public
MEDIASOUP_JOIN_SECRET=your-secret-same-as-or-separate-from-JWT
MEDIASOUP_JOIN_TOKEN_TTL_SECONDS=7200

# Optional legacy (meetings roster UID mapping only)
AGORA_APP_ID=
AGORA_APP_CERTIFICATE=

# Call ring timeout (default 60s → MISSED)
CALL_RING_TIMEOUT_MS=60000

# FCM for background incoming calls
FIREBASE_PROJECT_ID=
FIREBASE_CLIENT_EMAIL=
FIREBASE_PRIVATE_KEY=
```

Config loader: `backend/src/config/index.js` lines 94–99.

---

## 5. Backend — mediasoup adapter (full code path)

### 5.1 Create SFU room when call starts

On `POST /calls/initiate`, after DB create:

```javascript
// backend/src/modules/calls/calls.service.js
await mediasoup.ensureRoom(call.channelName);

const tokenForUser = (uid) => {
  const part = call.participants.find((p) => p.userId === uid);
  const name = part?.user?.name || 'Participant';
  return mediasoup.generateMediaSession({
    channelName: call.channelName,
    userId: uid,
    userName: name,
  });
};
```

### 5.2 `ensureRoom` — HTTP to connect

```javascript
// backend/src/services/mediasoup.js
async function ensureRoom(roomId) {
  const base = config.mediasoup.connectApiUrl.replace(/\/$/, '');
  const res = await fetch(`${base}/api/room`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ roomId }),
  });
  // ...
}
```

### 5.3 Token returned to Flutter

```javascript
// backend/src/services/mediasoup.js — generateMediaSession()
{
  mediaEngine: 'mediasoup',
  disabled: false,
  connectUrl: 'https://connect.mytaskking.com/public',
  connectApiUrl: 'https://connect.mytaskking.com',
  channelName: 'call_xxx',      // same as roomId
  roomId: 'call_xxx',
  userName: 'Priya K',
  joinToken: '<JWT signed with MEDIASOUP_JOIN_SECRET>',
  mediaPeerId: 1234567890,      // stable UI id (replaces legacy agoraUid)
  expiresAt: 1234567890123
}
```

JWT payload: `{ roomId, userId, userName, purpose: 'call-join' }`.

---

## 6. Backend REST API — call lifecycle

Base: **`/api/v1/calls`**

| Step | Method | Route | What happens |
|------|--------|-------|--------------|
| Start call | POST | `/initiate` | Create `Call`, `ensureRoom`, return tokens, emit `call.incoming` + FCM |
| Get media creds | GET | `/:id/token` | Refresh mediasoup session + live roster |
| Join (server) | POST | `/:id/join` | Set `joinedAt`, promote RINGING→ACTIVE when callee answers |
| Announce identity | POST | `/:id/announce` | Broadcast `{ agoraUid, userName, userId }` for tile labels |
| Leave | POST | `/:id/leave` | Set `leftAt`, end call if last person |
| Decline | POST | `/:id/decline` | Callee rejects → MISSED |
| Mute | POST | `/:id/mute` | Persist + `call.participant.muted` |
| Buzzer | POST | `/:id/buzzer` | Emergency alert to other participants |
| History | GET | `/history` | Calls + meetings merged |

Meetings use **`/api/v1/meetings/:slug/token`** with room id `meet_{slug}` — same SFU flow.

---

## 7. Backend — roster, names, joined / left

### 7.1 Live roster serialization

```javascript
// backend/src/modules/calls/calls.service.js
function serializeLiveCallRoster(call) {
  return liveCallParticipants(call).map((p) => ({
    userId: p.userId,
    userName: p.user?.name || 'Participant',
    agoraUid: mediasoup.toMediaPeerId(p.userId),   // legacy field name
    mediaPeerId: mediasoup.toMediaPeerId(p.userId),
    joinedAt: p.joinedAt,
    leftAt: p.leftAt,
  }));
}
```

`mediaPeerId` is a stable numeric id derived from `userId` (hash if not numeric).

### 7.2 Join (server-side)

```javascript
// POST /calls/:id/join → calls.service.js join()
await prisma.callParticipant.update({
  where: { callId_userId: { callId, userId: user.id } },
  data: { leftAt: null, joinedAt: part.joinedAt || new Date() },
});
// 1:1: stay RINGING until callee (non-initiator) has joinedAt
// Then status → ACTIVE, startedAt set
```

Route handler then emits **`call.participant.joined`** with roster payload to all participants.

### 7.3 Leave / end

`leave()` sets participant `leftAt`. If 1:1 or last in group → `status: ENDED`, emits **`call.ended`** + FCM `call.ended`.

### 7.4 Announce (per-device name + uid)

After media join, client calls:

```http
POST /api/v1/calls/:id/announce
{ "agoraUid": 1234567890, "userName": "Priya K" }
```

Backend fans out **`call.announce`** so other tiles show the correct name and uid.

---

## 8. Backend Socket.IO events (MyTaskKing API)

Connection: JWT in `handshake.auth.token`. User joins room `user:{userId}`.

### Server → client (call state)

| Event | When | Key payload |
|-------|------|-------------|
| `call.incoming` | Ring callee | `callId`, `mode`, `fromName`, `callerId` |
| `call.participant.joined` | Someone joined server roster | `callId`, `userId`, `userName`, `agoraUid`, `participants[]` |
| `call.announce` | Client announced uid/name | `callId`, `agoraUid`, `userName`, `userId` |
| `call.participant.left` | Someone left | `callId`, `userId`, `status`, roster |
| `call.ended` | Call finished | `callId`, `status` |
| `call.declined` | Declined / missed | `callId`, `status` |
| `call.buzzer` | Emergency buzzer | `callId`, `fromName`, `audioUrl` |
| `call.participant.muted` | Mute changed | `callId`, `userId`, `muted` |
| `call.participants.updated` | Roster refresh | full participant list |
| `meeting.invited` | Meeting ring | `meetingSlug`, `mode`, `fromName` |
| `meeting.participant.joined` | Meeting join | roster |
| `meeting.participant.left` | Meeting leave | roster |
| `meeting.ended` | Host ended | `meetingSlug` |

### Client → server (in-call signals)

| Event | Purpose |
|-------|---------|
| `call.signal` | Relay `{ to, payload }` — mute, raise hand, etc. |
| `call.screenShare` | `{ callId, active, agoraUid }` |
| `call.videoEnabled` | Voice→video upgrade / camera off |
| `call.activeSpeaker` | Speaker highlight |
| `call.ringing.ack` | Callee acknowledged ring |

---

## 9. connect.mytaskking.com Socket.IO (WebRTC signaling only)

Connect: `io('https://connect.mytaskking.com/public', { transports: ['websocket'] })`

### Server → client

| Event | Payload |
|-------|---------|
| `config` | `{ iceServers: { iceServers: [...], iceCandidatePoolSize: 10 } }` |
| `newProducer` | `{ producerId, socketId, userName, kind: 'audio'\|'video' }` |
| `userJoined` | `{ socketId, userName, participantCount }` |
| `userLeft` | `{ socketId, participantCount }` |

### Client → server (with ack)

| Event | Request | Response |
|-------|---------|----------|
| `joinRoom` | `{ roomId, userName, joinToken? }` | `{ routerRtpCapabilities, existingProducers[] }` |
| `createWebRTCTransport` | `{ roomId, direction: 'send'\|'recv' }` | `{ params: { id, iceParameters, iceCandidates, dtlsParameters } }` |
| `connectTransport` | `{ roomId, transportId, dtlsParameters, direction }` | `{ success: true }` |
| `produce` | `{ roomId, transportId, kind, rtpParameters }` | `{ id: producerId }` |
| `consume` | `{ roomId, producerId, rtpCapabilities }` | consumer params |
| `resumeConsumer` | `{ consumerId }` | `{ success: true }` |

**Important:** SFU has **no resume after disconnect** — must `joinRoom` again and recreate transports.

---

## 10. Flutter — key files

| File | Role |
|------|------|
| `lib/screens/call_screen.dart` | Main call UI, bootstrap, socket listeners, hang up |
| `lib/calls/mediasoup_call_session.dart` | SFU WebRTC client |
| `lib/calls/mediasoup_video_view.dart` | Renders remote/local video |
| `lib/screens/incoming_call_overlay.dart` | Ring UI, accept/decline |
| `lib/active_call_state.dart` | Minimized call bubble state |
| `lib/screens/ongoing_call_bar.dart` | Return-to-call pill |
| `shared_core/lib/src/realtime.dart` | App Socket.IO (`BestieRealtime`) |
| `shared_core/lib/src/api.dart` | REST helpers |
| `lib/router.dart` | `/call/:id`, `/meeting/:slug` |

Dependencies (`pubspec.yaml`):

```yaml
flutter_webrtc: ...
mediasfu_mediasoup_client: ...
socket_io_client: ...
agora_rtc_engine: ...   # legacy fallback only
```

---

## 11. Flutter — step-by-step: outbound 1:1 call

### Step 1 — Initiate from chat

```dart
// Chat → api.initiateCall(participantIds, kind, mode)
// → POST /calls/initiate
// Response: { call: { id, channelName, ... }, tokens: { [userId]: { mediaEngine, connectUrl, ... } } }
context.go('/call/$callId?mode=voice');  // or video
```

### Step 2 — `CallScreen` mounts → `_bootstrap()`

File: `lib/screens/call_screen.dart`

1. Request mic (+ camera if video) + Bluetooth on Android  
2. `GET /calls/:id/token` (or meeting token)  
3. Read `mediaEngine` from response  

```dart
if (mediaEngine == 'mediasoup') {
  await _bootstrapMediasoup(tokenResp);
  return;
}
// else legacy Agora path
```

### Step 3 — `_bootstrapMediasoup()`

1. Read `connectUrl`, `roomId`, `mediaPeerId`, `joinToken`, `userName`  
2. Create `MediasoupCallSession(myMediaPeerId: deviceUid)`  
3. `session.connect(connectUrl, roomId, userName, video, joinToken)`  
4. `POST /calls/:id/join` with `{ agoraUid: mediaPeerId }`  
5. `POST /calls/:id/announce` with `{ agoraUid, userName }`  
6. `ActiveCallState.start(...)` for minimize bubble  

### Step 4 — `MediasoupCallSession.connect()`

File: `lib/calls/mediasoup_call_session.dart`

```
1. Open socket → wait for 'config' (ICE servers)
2. emitWithAck('joinRoom', { roomId, userName, joinToken })
3. Device.load(routerRtpCapabilities)
4. createWebRTCTransport direction=send → connectTransport → produce mic/cam
5. createWebRTCTransport direction=recv
6. consume existingProducers from joinRoom ack
7. listen 'newProducer' for late joiners
```

### Step 5 — Callee path

`IncomingCallOverlay` receives `call.incoming`:

```
1. Show full-screen ring (device default ringtone on receiver)
2. User taps Accept
3. GET /calls/:id/token
4. router.go('/call/$callId?mode=...')
5. Same _bootstrapMediasoup() as caller
```

FCM path when app killed: native `IncomingCallForegroundService` + push data `type: call.incoming`.

---

## 12. Flutter — how names, joined, and left work

There are **two parallel sources** of join/leave — both must be wired:

### A) Server roster (authoritative for "who is in the call")

| Socket event | Flutter handler | UI effect |
|--------------|-----------------|-----------|
| `call.participant.joined` | `onParticipantJoined` | Updates `_joinedParticipants`, stops ringback when callee answers |
| `call.announce` | `onAnnounce` | Maps `agoraUid` ↔ `userId`, sets `_remoteNames[uid]` |
| `call.participant.left` | leave handler | Removes peer; if `status: ENDED` → hang up UI |

Code reference — `call_screen.dart` `_subscribeCallLifecycle()`:

```dart
_callUnsubs.add(rt.onAny('call.participant.joined', onParticipantJoined));
_callUnsubs.add(rt.onAny('call.announce', onAnnounce));
_callUnsubs.add(rt.onAny('call.participant.left', ([data]) { ... }));
```

For mediasoup, `onAnnounce` calls:

```dart
_registerParticipantIdentity(userId, resolved, agoraUid: uid);
_bindRemoteUidName(uid, userId: userId, name: name);
```

This links **SFU socketId** (from media layer) to **server userId/name** (from API layer).

### B) SFU media layer (who is sending audio/video)

| SFU event | Callback | UI effect |
|-----------|----------|-----------|
| `userJoined` | `onRemoteJoined` | `_ensureMediasoupRemoteTracked(socketId, userName)` |
| `newProducer` | consume | Attach audio/video stream to tile |
| `userLeft` | `onRemoteLeft` | `_removeRemotePeerBySocket` — remove tile and streams |

Wired in `_wireMediasoupCallbacks()`:

```dart
session.onRemoteJoined = (socketId, userName) {
  _ensureMediasoupRemoteTracked(socketId, userName);
};
session.onRemoteLeft = (socketId, userName) {
  _removeRemotePeerBySocket(socketId, userName);
};
session.onRemoteStream = (socketId, stream, kind) { ... };
```

### Mapping table

| Concept | Field | Source |
|---------|-------|--------|
| DB user | `userId` | JWT / roster |
| Display name | `userName` | roster / announce / SFU userJoined |
| UI tile id | `agoraUid` / `mediaPeerId` | server token (legacy name kept) |
| SFU connection | `socketId` | connect.mytaskking after joinRoom |
| Bridge maps | `CallSession.uidToSocketId`, `agoraUidToUserId` | built in call_screen |

---

## 13. Flutter — mediasoup connect (core snippet)

From `lib/calls/mediasoup_call_session.dart`:

```dart
final socket = io.io(
  connectUrl,
  io.OptionBuilder()
      .setTransports(['websocket'])
      .enableForceNew()
      .enableReconnection()
      .build(),
);

socket.on('config', (data) {
  _applyIceFromConfig(data);  // STUN/TURN for WebRTC
});

socket.on('newProducer', (data) {
  _consumeRemoteProducer(
    producerId: data['producerId'],
    socketId: data['socketId'],
    userName: data['userName'],
  );
});

socket.on('userJoined', (data) {
  onRemoteJoined?.call(data['socketId'], data['userName']);
});

socket.on('userLeft', (data) {
  onRemoteLeft?.call(data['socketId'], remoteNames[data['socketId']]);
});

// After connect:
final joinResult = await _emitAck('joinRoom', {
  'roomId': roomId,
  'userName': userName,
  if (joinToken != null) 'joinToken': joinToken,
});
await _device!.load(routerRtpCapabilities: joinResult['routerRtpCapabilities']);
await _createTransports();
await _produceLocalMedia(video: video);
await _consumeExistingProducers(joinResult['existingProducers']);
```

---

## 14. Flutter — navigation and background call

| Route | Widget |
|-------|--------|
| `/call/:id?mode=voice\|video` | `CallScreen(callId: id)` |
| `/meeting/:slug?mode=...` | `CallScreen(meetingSlug: slug)` |

App shell (`main.dart`):

```
IncomingCallOverlay  → global ring + call.ended teardown
  └─ OngoingCallBar  → minimized bubble (ActiveCallState.route)
       └─ [current route]
```

`CallSession` is **static** — disposing `CallScreen` does not end the call. Only explicit hang up or `call.ended` runs `_CallSession.teardown()`.

Minimize: back button → `context.go('/chat')`, call keeps running, bubble shows.

---

## 15. FCM + org sounds (incoming ring)

On initiate, backend loads org settings:

```javascript
// calls.routes.js — loadOrgCallSettings()
// Keys: ringingSoundUrl, emergencyBuzzerSoundUrl, emergencyBuzzerEnabled
```

FCM data includes `ringingSoundUrl` when admin uploaded custom ring.

Flutter receiver uses **device default ringtone** unless org custom URL is set (`incoming_call_overlay.dart`).

Caller ringback uses bundled **Ringing.mp3** via `OrgCallSounds` (`lib/org_call_sounds.dart`).

---

## 16. Full sequence diagram — 1:1 answered call

```
Caller                          API                         connect.mytaskking          Callee
  |                              |                                |                        |
  | POST /calls/initiate         |                                |                        |
  |----------------------------->| POST /api/room { roomId }      |                        |
  |                              |------------------------------->|                        |
  |<-- tokens + callId ----------|                                |                        |
  |                              | socket call.incoming + FCM   |                        |
  |                              |-------------------------------|----------------------->|
  | go /call/:id                 |                                |                        | accept
  | GET /calls/:id/token         |                                |                        | GET /token
  | socket connect (SFU)         |                                |                        | SFU connect
  | joinRoom --------------------|--------------------------------|----------------------->| joinRoom
  | produce audio/video ---------|--------------------------------|----------------------->| produce
  | POST /join + /announce       |                                |                        | POST /join + /announce
  |                              | call.participant.joined ------>|----------------------->|
  |                              | call.announce ---------------->|----------------------->|
  |<-- newProducer/consume ------|--------------------------------|------------------------|
  |  (WebRTC media flows)        |                                |                        |
  | POST /leave                  |                                |                        |
  |                              | call.ended + FCM -------------->|----------------------->|
  | teardown                     |                                |                        | teardown
```

---

## 17. How to implement WebRTC calling in a new Flutter screen (checklist)

### Backend (already done in this project)

- [ ] Set `MEDIASOUP_CONNECT_API_URL` and `MEDIASOUP_SOCKET_URL` in `.env`
- [ ] Ensure connect.mytaskking.com is reachable from mobile networks
- [ ] Use `POST /calls/initiate` — never create SFU room from client alone for production calls

### Flutter — minimum integration

1. **REST:** `initiateCall` → navigate to `CallScreen` with `callId`
2. **Token:** `GET /calls/:id/token` → check `mediaEngine == 'mediasoup'`
3. **SFU:** Instantiate `MediasoupCallSession`, call `connect(connectUrl, roomId, userName, joinToken: ...)`
4. **Server join:** `POST /calls/:id/join` then `POST /calls/:id/announce`
5. **Sockets:** Subscribe `realtimeProvider` to `call.participant.joined`, `call.announce`, `call.participant.left`, `call.ended`
6. **UI:** Map `onRemoteJoined` / `onRemoteStream` to video tiles via `MediasoupVideoView`
7. **Teardown:** `POST /calls/:id/leave` + `session.disconnect()` on hang up
8. **Incoming:** Mount `IncomingCallOverlay` at app root; handle FCM `call.incoming`

### Copy-paste starting points in this repo

| Task | Start here |
|------|------------|
| Full call UI | `lib/screens/call_screen.dart` |
| WebRTC session | `lib/calls/mediasoup_call_session.dart` |
| Incoming ring | `lib/screens/incoming_call_overlay.dart` |
| API wrappers | `shared_core/lib/src/api.dart` → `initiateCall`, `joinCall`, `fetchCallToken` |
| Backend token | `backend/src/services/mediasoup.js` |
| SFU wire protocol | `calls.md` (repo root) |

---

## 18. Meetings vs 1:1 calls

| | 1:1 / Group Call | Meeting |
|--|------------------|---------|
| DB model | `Call` | `MeetingRoom` |
| Room id | `call_{nanoid}` | `meet_{slug}` |
| Token route | `GET /calls/:id/token` | `POST /meetings/:slug/token` |
| Ring event | `call.incoming` | `meeting.invited` |
| Join route | `POST /calls/:id/join` | roster via meeting token + heartbeat |
| Flutter route | `/call/:id` | `/meeting/:slug` |
| SFU flow | **Identical** mediasoup sequence | **Identical** |

---

## 19. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| "Mediasoup is not configured" | Missing env vars | Set `MEDIASOUP_CONNECT_API_URL`, `MEDIASOUP_SOCKET_URL` |
| No remote audio | Consumer not resumed | Ensure `resumeConsumer` + `consumer.resume()` in Flutter |
| Names wrong / duplicate tiles | announce not called or uid mismatch | Call `POST /announce` after join; check `mediaPeerId` |
| Joined on server but no media | SFU join failed | Check connect URL, TURN in `config` event logs |
| Callee never rings | Presence BUSY/AWAY | Backend suppresses ring; check presence status |
| Stuck on "Ringing" | Callee never POST /join | 60s timeout → MISSED via `expireStaleRingingCalls` job |
| Black video tile | Stream not bound | Use `MediasoupVideoView` with `Consumer.stream` directly |

Log tag in Flutter: `[mediasoup]` in `mediasoup_call_session.dart` (ICE summary, TURN warning).

---

## 20. Legacy Agora path (fallback only)

If `GET /calls/:id/token` returns **no** `mediaEngine: 'mediasoup'`, `call_screen.dart` falls back to:

- `appId`, `token`, `channelName`, `uid` from token response
- `agora_rtc_engine` `joinChannel()`
- Same server `POST /join` and `POST /announce` for roster

New deployments should use mediasoup only. Field names `agoraUid` remain for backward compatibility.

---

## 21. Related documentation in repo

| Doc | Content |
|-----|---------|
| `calls.md` | connect.mytaskking.com REST + socket API + Flutter samples |
| `docs/API.md` | General API (may still mention Agora — prefer this doc for calls) |
| `backend/src/modules/calls/calls.routes.js` | Source of truth for routes |
| `backend/src/services/mediasoup.js` | Token + room creation |

---

*Generated from MyTaskKing codebase — main branch commit `c53ec62` and earlier. SFU service: https://connect.mytaskking.com*
