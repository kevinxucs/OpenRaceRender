import XCTest
@testable import RaceCore

final class DataProfileTests:XCTestCase {
  func file(_ text:String,_ ext:String = "csv") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    try text.write(to:url,atomically:true,encoding:.utf8); addTeardownBlock{try? FileManager.default.removeItem(at:url)}
    return url
  }
  func testUnknownClockPreviewAndExplicitClockConversion() throws {
    let url = try file("Logger export\n\u{FEFF}Ticks;Velocity;Height;Uncertainty;Circuit\n5000;36;50;10;1\n6000;72;51;20;2\n7000;108;52;30;3\n")
    XCTAssertThrowsError(try Telemetry(url:url))
    let preview = try TelemetryColumnPreview.read(url)
    XCTAssertEqual(preview.headers,["Ticks","Velocity","Height","Uncertainty","Circuit"]); XCTAssertEqual(preview.rows.count,3)
    var settings = DataSettings(); settings.assignments = ["time":"ticks","speed":"Velocity","altitude":"Height","accuracy":"Uncertainty","lap":"Circuit"]
    settings.timeUnitsPerSecond = 1000; settings.speedConversionEnabled = true; settings.speedMultiplier = 1; settings.speedUnit = "km/h"; settings.accuracyMultiplier = 0.1
    let data = try Telemetry(url:url,settings:settings)
    XCTAssertEqual(data.times,[0,1,2]); XCTAssertEqual(data.sourceHeaders["time"],"Ticks")
    XCTAssertEqual(data.value("time",at:1),1); XCTAssertEqual(data.speed(at:1,unit:"m/s"),20)
    XCTAssertEqual(data.value("altitude",at:1),51); XCTAssertEqual(data.value("accuracy",at:1),2)
    XCTAssertEqual(data.laps.map(\.number),[1,2,3]); XCTAssertEqual(data.laps.map(\.start),[0,1,2]); XCTAssertTrue(data.laps[1].complete)
    data.configure(settings); XCTAssertEqual(data.times,[0,1,2]); XCTAssertEqual(data.value("accuracy",at:1),2)
    XCTAssertEqual(data.speed(at:1,unit:"m/s"),20)
  }
  func testExplicitClockNeverFallsBackToAnotherColumnOrDiscardsBackwardsRows() throws {
    let bad = try file("Time,Clock,Speed\n0,100,1\n1,90,2\n2,110,3\n")
    var settings = DataSettings(); settings.assignments["time"] = "Missing"
    XCTAssertThrowsError(try Telemetry(url:bad,settings:settings))
    settings.assignments["time"] = "Clock"; XCTAssertThrowsError(try Telemetry(url:bad,settings:settings))
    let constant = try file("Clock,Speed\n1,10\n1,20\n")
    XCTAssertThrowsError(try Telemetry(url:constant,settings:settings))
    let clock = try file("Clock,Speed (m/s)\n01:00:00.0,10\n01:00:01.5,20\n")
    let data = try Telemetry(url:clock,settings:settings); XCTAssertEqual(data.times,[0,1.5]); XCTAssertEqual(data.value("time",at:1.5),1.5)
  }
  func testProfilesRoundtripRetainCalibrationAndChooseTrackScope() throws {
    var settings = DataSettings(); settings.assignments = ["speed":"Wheel speed","time":"Tick"]
    settings.timeUnitsPerSecond = 1000; settings.speedConversionEnabled = true; settings.speedUnit = "km/h"
    settings.speedMultiplier = 0.5; settings.accuracyMultiplier = 0.3; settings.headingAdjustment = 30
    settings.gearDerivation = .calculate; var gear = GearEstimationSettings(); gear.ratios = [200,100]; settings.gearEstimation = gear
    var field = CalculatedField(); field.name = "Double RPM"; field.source = "rpm"; field.multiply = 2; settings.fields = [field]
    settings.finishLine = FinishLine(latitude:37,longitude:-122,heading:90); settings.ignoreLapTriggers = 2
    let profile = DataProfile(name:"My logger",settings:settings)
    XCTAssertNil(profile.settings.finishLine); XCTAssertNil(profile.settings.ignoreLapTriggers)
    XCTAssertEqual(profile.applying(to:settings).finishLine,settings.finishLine)
    let url = try file("","orrd"); try profile.save(url); XCTAssertEqual(try DataProfile.read(url),profile)
    let json = try String(contentsOf:url,encoding:.utf8); XCTAssertFalse(json.contains("path")); XCTAssertFalse(json.contains("offset"))
    let track = DataProfile(name:"Logger and circuit",settings:settings,includeTrackSettings:true)
    XCTAssertEqual(track.applying(to:DataSettings()).finishLine,settings.finishLine)
    XCTAssertEqual(try JSONDecoder().decode(DataProfile.self,from:JSONEncoder().encode(track)),track)
  }
  func testMissingHeadersInvalidSettingsAndUnverifiedNativeExportAreRejected() throws {
    var settings = DataSettings(); settings.assignments["speed"] = "missing"
    XCTAssertThrowsError(try settings.validateConfiguration(headers:["Time","Speed"]))
    settings.assignments["speed"] = "speed"; XCTAssertNoThrow(try settings.validateConfiguration(headers:["Time","Speed"]))
    settings.timeUnitsPerSecond = 0; XCTAssertThrowsError(try settings.validateConfiguration()); settings.timeUnitsPerSecond = nil
    settings.accuracyMultiplier = -1; XCTAssertThrowsError(try settings.validateConfiguration()); settings.accuracyMultiplier = nil
    var profile = DataProfile(name:"Logger",settings:settings); profile.formatVersion = 2; XCTAssertThrowsError(try profile.validate())
    let data = try file("Time,Speed\n0,1\n1,2\n")
    var field = CalculatedField(); field.source = "unknown"; settings.fields = [field]
    XCTAssertThrowsError(try Telemetry(url:data,settings:settings))
    field.source = "Later"; var later = CalculatedField(); later.name = "Later"; later.source = "speed"
    settings.fields = [field,later]; XCTAssertThrowsError(try Telemetry(url:data,settings:settings))
    settings.fields = []
    settings.accuracyMultiplier = 0.1
    var input = MediaInput(name:"Logger",path:data.path,kind:"data"); input.dataSettings = settings
    var project = RaceProject(); project.inputs = [input]
    XCTAssertThrowsError(try LegacyWriter.data(project,format:.rrp))
  }
  func testAutomaticSpeedUnitsRemainCompatibleUntilExplicitlyOverridden() throws {
    let url = try file("Time,Speed (km/h),RPM\n0,36,2000\n1000,36,2000\n2000,36,2000\n")
    var settings = DataSettings(); settings.speedMultiplier = 1; settings.speedUnit = "mph"; settings.timeUnitsPerSecond = 1000
    let data = try Telemetry(url:url,settings:settings)
    XCTAssertEqual(data.speed(at:1,unit:"m/s"),10); XCTAssertEqual(data.value("gear",at:1),1)
    settings.speedConversionEnabled = true; settings.speedUnit = "km/h"; settings.speedMultiplier = 2
    data.configure(settings); XCTAssertEqual(data.speed(at:1,unit:"m/s"),20)
    settings.speedConversionEnabled = false; data.configure(settings); XCTAssertEqual(data.speed(at:1,unit:"m/s"),10)
    XCTAssertEqual(data.recordedHeaders,["Time","Speed (km/h)","RPM"])
  }
}
