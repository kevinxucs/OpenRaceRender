import Foundation
import Darwin

public enum LocalTransferAddress {
  public static func urls(port:UInt16,token:String) -> [URL] {
    var head:UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0 else {return []};defer {freeifaddrs(head)}
    var current = head,hosts = Set<String>()
    while let row = current {
      let item = row.pointee;current = item.ifa_next
      guard let address = item.ifa_addr,address.pointee.sa_family == UInt8(AF_INET),item.ifa_flags & UInt32(IFF_UP) != 0,item.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else {continue}
      var buffer = [CChar](repeating:0,count:Int(NI_MAXHOST))
      if getnameinfo(address,socklen_t(address.pointee.sa_len),&buffer,socklen_t(buffer.count),nil,0,NI_NUMERICHOST) == 0 {hosts.insert(String(cString:buffer))}
    }
    return hosts.sorted().compactMap {host in
      var parts = URLComponents();parts.scheme = "http";parts.host = host;parts.port = Int(port);parts.path = "/";parts.queryItems = [URLQueryItem(name:"token",value:token)]
      return parts.url
    }
  }
}
