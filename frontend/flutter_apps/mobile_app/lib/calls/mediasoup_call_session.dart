import 'dart:async';

import 'package:mediasfu_mediasoup_client/mediasfu_mediasoup_client.dart';
// ignore: implementation_imports
import 'package:mediasfu_mediasoup_client/src/handlers/handler_interface.dart'
    show RTCIceCredentialType, RTCIceServer;
import 'package:socket_io_client/socket_io_client.dart' as io;

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
      await _openSocket(connectUrl);
      final joinResult = await _joinRoom(roomId, userName);
      await _loadDevice(joinResult);
      await _createTransports(roomId);
      await _produceLocalMedia(video: video);
      await _consumeExistingProducers(joinResult);
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

    for (final stream in remoteStreams.values) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
    remoteStreams.clear();
    remoteNames.clear();
    _consumedProducerIds.clear();
    _pendingConsumers.clear();
    _pendingProducers.clear();

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

    _notifyStateChanged();
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
    await Helper.setSpeakerphoneOn(enabled);
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
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video,
    });

    for (final track in localStream!.getAudioTracks()) {
      await _produceTrack(
        track: track,
        stream: localStream!,
        source: 'mic',
        onReady: (producer) => _audioProducer = producer,
      );
    }

    if (video) {
      for (final track in localStream!.getVideoTracks()) {
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

      await _emitAck('resumeConsumer', {'consumerId': consumer.id});

      if (userName != null && userName.isNotEmpty) {
        remoteNames[socketId] = userName;
      }
      final kind = data['kind']?.toString() ?? consumer.kind ?? 'audio';
      _attachRemoteStream(socketId, consumer.stream, kind);
    } catch (e) {
      _consumedProducerIds.remove(producerId);
      onError?.call(e);
    }
  }

  void _onConsumerReady(Consumer consumer, Function? accept) {
    accept?.call();
    final completer = _pendingConsumers.remove(consumer.producerId);
    completer?.complete(consumer);
  }

  void _attachRemoteStream(String socketId, MediaStream incoming, String kind) {
    final existing = remoteStreams[socketId];
    if (existing == null) {
      remoteStreams[socketId] = incoming;
      onRemoteStream?.call(socketId, incoming, kind);
      _notifyStateChanged();
      return;
    }

    if (existing.id == incoming.id) {
      onRemoteStream?.call(socketId, existing, kind);
      _notifyStateChanged();
      return;
    }

    for (final track in incoming.getTracks()) {
      existing.addTrack(track);
    }
    onRemoteStream?.call(socketId, existing, kind);
    _notifyStateChanged();
  }

  void _removeRemoteParticipant(String socketId) {
    remoteNames.remove(socketId);
    final stream = remoteStreams.remove(socketId);
    if (stream != null) {
      unawaited(() async {
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        await stream.dispose();
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
    if (configData == null) return const [];

    dynamic nested = configData['iceServers'];
    List<dynamic> servers;
    if (nested is Map && nested['iceServers'] is List) {
      servers = nested['iceServers'] as List;
    } else if (nested is List) {
      servers = nested;
    } else {
      return const [];
    }

    return servers.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final urls = m['urls'];
      return RTCIceServer(
        urls: urls is List
            ? urls.map((u) => u.toString()).toList()
            : [urls.toString()],
        username: m['username']?.toString() ?? '',
        credential: m['credential']?.toString(),
        credentialType: RTCIceCredentialType.password,
      );
    }).toList();
  }

  void _notifyStateChanged() => onStateChanged?.call();
}
