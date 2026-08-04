import 'dart:io';

const String defaultSyncPlayEndPoint = 'www.rusye.com:8998';

const officialSyncPlayEndPoints = <String>{defaultSyncPlayEndPoint};

class SyncPlayEndPoint {
  const SyncPlayEndPoint({required this.host, required this.port});

  final String host;
  final int port;
}

SyncPlayEndPoint? parseSyncPlayEndPoint(String endPoint) {
  final input = endPoint.trim();
  if (input.isEmpty) {
    return null;
  }

  String host;
  String portStr;

  if (input.startsWith('[')) {
    final closeIndex = input.indexOf(']');
    if (closeIndex == -1) {
      return null;
    }
    host = input.substring(1, closeIndex).trim();
    final rest = input.substring(closeIndex + 1);
    if (!rest.startsWith(':')) {
      return null;
    }
    portStr = rest.substring(1).trim();
  } else {
    final lastColonIndex = input.lastIndexOf(':');
    if (lastColonIndex == -1) {
      return null;
    }
    host = input.substring(0, lastColonIndex).trim();
    portStr = input.substring(lastColonIndex + 1).trim();
  }

  if (host.isEmpty || portStr.isEmpty) {
    return null;
  }

  final port = int.tryParse(portStr);
  if (port == null || port <= 0 || port > 65535) {
    return null;
  }

  return SyncPlayEndPoint(host: host, port: port);
}

bool isOfficialSyncPlayEndPoint(SyncPlayEndPoint endPoint) {
  final normalized = '${endPoint.host.toLowerCase()}:${endPoint.port}';
  return officialSyncPlayEndPoints.contains(normalized);
}
