import Foundation
import Network

public enum LocalTransferEvent:Sendable {
  case progress(name:String,received:Int64,total:Int64)
  case fileReceived(String)
  case complete([URL])
  case failed(String)
}

/// One explicitly started receive session. No discovery, outgoing connection, or always-on server.
public final class LocalTransferServer:@unchecked Sendable {
  public let token = UUID().uuidString+UUID().uuidString
  private let queue = DispatchQueue(label:"org.openracerender.receive")
  private var listener:NWListener?
  private var store:TransferStore?
  private var clients:[UUID:Client] = [:]
  private let event:@Sendable (LocalTransferEvent)->Void
  private var stopped = false
  private struct Client {
    var connection:NWConnection
    var buffer = Data()
    var head:TransferHTTPHead?
    var written:Int64 = 0
    var response = false
    var timeout:DispatchWorkItem?
    var lastProgress:TimeInterval = 0
  }
  public init(event:@escaping @Sendable (LocalTransferEvent)->Void) {self.event = event}
  public func start(destination:URL,loopbackOnly:Bool = false) async throws -> UInt16 {
    try await withCheckedThrowingContinuation {continuation in
      queue.async {
        guard self.listener == nil,!self.stopped else {continuation.resume(throwing:RaceError.invalid("Start a new receiving session."));return}
        do {
          let store = try TransferStore(destination:destination),parameters = NWParameters.tcp
          self.store = store
          if loopbackOnly {parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)}
          let listener = try NWListener(using:parameters,on:.any);self.listener = listener
          var resumed = false
          listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
              if !resumed,let port = listener.port {resumed = true;continuation.resume(returning:port.rawValue)}
            case .failed(let error),.waiting(let error):
              if !resumed {resumed = true;continuation.resume(throwing:error)}
              self?.event(.failed(error.localizedDescription));self?.stopOnQueue()
            case .cancelled:
              listener.stateUpdateHandler = nil
              if !resumed {resumed = true;continuation.resume(throwing:CancellationError())}
            default:break
            }
          }
          listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
          listener.start(queue:self.queue)
        } catch {self.store?.cancel();self.store = nil;continuation.resume(throwing:error)}
      }
    }
  }
  public func stop() {queue.async {self.stopOnQueue()}}
  private func stopOnQueue() {
    stopped = true;listener?.cancel();listener = nil
    for id in Array(clients.keys) {close(id)}
    store?.cancel();store = nil
  }
  private func accept(_ connection:NWConnection) {
    guard !stopped,clients.count < 4 else {connection.cancel();return}
    let id = UUID();clients[id] = Client(connection:connection)
    connection.stateUpdateHandler = {[weak self] state in if case .failed = state {self?.close(id)}}
    connection.start(queue:queue);receive(id)
  }
  private func close(_ id:UUID) {
    guard let client = clients.removeValue(forKey:id) else {return}
    client.timeout?.cancel();client.connection.cancel();store?.abort(id)
  }
  private func receive(_ id:UUID) {
    guard let client = clients[id],!client.response else {return}
    client.timeout?.cancel()
    let timeout = DispatchWorkItem {[weak self] in self?.close(id)};clients[id]?.timeout = timeout
    queue.asyncAfter(deadline:.now()+60,execute:timeout)
    client.connection.receive(minimumIncompleteLength:1,maximumLength:65_536) {[weak self] data,_,complete,error in
      guard let self,self.clients[id] != nil else {return}
      do {
        if let data,!data.isEmpty {try self.consume(data,id:id)}
        guard let remaining = self.clients[id],!remaining.response else {return}
        if error != nil || complete {self.close(id)} else {self.receive(id)}
      } catch {self.store?.abort(id);self.respond(id,status:400,body:Data(error.localizedDescription.utf8))}
    }
  }
  private func consume(_ incoming:Data,id:UUID) throws {
    guard var client = clients[id],let store else {return}
    var body = incoming
    if client.head == nil {
      client.buffer.append(incoming)
      guard let boundary = client.buffer.range(of:TransferHTTPHead.delimiter) else {
        guard client.buffer.count <= 16_384 else {throw RaceError.invalid("HTTP header too large.")}
        clients[id] = client;return
      }
      let head = try TransferHTTPHead.parse(Data(client.buffer[..<boundary.lowerBound]),token:token)
      body = Data(client.buffer[boundary.upperBound...]);client.buffer = Data();client.head = head;clients[id] = client
      if head.method == "GET" {
        guard body.isEmpty else {throw RaceError.invalid("Unexpected request body.")}
        respond(id,status:200,body:Data(LocalTransferPage.html.utf8),html:true);return
      }
      if head.method == "POST" {
        guard body.isEmpty else {throw RaceError.invalid("Unexpected request body.")}
        let files = try store.commit()
        respond(id,status:200,body:Data("Complete".utf8)) { [weak self] in
          self?.event(.complete(files));self?.stopOnQueue()
        }
        return
      }
      try store.begin(head.name!,size:head.length,id:id)
    }
    guard let head = client.head else {return}
    if !body.isEmpty {
      let progress = try store.write(body,id:id);client.written = progress.0
      let now = Date.timeIntervalSinceReferenceDate
      if now-client.lastProgress > 0.1 || progress.0 == progress.1 {
        event(.progress(name:head.name!,received:progress.0,total:progress.1));client.lastProgress = now
      }
      clients[id] = client
    }
    if client.written == head.length {
      try store.finishFile(id);event(.fileReceived(head.name!));respond(id,status:200,body:Data("Received".utf8))
    }
  }
  private func respond(_ id:UUID,status:Int,body:Data,html:Bool = false,completion:(()->Void)? = nil) {
    guard let client = clients[id],!client.response else {return}
    clients[id]?.response = true;client.timeout?.cancel()
    let type = html ? "text/html; charset=utf-8" : "text/plain; charset=utf-8"
    let header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Bad Request")\r\nContent-Length: \(body.count)\r\nContent-Type: \(type)\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'\r\n\r\n"
    client.connection.send(content:Data(header.utf8)+body,completion:.contentProcessed {[weak self] _ in self?.close(id);completion?()})
  }
}
