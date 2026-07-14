import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mediasfu_mediasoup_client/mediasfu_mediasoup_client.dart';
// ignore: implementation_imports
import 'package:mediasfu_mediasoup_client/src/handlers/handler_interface.dart'
    show RTCIceCredentialType, RTCIceServer;
import 'package:socket_io_client/socket_io_client.dart' as io;

final List<RTCIceServer> _googleStunFallback = [
  RTCIceServer(
    urls: ['stun:stun.l.google.com:19302'],
    username: '',
    credentialType: RTCIceCredentialType.password,
  ),
  RTCIceServer(
    urls: ['stun:stun1.l.google.com:19302'],
    username: '',
    credentialType: RTCIceCredentialType.password,
  ),
];

/// Mediasoup SFU call session for MyTaskKing mobile (connect.mytaskking.com).
///
/// Follows the signaling flow in [calls.md]: config → joinRoom → Device.load →
/// send/recv transports → produce/consume → newProducer / userJoined / userLeft.
///
/// The server has no reconnection/resume logic — [disconnect] tears everything
/// down and the caller must [connect] again from scratch.
class MediasoupCallSession {
  MediasoupCallSession({this.myMediaPeerId});

  // --- Public state ---

  bool joined = false;
  MediaStream? localStream;
  final Map<String, MediaStream> remoteStreams = {};
  final Map<String, String> remoteNames = {};
  String? mySocketId;
  int? myMediaPeerId;

  // --- Callbacks ---

  void Function(String socketId, String userName)? onRemoteJoined;
  void Function(String socketId)? onRemoteLeft;
  /// [kind] is `audio` or `video` from the SFU consumer.
  void Function(String socketId, MediaStream stream, String kind)? onRemoteStream;
  void Function()? onStateChanged;
  void Function(Object error)? onError;

  // --- Internals ---

  io.Socket? _socket;
  Device? _device;
  Transport? _sendTransport;
  Transport? _recvTransport;

  String? _roomId;
  bool _videoEnabled = false;
  bool _muted = false;
  bool _cameraEnabled = true;
  bool _connecting = false;
  bool _screenSharing = false;

  Map<String, dynamic>? _iceConfig;
  List<RTCIceServer> _iceServers = [];

  Producer? _audioProducer;
  Producer? _videoProducer;
  Producer? _screenProducer;
  MediaStream? _screenStream;

  final Set<String> _consumedProducerIds = {};
  final Map<String, Completer<Consumer>> _pendingConsumers = {};
  final Map<String, Completer<Producer>> _pendingProducers = {};
  /// Live consumers — need client-side [Consumer.resume] after server
  /// `resumeConsumer` (MediaSFU / mediasoup-client pattern; HTML JS also
  /// enables the track before play).
  final Map<String, Consumer> _consumersByProducerId = {};

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> connect({
    required String connectUrl,
    required String roomId,
    required String userName,
    bool video = false,
  }) async {
    if (_connecting) {
      throw StateError('connect() already in progress');
    }
    if (joined) {
      throw StateError('already connected — call disconnect() first');
    }

    _connecting = true;
    _roomId = roomId;
    _videoEnabled = video;
    _cameraEnabled = video;
    _muted = false;

    try {
      await _configurePlatformAudioForCall(video: video);
      await _openSocket(connectUrl);
      final joinResult = await _joinRoom(roomId, userName);
      await _loadDevice(joinResult);
      await _createTransports(roomId);
      await _produceLocalMedia(video: video);
      await _consumeExistingProducers(joinResult);
      // Match HTML: media is live — force playout path again after first
      // produce/consume (ADM often only binds after getUserMedia).
      await enableRemotePlayback();
      if (video) {
        try {
          await Helper.setSpeakerphoneOnButPreferBluetooth();
        } catch (_) {
          await Helper.setSpeakerphoneOn(true);
        }
      }
      joined = true;
      _notifyStateChanged();
    } catch (e) {
      await disconnect();
      onError?.call(e);
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  Future<void> disconnect() async {
    joined = false;
    _connecting = false;

    _audioProducer?.close();
    _videoProducer?.close();
    _screenProducer?.close();
    _audioProducer = null;
    _videoProducer = null;
    _screenProducer = null;

    await _stopScreenShareInternal(notify: false);

    for (final c in _consumersByProducerId.values) {
      try {
        await c.close();
      } catch (_) {}
    }
    _consumersByProducerId.clear();
    _consumedProducerIds.clear();
    _pendingConsumers.clear();
    _pendingProducers.clear();

    // Peer streams only aggregate consumer tracks — don't stop tracks here.
    for (final stream in remoteStreams.values) {
      try {
        await stream.dispose();
      } catch (_) {}
    }
    remoteStreams.clear();
    remoteNames.clear();

    if (localStream != null) {
      for (final track in localStream!.getTracks()) {
        await track.stop();
      }
      await localStream!.dispose();
      localStream = null;
    }

    await _sendTransport?.close();
    await _recvTransport?.close();
    _sendTransport = null;
    _recvTransport = null;
    _device = null;

    _socket?.dispose();
    _socket = null;
    mySocketId = null;
    _roomId = null;
    _iceConfig = null;
    _iceServers = [];

    if (Platform.isAndroid) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (_) {}
    }

    _notifyStateChanged();
  }

  /// Must run before getUserMedia / transports — otherwise Android/iOS route
  /// remote voice to a dormant ADM / wrong stream (silent-call symptom).
  /// Patterns from flutter_webrtc#1772 / #1032 + MediaSFU consumerResume.
  Future<void> _configurePlatformAudioForCall({required bool video}) async {
    try {
      if (WebRTC.platformIsAndroid) {
        final androidConfig = AndroidAudioConfiguration(
          manageAudioFocus: true,
          androidAudioMode: AndroidAudioMode.inCommunication,
          androidAudioFocusMode: AndroidAudioFocusMode.gain,
          androidAudioStreamType: AndroidAudioStreamType.voiceCall,
          androidAudioAttributesUsageType:
              AndroidAudioAttributesUsageType.voiceCommunication,
          androidAudioAttributesContentType:
              AndroidAudioAttributesContentType.speech,
        );
        try {
          await WebRTC.initialize(options: {
            'androidAudioConfiguration': androidConfig.toMap(),
          });
        } catch (_) {
          // Already initialized for this process — re-apply via Helper.
        }
        await Helper.setAndroidAudioConfiguration(androidConfig);
      } else if (WebRTC.platformIsIOS) {
        await Helper.setAppleAudioConfiguration(
          AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playAndRecord,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.allowBluetooth,
              AppleAudioCategoryOption.mixWithOthers,
              if (video) AppleAudioCategoryOption.defaultToSpeaker,
            },
            // videoChat unlocks louder speaker path; voiceChat for earpiece VoIP.
            appleAudioMode:
                video ? AppleAudioMode.videoChat : AppleAudioMode.voiceChat,
          ),
        );
        await Helper.ensureAudioSession();
      }

      // Speaker for video; for voice leave earpiece until CallScreen sets route.
      // Prefer Bluetooth when a headset is connected (flutter_webrtc guidance).
      if (video) {
        try {
          await Helper.setSpeakerphoneOnButPreferBluetooth();
        } catch (_) {
          await Helper.setSpeakerphoneOn(true);
        }
      }
    } catch (_) {}
  }

  Future<void> enableRemotePlayback() async {
    for (final consumer in _consumersByProducerId.values) {
      try {
        consumer.resume();
        consumer.track.enabled = true;
      } catch (_) {}
    }
    for (final stream in remoteStreams.values) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = true;
        try {
          await Helper.setVolume(1.0, track);
        } catch (_) {}
      }
      for (final track in stream.getVideoTracks()) {
        track.enabled = true;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Media controls
  // ---------------------------------------------------------------------------

  bool get isMuted => _muted;
  bool get isCameraEnabled => _cameraEnabled;
  bool get isVideoCall => _videoEnabled;
  bool get isScreenSharing => _screenSharing;
  MediaStream? get screenStream => _screenStream;

  void setMuted(bool muted) {
    _muted = muted;
    final audioTracks = localStream?.getAudioTracks() ?? [];
    for (final track in audioTracks) {
      track.enabled = !muted;
    }
    if (muted) {
      _audioProducer?.pause();
    } else {
      _audioProducer?.resume();
    }
    _notifyStateChanged();
  }

  void setCameraEnabled(bool enabled) {
    _cameraEnabled = enabled;
    final videoTracks = localStream?.getVideoTracks() ?? [];
    for (final track in videoTracks) {
      track.enabled = enabled;
    }
    if (enabled) {
      _videoProducer?.resume();
    } else {
      _videoProducer?.pause();
    }
    _notifyStateChanged();
  }

  Future<void> setSpeakerphone(bool enabled) async {
    if (enabled) {
      try {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
      } catch (_) {
        await Helper.setSpeakerphoneOn(true);
      }
    } else {
      await Helper.setSpeakerphoneOn(false);
    }
    // Re-enable remote tracks after route flips (Android often mutes briefly).
    await enableRemotePlayback();
    _notifyStateChanged();
  }

  Future<void> startScreenShare() async {
    if (_sendTransport == null || joined == false) {
      throw StateError('not connected');
    }
    if (_screenSharing) return;

    _screenStream = await navigator.mediaDevices.getDisplayMedia({
      'video': true,
      'audio': false,
    });
    final tracks = _screenStream!.getVideoTracks();
    if (tracks.isEmpty) {
      await _screenStream!.dispose();
      _screenStream = null;
      throw StateError('screen share produced no video track');
    }

    await _produceTrack(
      track: tracks.first,
      stream: _screenStream!,
      source: 'screen',
      onReady: (producer) => _screenProducer = producer,
    );
    _screenSharing = true;
    _notifyStateChanged();
  }

  Future<void> stopScreenShare() async {
    await _stopScreenShareInternal(notify: true);
  }

  // ---------------------------------------------------------------------------
  // Socket + signaling
  // ---------------------------------------------------------------------------

  Future<void> _openSocket(String connectUrl) async {
    final configCompleter = Completer<Map<String, dynamic>>();
    final connectCompleter = Completer<void>();

    final socket = io.io(
      connectUrl,
      io.OptionBuilder().setTransports(['websocket']).enableForceNew().build(),
    );
    _socket = socket;

    socket.on('config', (dynamic data) {
      if (data is Map) {
        _iceConfig = Map<String, dynamic>.from(data);
        _iceServers = _parseIceServers(_iceConfig);
        if (!configCompleter.isCompleted) {
          configCompleter.complete(_iceConfig!);
        }
      }
    });

    socket.on('newProducer', (dynamic data) {
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final producerId = map['producerId']?.toString();
      final socketId = map['socketId']?.toString();
      final name = map['userName']?.toString();
      if (producerId == null || socketId == null) return;
      if (name != null && name.isNotEmpty) {
        remoteNames[socketId] = name;
      }
      unawaited(_consumeRemoteProducer(
        producerId: producerId,
        socketId: socketId,
        userName: name,
      ));
    });

    socket.on('userJoined', (dynamic data) {
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final socketId = map['socketId']?.toString();
      final name = map['userName']?.toString() ?? 'Participant';
      if (socketId == null || socketId == mySocketId) return;
      remoteNames[socketId] = name;
      onRemoteJoined?.call(socketId, name);
      _notifyStateChanged();
    });

    socket.on('userLeft', (dynamic data) {
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final socketId = map['socketId']?.toString();
      if (socketId == null) return;
      _removeRemoteParticipant(socketId);
      onRemoteLeft?.call(socketId);
      _notifyStateChanged();
    });

    socket.onDisconnect((_) {
      if (joined || _connecting) {
        unawaited(disconnect());
        onError?.call('Socket disconnected — rejoin required');
      }
    });

    socket.onConnect((_) {
      mySocketId = socket.id;
      if (!connectCompleter.isCompleted) {
        connectCompleter.complete();
      }
    });

    socket.onConnectError((dynamic err) {
      if (!connectCompleter.isCompleted) {
        connectCompleter.completeError(err ?? 'connect error');
      }
    });

    await connectCompleter.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('socket connect timed out'),
    );

    await configCompleter.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('config event timed out'),
    );
  }

  Future<Map<String, dynamic>> _joinRoom(String roomId, String userName) async {
    final result = await _emitAck('joinRoom', {
      'roomId': roomId,
      'userName': userName,
    });
    if (result['success'] != true) {
      throw result['error'] ?? 'joinRoom failed';
    }
    return result;
  }

  Future<void> _loadDevice(Map<String, dynamic> joinResult) async {
    final caps = joinResult['routerRtpCapabilities'];
    if (caps is! Map) {
      throw StateError('joinRoom missing routerRtpCapabilities');
    }
    final device = Device();
    await device.load(
      routerRtpCapabilities: RtpCapabilities.fromMap(
        Map<String, dynamic>.from(caps),
      ),
    );
    _device = device;
  }

  Future<void> _createTransports(String roomId) async {
    final device = _device!;
    _sendTransport = await _createSendTransport(device, roomId);
    _recvTransport = await _createRecvTransport(device, roomId);
  }

  Future<Transport> _createSendTransport(Device device, String roomId) async {
    final res = await _emitAck('createWebRTCTransport', {
      'roomId': roomId,
      'direction': 'send',
    });
    if (res['error'] != null) throw res['error'];
    final params = Map<String, dynamic>.from(res['params'] as Map);

    final transport = device.createSendTransport(
      id: params['id'].toString(),
      iceParameters: IceParameters.fromMap(params['iceParameters']),
      iceCandidates: (params['iceCandidates'] as List)
          .map((c) => IceCandidate.fromMap(Map<String, dynamic>.from(c as Map)))
          .toList(),
      dtlsParameters: DtlsParameters.fromMap(params['dtlsParameters']),
      iceServers: _iceServers,
      producerCallback: _onProducerReady,
    );

    transport.on('connect', (Map data) async {
      try {
        final dtls = data['dtlsParameters'] as DtlsParameters;
        final ack = await _emitAck('connectTransport', {
          'roomId': roomId,
          'transportId': transport.id,
          'dtlsParameters': dtls.toMap(),
          'direction': 'send',
        });
        if (ack['error'] != null) {
          data['errback'](ack['error']);
          return;
        }
        data['callback']();
      } catch (e) {
        data['errback'](e);
      }
    });

    transport.on('produce', (Map data) async {
      try {
        final rtp = data['rtpParameters'] as RtpParameters;
        final ack = await _emitAck('produce', {
          'roomId': roomId,
          'transportId': transport.id,
          'kind': data['kind'],
          'rtpParameters': rtp.toMap(),
        });
        if (ack['error'] != null) {
          data['errback'](ack['error']);
          return;
        }
        data['callback'](ack['id']);
      } catch (e) {
        data['errback'](e);
      }
    });

    return transport;
  }

  Future<Transport> _createRecvTransport(Device device, String roomId) async {
    final res = await _emitAck('createWebRTCTransport', {
      'roomId': roomId,
      'direction': 'recv',
    });
    if (res['error'] != null) throw res['error'];
    final params = Map<String, dynamic>.from(res['params'] as Map);

    final transport = device.createRecvTransport(
      id: params['id'].toString(),
      iceParameters: IceParameters.fromMap(params['iceParameters']),
      iceCandidates: (params['iceCandidates'] as List)
          .map((c) => IceCandidate.fromMap(Map<String, dynamic>.from(c as Map)))
          .toList(),
      dtlsParameters: DtlsParameters.fromMap(params['dtlsParameters']),
      iceServers: _iceServers,
      consumerCallback: _onConsumerReady,
    );

    transport.on('connect', (Map data) async {
      try {
        final dtls = data['dtlsParameters'] as DtlsParameters;
        final ack = await _emitAck('connectTransport', {
          'roomId': roomId,
          'transportId': transport.id,
          'dtlsParameters': dtls.toMap(),
          'direction': 'recv',
        });
        if (ack['error'] != null) {
          data['errback'](ack['error']);
          return;
        }
        data['callback']();
      } catch (e) {
        data['errback'](e);
      }
    });

    return transport;
  }

  // ---------------------------------------------------------------------------
  // Produce / consume
  // ---------------------------------------------------------------------------

  Future<void> _produceLocalMedia({required bool video}) async {
    // Explicit AEC/NS like proven flutter_webrtc call setups; fall back if
    // the device rejects constraint maps.
    try {
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': video,
      });
    } catch (_) {
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video,
      });
    }

    for (final track in localStream!.getAudioTracks()) {
      track.enabled = true;
      await _produceTrack(
        track: track,
        stream: localStream!,
        source: 'mic',
        onReady: (producer) => _audioProducer = producer,
      );
    }

    if (video) {
      for (final track in localStream!.getVideoTracks()) {
        track.enabled = true;
        await _produceTrack(
          track: track,
          stream: localStream!,
          source: 'webcam',
          onReady: (producer) => _videoProducer = producer,
        );
      }
    }
  }

  Future<void> _produceTrack({
    required MediaStreamTrack track,
    required MediaStream stream,
    required String source,
    void Function(Producer producer)? onReady,
  }) async {
    final transport = _sendTransport;
    if (transport == null) throw StateError('send transport not ready');

    final completer = Completer<Producer>();
    _pendingProducers[track.id ?? source] = completer;

    transport.produce(
      track: track,
      stream: stream,
      source: source,
      stopTracks: false,
    );

    final producer = await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException('produce timed out ($source)'),
    );
    onReady?.call(producer);
  }

  void _onProducerReady(Producer producer) {
    final key = producer.track.id ?? producer.source;
    final completer = _pendingProducers.remove(key);
    completer?.complete(producer);

    if (producer.kind == 'audio' && _audioProducer == null) {
      _audioProducer = producer;
    } else if (producer.source == 'screen') {
      _screenProducer = producer;
    } else if (producer.kind == 'video' && _videoProducer == null) {
      _videoProducer = producer;
    }
  }

  Future<void> _consumeExistingProducers(Map<String, dynamic> joinResult) async {
    final existing = joinResult['existingProducers'];
    if (existing is! List) return;
    final seenSockets = <String>{};
    for (final raw in existing) {
      if (raw is! Map) continue;
      final p = Map<String, dynamic>.from(raw);
      final producerId = p['producerId']?.toString();
      final socketId = p['socketId']?.toString();
      final name = p['userName']?.toString();
      if (producerId == null || socketId == null) continue;
      if (socketId != mySocketId && seenSockets.add(socketId)) {
        final resolved = (name != null && name.isNotEmpty)
            ? name
            : (remoteNames[socketId] ?? 'Participant');
        remoteNames[socketId] = resolved;
        onRemoteJoined?.call(socketId, resolved);
      }
      await _consumeRemoteProducer(
        producerId: producerId,
        socketId: socketId,
        userName: name,
      );
    }
  }

  Future<void> _consumeRemoteProducer({
    required String producerId,
    required String socketId,
    String? userName,
  }) async {
    if (socketId == mySocketId) return;
    if (_consumedProducerIds.contains(producerId)) return;
    _consumedProducerIds.add(producerId);

    final device = _device;
    final recvTransport = _recvTransport;
    final roomId = _roomId;
    if (device == null || recvTransport == null || roomId == null) return;

    try {
      final data = await _emitAck('consume', {
        'roomId': roomId,
        'producerId': producerId,
        'rtpCapabilities': device.rtpCapabilities.toMap(),
      });
      if (data['error'] != null) {
        _consumedProducerIds.remove(producerId);
        onError?.call(data['error']);
        return;
      }

      final completer = Completer<Consumer>();
      _pendingConsumers[producerId] = completer;

      recvTransport.consume(
        id: data['id'].toString(),
        producerId: data['producerId'].toString(),
        peerId: socketId,
        kind: RTCRtpMediaTypeExtension.fromString(data['kind'].toString()),
        rtpParameters: RtpParameters.fromMap(
          Map<String, dynamic>.from(data['rtpParameters'] as Map),
        ),
      );

      final consumer = await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('consume timed out'),
      );

      _consumersByProducerId[producerId] = consumer;

      // Server must unpause first (calls.md / HTML), then client Consumer.resume
      // enables the local MediaStreamTrack (MediaSFU consumerResume pattern).
      await _emitAck('resumeConsumer', {'consumerId': consumer.id});
      consumer.resume();
      consumer.track.enabled = true;

      if (userName != null && userName.isNotEmpty) {
        remoteNames[socketId] = userName;
      }
      final kind = data['kind']?.toString() ?? consumer.kind ?? 'audio';
      // HTML does: el.srcObject = new MediaStream(); el.srcObject.addTrack(track)
      await _attachRemoteTrack(socketId, consumer.track, kind);
      await enableRemotePlayback();
      // Android ADM sometimes binds a tick after tracks appear.
      Future<void>.delayed(const Duration(milliseconds: 300), () async {
        await enableRemotePlayback();
      });
    } catch (e) {
      _consumedProducerIds.remove(producerId);
      _consumersByProducerId.remove(producerId);
      onError?.call(e);
    }
  }

  void _onConsumerReady(Consumer consumer, Function? accept) {
    accept?.call();
    final completer = _pendingConsumers.remove(consumer.producerId);
    completer?.complete(consumer);
  }

  /// One MediaStream per remote peer (same as the HTML test's video element).
  Future<void> _attachRemoteTrack(
    String socketId,
    MediaStreamTrack track,
    String kind,
  ) async {
    track.enabled = true;

    var peerStream = remoteStreams[socketId];
    if (peerStream == null) {
      peerStream = await createLocalMediaStream('remote-$socketId');
      remoteStreams[socketId] = peerStream;
    }

    final already = peerStream.getTracks().any((t) => t.id == track.id);
    if (!already) {
      await peerStream.addTrack(track);
    }

    onRemoteStream?.call(socketId, peerStream, kind);
    _notifyStateChanged();
  }

  void _removeRemoteParticipant(String socketId) {
    remoteNames.remove(socketId);

    final toClose = <String>[];
    for (final entry in _consumersByProducerId.entries) {
      if (entry.value.peerId == socketId) {
        toClose.add(entry.key);
      }
    }
    for (final producerId in toClose) {
      final c = _consumersByProducerId.remove(producerId);
      _consumedProducerIds.remove(producerId);
      try {
        unawaited(c?.close() ?? Future.value());
      } catch (_) {}
    }

    final stream = remoteStreams.remove(socketId);
    if (stream != null) {
      unawaited(() async {
        // Tracks belong to consumers — don't stop them here; closing the
        // consumer tears them down. Just drop our peer aggregator stream.
        try {
          await stream.dispose();
        } catch (_) {}
      }());
    }
  }

  Future<void> _stopScreenShareInternal({required bool notify}) async {
    if (!_screenSharing && _screenProducer == null && _screenStream == null) {
      return;
    }

    _screenProducer?.close();
    _screenProducer = null;
    _screenSharing = false;

    if (_screenStream != null) {
      for (final track in _screenStream!.getTracks()) {
        await track.stop();
      }
      await _screenStream!.dispose();
      _screenStream = null;
    }

    if (notify) _notifyStateChanged();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _emitAck(
    String event,
    Map<String, dynamic> payload,
  ) async {
    final socket = _socket;
    if (socket == null) throw StateError('socket not connected');

    final completer = Completer<Map<String, dynamic>>();
    socket.emitWithAck(event, payload, ack: (dynamic data) {
      if (data is Map) {
        completer.complete(Map<String, dynamic>.from(data));
      } else {
        completer.complete(<String, dynamic>{'success': data});
      }
    });
    return completer.future;
  }

  List<RTCIceServer> _parseIceServers(Map<String, dynamic>? configData) {
    final googleStun = _googleStunFallback;

    if (configData == null) return googleStun;

    dynamic nested = configData['iceServers'];
    List<dynamic> servers;
    if (nested is Map && nested['iceServers'] is List) {
      servers = nested['iceServers'] as List;
    } else if (nested is List) {
      servers = nested;
    } else {
      return googleStun;
    }

    if (servers.isEmpty) return googleStun;

    final parsed = servers.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final urls = m['urls'];
      if (urls == null) return null;
      final urlList = urls is List
          ? urls.map((u) => u.toString()).where((u) => u.isNotEmpty).toList()
          : [urls.toString()];
      if (urlList.isEmpty) return null;
      return RTCIceServer(
        urls: urlList,
        username: m['username']?.toString() ?? '',
        credential: m['credential']?.toString(),
        credentialType: RTCIceCredentialType.password,
      );
    }).whereType<RTCIceServer>().toList();

    if (parsed.isEmpty) return googleStun;

    final hasStun = parsed.any((s) {
      final urls = s.urls;
      if (urls is List) {
        return urls.any((u) => u.toString().startsWith('stun:'));
      }
      return urls.toString().startsWith('stun:');
    });
    if (!hasStun) return [...parsed, ...googleStun];
    return parsed;
  }

  void _notifyStateChanged() => onStateChanged?.call();
}
