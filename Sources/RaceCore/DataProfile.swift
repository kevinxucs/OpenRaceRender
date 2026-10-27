import Foundation

public enum DataRole:String,CaseIterable,Sendable {
  case time,lon,lat,altitude,accuracy,lap,speed,heading,rpm,gear,gx,gy,throttle,brake,distance,coolant,intake,oil
  public var title:String {
    switch self {
    case .time:return "Session time"; case .lon:return "Longitude"; case .lat:return "Latitude"
    case .altitude:return "Altitude"; case .accuracy:return "GPS accuracy"; case .lap:return "Lap number"
    case .speed:return "Speed"; case .heading:return "Heading"; case .rpm:return "Engine RPM"; case .gear:return "Gear"
    case .gx:return "Longitudinal G"; case .gy:return "Lateral G"; case .throttle:return "Throttle"; case .brake:return "Brake"
    case .distance:return "Distance"; case .coolant:return "Coolant temperature"; case .intake:return "Intake temperature"; case .oil:return "Oil temperature"
    }
  }
}

/// Open, versioned data configuration. No source path, timing offset or project state.
public struct DataProfile:Codable,Equatable,Sendable {
  public var formatVersion:Int = 1
  public var name:String
  public var settings:DataSettings
  public var includesTrackSettings:Bool
  public init(name:String,settings:DataSettings,includeTrackSettings:Bool = false) {
    self.name = name; self.settings = settings; includesTrackSettings = includeTrackSettings
    if !includeTrackSettings { self.settings.finishLine = nil; self.settings.ignoreLapTriggers = nil }
  }
  enum CodingKeys:String,CodingKey { case formatVersion,name,settings,includesTrackSettings }
  public init(from decoder:Decoder) throws {
    let c = try decoder.container(keyedBy:CodingKeys.self)
    formatVersion = try c.decode(Int.self,forKey:.formatVersion)
    name = try c.decodeIfPresent(String.self,forKey:.name) ?? "Data profile"
    settings = try c.decode(DataSettings.self,forKey:.settings)
    includesTrackSettings = try c.decodeIfPresent(Bool.self,forKey:.includesTrackSettings) ?? false
    try validate()
  }
  public func applying(to current:DataSettings) -> DataSettings {
    var value = settings
    if !includesTrackSettings { value.finishLine = current.finishLine; value.ignoreLapTriggers = current.ignoreLapTriggers }
    return value
  }
  public func validate() throws {
    guard formatVersion == 1 else { throw RaceError.invalid("Unsupported data-profile version \(formatVersion).") }
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf8.count <= 1024,
      includesTrackSettings || (settings.finishLine == nil && settings.ignoreLapTriggers == nil) else {
      throw RaceError.invalid("Use a profile name and explicitly include track settings when saving them.")
    }
    try settings.validateConfiguration()
  }
  public static func read(_ url:URL) throws -> DataProfile {
    let bytes = try Data(contentsOf:url)
    guard bytes.count <= 1_048_576 else { throw RaceError.invalid("Data profiles must be smaller than 1 MB.") }
    do { return try JSONDecoder().decode(DataProfile.self,from:bytes) }
    catch let error as RaceError { throw error }
    catch { throw RaceError.invalid("Not a supported OpenRaceRender data profile. Native RaceRender profile files are not yet verified.\n\n"+error.localizedDescription) }
  }
  public func save(_ url:URL) throws {
    try validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
    try encoder.encode(self).write(to:url,options:.atomic)
  }
}

extension Telemetry {
  public func configureValidated(_ settings:DataSettings) throws {
    try settings.validateConfiguration(headers:recordedHeaders)
    if let name = settings.assignments["time"],!name.isEmpty,let i = recordedHeaders.firstIndex(where:{$0.caseInsensitiveCompare(name) == .orderedSame}) {
      let clock = recordedState?.columns[i] ?? columns[i]
      guard clock.count >= 2,clock.allSatisfy(\.isFinite),zip(clock,clock.dropFirst()).allSatisfy({$0 <= $1}),clock.last! > clock.first! else {
        throw RaceError.invalid("Assigned time column must contain at least two increasing, finite timestamps.")
      }
    }
    configure(settings)
    guard Array(headers.suffix(settings.fields.count)) == settings.fields.map(\.name) else {
      throw RaceError.invalid("A calculated field has an unavailable source. Fields may refer to recorded/derived channels or earlier calculated fields.")
    }
  }
}

extension DataSettings {
  public func validateConfiguration(headers:[String]? = nil) throws {
    guard assignments.count <= 64,fields.count <= 64,
      assignments.allSatisfy({!$0.key.isEmpty && $0.key.utf8.count <= 128 && $0.value.utf8.count <= 4096}) else {
      throw RaceError.invalid("Data configuration has too many or invalid assignments/calculated fields.")
    }
    if let headers {
      // Use explicit names, not column positions, so a different file cannot silently remap a role.
      let unresolved = assignments.values.filter { name in !name.isEmpty && !headers.contains(where:{$0.caseInsensitiveCompare(name) == .orderedSame}) }
      if !unresolved.isEmpty { throw RaceError.invalid("Remap the profile's missing columns before applying:\n"+Set(unresolved).sorted().joined(separator:"\n")) }
    }
    if let units = timeUnitsPerSecond,(!units.isFinite || units <= 0) { throw RaceError.invalid("Time units per second must be positive.") }
    if let multiplier = speedMultiplier,!multiplier.isFinite { throw RaceError.invalid("Speed multiplier must be finite.") }
    if let unit = speedUnit,!RaceProject.speedUnits.contains(unit) { throw RaceError.invalid("Choose mph, km/h, m/s or knots for speed conversion.") }
    if let multiplier = accuracyMultiplier,(!multiplier.isFinite || multiplier <= 0) { throw RaceError.invalid("GPS accuracy conversion to meters must be positive.") }
    if let headingAdjustment,!headingAdjustment.isFinite { throw RaceError.invalid("Heading adjustment must be finite.") }
    if let gearAdjustment,(!gearAdjustment.isFinite || gearAdjustment.rounded() != gearAdjustment || !(-128...127).contains(gearAdjustment)) { throw RaceError.invalid("Gear adjustment must be a whole number between −128 and 127.") }
    if let ignoreLapTriggers,!(0...1_000_000).contains(ignoreLapTriggers) { throw RaceError.invalid("Ignored lap triggers must be nonnegative.") }
    if let gearEstimation { try gearEstimation.validate() }
    var names = Set<String>()
    for field in fields {
      guard !field.name.isEmpty,field.name.utf8.count <= 1024,names.insert(field.name.lowercased()).inserted,
        !field.source.isEmpty,field.source.utf8.count <= 4096,field.multiply.isFinite,field.add.isFinite else {
        throw RaceError.invalid("Calculated fields need unique names, a source and finite multiplier/offset.")
      }
    }
    try finishLine?.validate()
  }
}

public struct TelemetryColumnPreview:Sendable {
  public var headers:[String]
  public var rows:[[String]]
  public static func read(_ url:URL) throws -> TelemetryColumnPreview {
    let handle = try FileHandle(forReadingFrom:url); defer {try? handle.close()}
    let data = try handle.read(upToCount:1_048_576) ?? Data()
    guard let text = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.utf16) ?? String(data:data,encoding:.isoLatin1) else { throw RaceError.invalid("Cannot inspect the text data file.") }
    let lines = text.replacingOccurrences(of:"\u{FEFF}",with:"").components(separatedBy:.newlines).filter{!$0.isEmpty}.prefix(150)
    let array = Array(lines)
    var best:TelemetryColumnPreview?
    for index in array.indices where index+1 < array.count {
      let line = array[index], separator:Character = line.contains("\t") ? "\t" : line.contains(";") && !line.contains(",") ? ";" : ","
      let cells = Telemetry.parseRow(line,delimiter:separator)
      guard cells.count >= 2,cells.allSatisfy({!$0.isEmpty}),cells.contains(where:{Double($0) == nil}),Set(cells).count == cells.count else { continue }
      let rows = array.dropFirst(index+1).prefix(8).map{Telemetry.parseRow($0,delimiter:separator)}.filter{$0.count == cells.count}
      guard rows.contains(where:{$0.contains(where:{Telemetry.parseTime($0) != nil})}) else { continue }
      let candidate = Self(headers:cells,rows:rows)
      if cells.contains(where:Telemetry.isTimeHeader) { return candidate }
      if best == nil || cells.count > best!.headers.count { best = candidate }
    }
    guard let best else { throw RaceError.invalid("No delimited header and numeric rows found. Choose a CSV/TSV file with column names.") }
    return best
  }
}
