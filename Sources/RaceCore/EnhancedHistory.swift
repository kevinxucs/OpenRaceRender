import AppKit

struct EnhancedState {
  var variables: [String:ScriptValue]
  var outline: Double
  var cost: Int {
    variables.reduce(0) { total,pair in total+pair.key.utf8.count+pair.value.string.utf8.count+32 }
  }
}

/// Frame-grid replay makes a persistent display independent of seek order and export start time.
final class EnhancedHistory: NSObject {
  let program: EnhancedProgram
  let background: CGImage
  let telemetry: Telemetry? // Retain the identity used by the cache key.
  private let lock = NSLock()
  private var checkpoints: [Int:EnhancedState]
  private var cursor: (frame: Int,state: EnhancedState)
  private var lastBefore: (frame: Int,state: EnhancedState)?
  private var checkpointCost: Int
  init(program: EnhancedProgram,background: CGImage,telemetry: Telemetry?,initial: EnhancedState) {
    self.program = program;self.background = background;self.telemetry = telemetry
    checkpoints = [0:initial];cursor = (0,initial);checkpointCost = initial.cost
  }
  func render(frame: Int,drawing: ScriptDrawing,values: (Int) -> [String:ScriptValue]) throws -> [String:ScriptValue] {
    lock.lock();defer { lock.unlock();drawing.renders = true }
    guard frame >= 0,frame <= 1_000_000 else { throw RaceError.invalid("Enhanced history exceeds the replay limit.") }
    let start: (frame: Int,state: EnhancedState)
    if let lastBefore,lastBefore.frame == frame { start = lastBefore }
    else {
      let index = checkpoints.keys.filter { $0 <= frame }.max() ?? 0
      start = cursor.frame <= frame && cursor.frame >= index ? cursor : (index,checkpoints[index]!)
    }
    drawing.outline = start.state.outline;drawing.renders = false
    let machine = ScriptMachine(variables:start.state.variables) { name,args in try drawing.call(name,args) }
    func run(_ index: Int) throws {
      let frameValues = values(index)
      machine.variables.merge(frameValues) { _,new in new }
      drawing.time = frameValues["sampletime"]?.number ?? 0
      machine.budget = 20000;machine.stopped = false
      try machine.run(program.foreground)
    }
    if start.frame < frame {
      for index in start.frame..<frame {
        try run(index)
        if (index+1)%300 == 0 { checkpoint(index+1,EnhancedState(variables:machine.variables,outline:drawing.outline)) }
      }
    }
    lastBefore = (frame,EnhancedState(variables:machine.variables,outline:drawing.outline))
    drawing.renders = true;try run(frame)
    cursor = (frame+1,EnhancedState(variables:machine.variables,outline:drawing.outline))
    if (frame+1)%300 == 0 { checkpoint(frame+1,cursor.state) }
    return machine.variables
  }
  private func checkpoint(_ index: Int,_ state: EnhancedState) {
    if let old = checkpoints.updateValue(state,forKey:index) { checkpointCost -= old.cost }
    checkpointCost += state.cost
    while checkpoints.count > 128 || (checkpointCost > 2*1024*1024 && checkpoints.count > 2) {
      guard let first = checkpoints.keys.filter({ $0 != 0 && $0 != index }).min(),let old = checkpoints.removeValue(forKey:first) else { break }
      checkpointCost -= old.cost
    }
  }
}
