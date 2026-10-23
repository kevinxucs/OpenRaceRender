import Foundation

/// A deliberately bounded interpreter for the documented drawing language. No eval, loops,
/// properties, filesystem, networking, or native function lookup are available to imported scripts.
enum ScriptValue {
  case number(Double), string(String)
  var number: Double { if case .number(let n) = self { return n }; return 0 }
  var string: String { switch self { case .string(let s): return s; case .number(let n): return String(n) } }
  var truth: Bool { number.isFinite && number != 0 }
}
enum ScriptToken: Equatable {
  case number(Double), string(String), name(String), symbol(String)
}
indirect enum ScriptExpression {
  case value(ScriptValue), variable(String), unary(String, ScriptExpression)
  case binary(String, ScriptExpression, ScriptExpression), call(String, [ScriptExpression])
  case assignment(String,ScriptExpression)
}
indirect enum ScriptStatement {
  case assign(String, String, ScriptExpression), expression(ScriptExpression)
  case branch(ScriptExpression, ScriptStatement, ScriptStatement?), block([ScriptStatement]), stop
}

struct ScriptParser {
  var tokens: [ScriptToken] = []
  var index = 0
  var nodes = 0
  init(_ source: String) throws {
    guard source.utf8.count <= 32768 else { throw RaceError.invalid("Enhanced script exceeds size limit.") }
    let chars = Array(source)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if c == "\n" { tokens.append(.symbol("\n")); i += 1; continue }
      if c.isWhitespace { i += 1; continue }
      if c == "/", i+1 < chars.count, chars[i+1] == "/" {
        while i < chars.count && chars[i] != "\n" { i += 1 }; continue
      }
      if c == "/", i+1 < chars.count, chars[i+1] == "*" {
        i += 2
        while i+1 < chars.count && !(chars[i] == "*" && chars[i+1] == "/") { i += 1 }
        guard i+1 < chars.count else { throw RaceError.invalid("Unterminated script comment.") }
        i += 2; continue
      }
      if c == "\"" || c == "'" {
        let quote = c; i += 1; var s = ""
        while i < chars.count && chars[i] != quote { s.append(chars[i]); i += 1 }
        guard i < chars.count, s.count <= 1024 else { throw RaceError.invalid("Invalid script string.") }
        i += 1
        if quote == "'" { tokens.append(.number(Double(s.utf8.first ?? 0))) }
        else { tokens.append(.string(s)) }
        continue
      }
      if c.isNumber || (c == "." && i+1 < chars.count && chars[i+1].isNumber) {
        let start = i
        if c == "0", i+1 < chars.count, chars[i+1] == "x" || chars[i+1] == "X" {
          i += 2; let begin = i
          while i < chars.count && chars[i].isHexDigit { i += 1 }
          guard let n = UInt64(String(chars[begin..<i]),radix:16) else { throw RaceError.invalid("Invalid hex literal.") }
          tokens.append(.number(Double(n)))
        } else {
          while i < chars.count && (chars[i].isNumber || chars[i] == ".") { i += 1 }
          guard let n = Double(String(chars[start..<i])), n.isFinite else { throw RaceError.invalid("Invalid number literal.") }
          tokens.append(.number(n))
        }
        continue
      }
      if c.isASCII && (c.isLetter || c == "_") {
        let start = i; i += 1
        while i < chars.count && chars[i].isASCII && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") { i += 1 }
        tokens.append(.name(String(chars[start..<i]).lowercased())); continue
      }
      let pair = i+1 < chars.count ? String(chars[i...i+1]) : ""
      if ["==","!=",">=","<=","&&","||","+=","-=","*=","/=","%=","^="].contains(pair) {
        tokens.append(.symbol(pair)); i += 2; continue
      }
      guard "{}(),;=+-*/%^!<>".contains(c) else { throw RaceError.invalid("Unsupported script token.") }
      tokens.append(.symbol(String(c))); i += 1
    }
    guard tokens.count <= 16000 else { throw RaceError.invalid("Enhanced script has too many tokens.") }
  }
  mutating func parse() throws -> [ScriptStatement] {
    var result: [ScriptStatement] = []
    separators()
    while index < tokens.count { result.append(try statement(depth: 0)); separators() }
    return result
  }
  mutating func take(_ s: String) -> Bool {
    if index < tokens.count, tokens[index] == .symbol(s) { index += 1; return true }; return false
  }
  mutating func require(_ s: String) throws { guard take(s) else { throw RaceError.invalid("Expected \(s) in script.") } }
  mutating func newlines() { while take("\n") {} }
  mutating func separators() { while take("\n") || take(";") {} }
  mutating func statement(depth: Int) throws -> ScriptStatement {
    nodes += 1
    guard depth < 64, nodes < 8000, index < tokens.count else { throw RaceError.invalid("Enhanced script nesting/size limit.") }
    newlines()
    if take("{") {
      var body: [ScriptStatement] = []; separators()
      while !take("}") { body.append(try statement(depth: depth+1)); separators() }
      return .block(body)
    }
    if tokens[index] == .name("if") {
      index += 1; try require("("); let condition = try expression(depth: depth+1); newlines(); try require(")"); newlines()
      let yes = try statement(depth: depth+1); separators()
      var no: ScriptStatement?
      if index < tokens.count, tokens[index] == .name("else") { index += 1; newlines(); no = try statement(depth: depth+1) }
      return .branch(condition,yes,no)
    }
    if tokens[index] == .name("return") { index += 1; return .stop }
    if case .name(let name) = tokens[index], index+1 < tokens.count,
      case .symbol(let op) = tokens[index+1], ["=","+=","-=","*=","/=","%=","^="].contains(op) {
      index += 2; return .assign(name,op,try expression(depth: depth+1))
    }
    return .expression(try expression(depth: depth+1))
  }
  static let priorities = ["=":0,"||":1,"&&":2,"^":3,"==":4,"!=":4,"<":4,">":4,"<=":4,">=":4,"+":5,"-":5,"*":6,"/":6,"%":6]
  mutating func expression(_ minimum: Int = 0, depth: Int) throws -> ScriptExpression {
    newlines()
    guard depth < 64, index < tokens.count else { throw RaceError.invalid("Invalid script expression.") }
    let token = tokens[index]; index += 1
    var left: ScriptExpression
    switch token {
    case .number(let n): left = .value(.number(n))
    case .string(let s): left = .value(.string(s))
    case .name(let name):
      if take("(") {
        var args: [ScriptExpression] = []; newlines()
        if !take(")") {
          repeat { newlines(); args.append(try expression(depth: depth+1)); newlines() } while take(",")
          try require(")")
        }
        left = .call(name,args)
      } else { left = .variable(name) }
    case .symbol("("): left = try expression(depth: depth+1); newlines(); try require(")")
    case .symbol(let op) where ["+","-","!"].contains(op): left = .unary(op,try expression(7,depth: depth+1))
    default: throw RaceError.invalid("Unsupported script expression.")
    }
    while index < tokens.count, case .symbol(let op) = tokens[index], let priority = Self.priorities[op], priority >= minimum {
      index += 1
      if op == "=" {
        guard case .variable(let name) = left else { throw RaceError.invalid("Invalid script assignment.") }
        left = .assignment(name,try expression(priority,depth:depth+1))
      } else { left = .binary(op,left,try expression(priority+1,depth: depth+1)) }
    }
    return left
  }
}

final class ScriptMachine {
  var variables: [String: ScriptValue]
  var budget = 20000
  var stopped = false
  var evaluationDepth = 0
  let function: (String,[ScriptValue]) throws -> ScriptValue
  init(variables: [String: ScriptValue], function: @escaping (String,[ScriptValue]) throws -> ScriptValue) {
    self.variables = variables; self.function = function
  }
  func run(_ program: [ScriptStatement]) throws { for s in program where !stopped { try execute(s) } }
  func spend() throws { budget -= 1; if budget <= 0 { throw RaceError.invalid("Enhanced script instruction limit.") } }
  func execute(_ s: ScriptStatement) throws {
    try spend()
    switch s {
    case .stop: stopped = true
    case .block(let list): try run(list)
    case .expression(let e): _ = try evaluate(e)
    case .branch(let e, let yes, let no): if try evaluate(e).truth { try execute(yes) } else if let no { try execute(no) }
    case .assign(let name, let op, let e):
      guard variables[name] != nil || variables.count < 256 else { throw RaceError.invalid("Too many script variables.") }
      let rhs = try evaluate(e)
      variables[name] = op == "=" ? rhs : try Self.binary(String(op.prefix(1)),variables[name] ?? .number(0),rhs)
    }
  }
  func evaluate(_ e: ScriptExpression) throws -> ScriptValue {
    try spend()
    evaluationDepth += 1
    defer { evaluationDepth -= 1 }
    guard evaluationDepth < 128 else { throw RaceError.invalid("Enhanced expression nesting limit.") }
    switch e {
    case .assignment(let name,let e):
      guard variables[name] != nil || variables.count < 256 else { throw RaceError.invalid("Too many script variables.") }
      let value = try evaluate(e);variables[name] = value;return value
    case .value(let v): return v
    case .variable(let name): return variables[name] ?? .number(0)
    case .call(let name,let args): return try function(name,args.map { try evaluate($0) })
    case .unary(let op,let e):
      let v = try evaluate(e)
      return .number(op == "!" ? (v.truth ? 0 : 1) : (op == "-" ? -v.number : v.number))
    case .binary(let op,let a,let b):
      let lhs = try evaluate(a)
      if op == "&&" && !lhs.truth { return .number(0) }
      if op == "||" && lhs.truth { return .number(1) }
      return try Self.binary(op,lhs,evaluate(b))
    }
  }
  static func binary(_ op: String,_ a: ScriptValue,_ b: ScriptValue) throws -> ScriptValue {
    if case .string(let x) = a, case .string(let y) = b {
      if op == "+" { return .string(String((x+y).prefix(4096))) }
      if op == "==" { return .number(x == y ? 1 : 0) }
      if op == "!=" { return .number(x != y ? 1 : 0) }
    }
    let x = a.number,y = b.number
    switch op {
    case "+": return .number(x+y)
    case "-": return .number(x-y)
    case "*": return .number(x*y)
    case "/": return .number(y == 0 ? .nan : x/y)
    case "%": return .number(y == 0 ? .nan : x.truncatingRemainder(dividingBy:y))
    case "^": return .number(Double(Int64(clamping: int(x)) ^ Int64(clamping: int(y))))
    case "==": return .number(abs(x-y) < 1e-8 ? 1 : 0)
    case "!=": return .number(abs(x-y) < 1e-8 ? 0 : 1)
    case "<": return .number(x < y ? 1 : 0)
    case ">": return .number(x > y ? 1 : 0)
    case "<=": return .number(x <= y ? 1 : 0)
    case ">=": return .number(x >= y ? 1 : 0)
    case "&&": return .number(a.truth && b.truth ? 1 : 0)
    case "||": return .number(a.truth || b.truth ? 1 : 0)
    default: throw RaceError.invalid("Unsupported script operator.")
    }
  }
  static func int(_ value: Double) -> Int {
    value.isFinite ? Int(max(-1e12,min(1e12,value))) : 0
  }
}
