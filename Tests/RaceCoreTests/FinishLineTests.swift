import XCTest
@testable import RaceCore

final class FinishLineTests:XCTestCase {
  func circuit(eastOffset:Double = 0,diagonal:Bool = false) throws -> Telemetry {
    var rows = ["Time,Latitude,Longitude"]
    for lap in 0..<3 {
      for (time,x,y) in [(0.0,diagonal ? -10.0 : 0,-10.0),(1.0,diagonal ? 30.0 : 0,30.0),(2.0,100.0,30.0),(4.0,100.0,-10.0),(6.0,0.0,-10.0)] {
        let latitude = 36+y/111195,longitude = -121+(x+eastOffset)/(111195*cos(36 * .pi/180))
        rows.append("\(Double(lap)*10+time),\(latitude),\(longitude)")
      }
    }
    return try Telemetry(text:rows.joined(separator:"\n"))
  }
  func line() -> FinishLine { var line = FinishLine(latitude:36,longitude:-121,heading:0); line.minimumLap = 8; return line }
  func testInterpolatedAndSampleTimingAndCoordinateTolerances() throws {
    let data = try circuit(); var settings = DataSettings(); settings.finishLine = line(); data.configure(settings)
    XCTAssertEqual(data.laps.filter(\.complete).count,2); XCTAssertEqual(data.laps[1].start,0.25,accuracy:1e-8)
    XCTAssertEqual(data.laps[1].duration,10,accuracy:1e-8)
    settings.finishLine?.precision = .sample; data.configure(settings)
    XCTAssertEqual(data.laps[1].start,1); XCTAssertEqual(data.laps[1].duration,10)
    settings.finishLine?.northTolerance = 5; data.configure(settings); XCTAssertEqual(data.laps.count,1,"Sample mode must honor the sample's distance past the gate")
    settings.finishLine?.precision = .interpolated; data.configure(settings); XCTAssertEqual(data.laps.filter(\.complete).count,2)
    let offset = try circuit(eastOffset:6); settings.finishLine?.eastTolerance = 5; offset.configure(settings); XCTAssertEqual(offset.laps.count,1)
    settings.finishLine?.eastTolerance = 10; offset.configure(settings); XCTAssertEqual(offset.laps.filter(\.complete).count,2)
  }
  func testHeadingDirectionToleranceAndIgnoredCalculatedTriggers() throws {
    let data = try circuit(diagonal:true); var settings = DataSettings(); settings.finishLine = line(); settings.finishLine?.headingTolerance = 20
    data.configure(settings); XCTAssertEqual(data.laps.count,1)
    settings.finishLine?.headingTolerance = 60; data.configure(settings); XCTAssertEqual(data.laps.filter(\.complete).count,2)
    settings.finishLine?.heading = 720; data.configure(settings); XCTAssertEqual(data.laps.filter(\.complete).count,2)
    settings.ignoreLapTriggers = 1; data.configure(settings); XCTAssertEqual(data.laps.filter(\.complete).count,1)
    XCTAssertEqual(data.laps[1].start,10.25,accuracy:1e-8)
    settings.ignoreLapTriggers = 100; data.configure(settings); XCTAssertEqual(data.laps.count,1); XCTAssertFalse(data.laps[0].complete)
    settings.ignoreLapTriggers = 0; settings.finishLine?.heading = 180; data.configure(settings); XCTAssertEqual(data.laps.count,1)
  }
  func testRecordedTriggerIgnoreRetainsPreciseBoundariesAndCanReset() throws {
    let data = try Telemetry(text:"Time,Lap\n0,1\n1.234,2\n11.456,3\n21.789,4\n25,4\n")
    let original = data.laps
    var settings = DataSettings(); settings.ignoreLapTriggers = 1; data.configure(settings)
    XCTAssertEqual(data.laps.map(\.number),[0,1,2]); XCTAssertEqual(data.laps[1].start,11.456)
    XCTAssertEqual(data.laps[1].end,21.789); XCTAssertTrue(data.laps[1].complete)
    settings.ignoreLapTriggers = nil; data.configure(settings); XCTAssertEqual(data.laps.map(\.start),original.map(\.start)); XCTAssertEqual(data.laps.map(\.number),original.map(\.number))
  }
  func testGPSPausesTeleportsAndStationarySamplesCannotInventCrossingsOrHeading() throws {
    let gap = try Telemetry(text:"Time,Latitude,Longitude\n0,35.9999,-121\n0.1,35.9999,-121\n10,36.0001,-121\n10.1,36.0001,-121\n")
    var settings = DataSettings(); settings.finishLine = line(); gap.configure(settings); XCTAssertEqual(gap.laps.count,1)
    let jump = try Telemetry(text:"Time,Latitude,Longitude\n0,35,-121\n0.1,37,-121\n0.2,37,-121\n")
    jump.configure(settings); XCTAssertEqual(jump.laps.count,1)
    let stationary = try Telemetry(text:"Time,Latitude,Longitude\n0,36,-121\n1,36,-121\n2,36,-121\n")
    XCTAssertNil(stationary.finishLine(at:1)); XCTAssertNil(stationary.finishLine(at:-1))
    let moving = try circuit(); let sample = try XCTUnwrap(moving.finishLine(at:0.25))
    XCTAssertEqual(sample.latitude,36,accuracy:1e-9); XCTAssertEqual(sample.heading,0,accuracy:1e-9)
  }
  func testTrackLibraryRoundtripNearbyLookupMergeAndValidation() throws {
    var library = TrackLibrary(); library.tracks = [SavedTrack(name:"Original local circuit",finishLine:line()),SavedTrack(name:"Far away",finishLine:FinishLine(latitude:42,longitude:-115,heading:0))]
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer {try? FileManager.default.removeItem(at:root)}
    let file = root.appendingPathComponent("Tracks.orrtracks"); try library.save(file); XCTAssertEqual(try TrackLibrary.read(file),library)
    XCTAssertEqual(library.nearby(latitude:36.001,longitude:-121).map(\.track.name),["Original local circuit"])
    var imported = library; imported.tracks[0].name = "Another layout"
    let merged = try library.merging(imported); XCTAssertEqual(merged.tracks.count,3); XCTAssertEqual(merged.tracks[0],library.tracks[0]); XCTAssertNotEqual(merged.tracks[2].id,library.tracks[0].id)
    XCTAssertEqual(try library.merging(library),library)
    XCTAssertTrue(library.nearby(latitude:.nan,longitude:0).isEmpty)
    library.formatVersion = 2; XCTAssertThrowsError(try library.validate()); library.formatVersion = 1
    library.tracks[0].finishLine.eastTolerance = 0; XCTAssertThrowsError(try library.validate())
    XCTAssertFalse(TrackLibrary.userURL().path.contains("Documents"))
  }
  func testFinishLineSettingsProfileCompatibilityAndGPSPlotSampling() throws {
    var settings = DataSettings(); var line = line(); line.precision = .sample; line.eastTolerance = 8; line.northTolerance = 12; line.headingTolerance = 35
    settings.finishLine = line; settings.ignoreLapTriggers = 2
    let profile = DataProfile(name:"Original track",settings:settings,includeTrackSettings:true)
    XCTAssertEqual(try JSONDecoder().decode(DataProfile.self,from:JSONEncoder().encode(profile)),profile)
    XCTAssertNil(DataProfile(name:"Logger",settings:settings).settings.finishLine)
    let old = try JSONDecoder().decode(FinishLine.self,from:Data("{\"latitude\":36,\"longitude\":-121,\"heading\":0,\"width\":40,\"minimumLap\":10}".utf8))
    XCTAssertNil(old.precision); XCTAssertNil(old.eastTolerance)
    let data = try circuit(); XCTAssertLessThanOrEqual(data.gpsTrackSamples(maximum:5).count,5)
    let start = line.localPosition(latitude:line.latitude,longitude:line.longitude); XCTAssertEqual(start.0,0); XCTAssertEqual(start.1,0)
    let point = line.point(east:12,north:34),back = line.localPosition(latitude:point.latitude,longitude:point.longitude)
    XCTAssertEqual(back.0,12,accuracy:1e-7); XCTAssertEqual(back.1,34,accuracy:1e-7)
  }
}
