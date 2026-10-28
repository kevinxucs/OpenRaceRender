import Foundation
import Network

/// Temporary loopback-only OAuth callback. Authorization codes never pass through a remote relay.
public final class GoogleOAuthCallback:@unchecked Sendable {
  private let queue = DispatchQueue(label:"org.openracerender.google-oauth")
  private var listener:NWListener?
  private var clients:[UUID:NWConnection] = [:]
  private var buffers:[UUID:Data] = [:]
  private var terminal = false
  private var timer:DispatchWorkItem?
  private let state:String
  private var port:UInt16 = 0
  private let stream:AsyncThrowingStream<String,Error>
  private let continuation:AsyncThrowingStream<String,Error>.Continuation
  public init(state:String) {
    self.state = state
    var saved:AsyncThrowingStream<String,Error>.Continuation!
    stream = AsyncThrowingStream {saved = $0};continuation = saved
  }
  public func start() async throws -> URL {
    try await withCheckedThrowingContinuation {completion in queue.async {
      guard self.listener == nil,!self.terminal else {completion.resume(throwing:CancellationError());return}
      do {
        let params = NWParameters.tcp;params.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        let listener = try NWListener(using:params,on:.any);self.listener = listener;var resumed = false
        listener.stateUpdateHandler = {[weak self] state in
          switch state {
          case .ready:
            if !resumed,let self,let port = listener.port {
              resumed = true;self.port = port.rawValue
              completion.resume(returning:URL(string:"http://127.0.0.1:\(port.rawValue)/oauth2callback")!)
            }
          case .failed(let error),.waiting(let error):
            if !resumed {resumed = true;completion.resume(throwing:error)};self?.finish(.failure(error))
          case .cancelled:
            listener.stateUpdateHandler = nil
            if !resumed {resumed = true;completion.resume(throwing:CancellationError())}
          default:break
          }
        }
        listener.newConnectionHandler = {[weak self] connection in self?.accept(connection)}
        listener.start(queue:self.queue)
        let timeout = DispatchWorkItem {[weak self] in self?.finish(.failure(RaceError.invalid("Google sign-in timed out. Try again.")))}
        self.timer = timeout;self.queue.asyncAfter(deadline:.now()+300,execute:timeout)
      } catch {completion.resume(throwing:error);self.finish(.failure(error))}
    }}
  }
  public func code() async throws -> String {
    try await withTaskCancellationHandler(operation:{
      for try await value in stream {return value}
      throw CancellationError()
    },onCancel:{self.cancel()})
  }
  public func cancel() {queue.async {self.finish(.failure(CancellationError()))}}
  private func close(_ id:UUID) {clients.removeValue(forKey:id)?.cancel();buffers.removeValue(forKey:id)}
  private func finish(_ result:Result<String,Error>) {
    guard !terminal else {return};terminal = true;timer?.cancel();timer = nil
    listener?.cancel();listener = nil
    for id in Array(clients.keys) {close(id)}
    switch result {case .success(let code):continuation.yield(code);continuation.finish()
    case .failure(let error):continuation.finish(throwing:error)}
  }
  private func accept(_ connection:NWConnection) {
    guard !terminal,clients.count < 4 else {connection.cancel();return}
    let id = UUID();clients[id] = connection;buffers[id] = Data()
    connection.start(queue:queue);receive(id)
    queue.asyncAfter(deadline:.now()+15) {[weak self] in self?.close(id)}
  }
  private func receive(_ id:UUID) {
    guard let connection = clients[id] else {return}
    connection.receive(minimumIncompleteLength:1,maximumLength:8192) {[weak self] bytes,_,complete,error in
      guard let self,self.clients[id] != nil else {return}
      if let bytes {self.buffers[id,default:Data()].append(bytes)}
      guard let buffer = self.buffers[id],buffer.count <= 8192 else {self.close(id);return}
      if let end = buffer.range(of:Data([13,10,13,10])) {
        let result = Self.parse(Data(buffer[..<end.lowerBound]),port:self.port,state:self.state)
        let valid = result != nil
        let body = valid ? "Sign-in response received. You may return to OpenRaceRender." : "Invalid sign-in callback. Return to OpenRaceRender and try again."
        let message = "HTTP/1.1 \(valid ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"+body
        connection.send(content:Data(message.utf8),completion:.contentProcessed {[weak self] _ in
          self?.close(id);if let result {self?.finish(result)}
        })
      } else if error != nil || complete {self.close(id)} else {self.receive(id)}
    }
  }
  static func parse(_ data:Data,port:UInt16,state:String) -> Result<String,Error>? {
    guard let text = String(data:data,encoding:.utf8),let line = text.components(separatedBy:"\r\n").first else {return nil}
    let fields = line.split(separator:" ")
    guard fields.count == 3,fields[0] == "GET",["HTTP/1.1","HTTP/1.0"].contains(String(fields[2])),fields[1].hasPrefix("/oauth2callback?"),
      let url = URLComponents(string:"http://127.0.0.1:\(port)"+fields[1]),url.path == "/oauth2callback" else {return nil}
    let hosts = text.components(separatedBy:"\r\n").dropFirst().filter{$0.lowercased().hasPrefix("host:")}
    guard hosts.count == 1,hosts[0].dropFirst(5).trimmingCharacters(in:.whitespaces) == "127.0.0.1:\(port)" else {return nil}
    let query = url.queryItems ?? [],states = query.filter{$0.name == "state"},codes = query.filter{$0.name == "code"},errors = query.filter{$0.name == "error"}
    guard states.count == 1,states[0].value == state else {return nil}
    if errors.count == 1,codes.isEmpty {return .failure(RaceError.invalid("Google sign-in was declined. No video was uploaded."))}
    guard errors.isEmpty,codes.count == 1,let code = codes[0].value,!code.isEmpty,code.utf8.count <= 4096 else {return nil}
    return .success(code)
  }
}
