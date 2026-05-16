import 'package:bestie_core/bestie_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kApiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:4000',
);
const kSocketUrl = String.fromEnvironment(
  'SOCKET_URL',
  defaultValue: 'http://localhost:4000',
);

final authStoreProvider = Provider<BestieAuthStore>((_) => throw UnimplementedError());

final apiProvider = Provider<BestieApi>((ref) {
  return BestieApi(baseUrl: kApiBaseUrl, auth: ref.watch(authStoreProvider));
});

final socketProvider = Provider<BestieSocket>((ref) {
  return BestieSocket(url: kSocketUrl, auth: ref.watch(authStoreProvider));
});
