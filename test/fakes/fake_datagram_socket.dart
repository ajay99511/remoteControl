import 'dart:async';
import 'dart:io';

/// A [RawDatagramSocket] the test drives.
///
/// Exists so the scanner's resource handling can be asserted without binding
/// a real UDP socket. The previous scanner test called startScan() for real,
/// which bound one.
class FakeDatagramSocket extends Stream<RawSocketEvent>
    implements RawDatagramSocket {
  final _events = StreamController<RawSocketEvent>();

  /// Payloads passed to [send], in order.
  final List<List<int>> sent = <List<int>>[];

  /// Datagrams [receive] will hand back, oldest first.
  final List<Datagram> inbox = <Datagram>[];

  bool closed = false;

  @override
  bool broadcastEnabled = false;

  /// Simulates an inbound datagram arriving on the socket.
  void deliver(Datagram datagram) {
    inbox.add(datagram);
    _events.add(RawSocketEvent.read);
  }

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  int send(List<int> buffer, InternetAddress address, int port) {
    sent.add(buffer);
    return buffer.length;
  }

  @override
  Datagram? receive() => inbox.isEmpty ? null : inbox.removeAt(0);

  @override
  void close() {
    closed = true;
    if (!_events.isClosed) _events.close();
  }

  // RawDatagramSocket has a wide surface the scanner never touches.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
