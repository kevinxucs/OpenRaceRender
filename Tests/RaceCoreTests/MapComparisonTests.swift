import AppKit
import XCTest
@testable import RaceCore

final class MapComparisonTests:XCTestCase {
  func testIndependentInputClocksShareOnlyIdenticallyConfiguredDataTables() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("csv")
    defer {try? FileManager.default.removeItem(at:url)}
    try "Time,Speed (m/s)\n0,10\n1,20\n2,30\n".write(to:url,atomically:true,encoding:.utf8)
    let a = MediaInput(name:"First",path:url.path,kind:"data",legacyIndex:1)
    var b = a; b.id = UUID(); b.legacyIndex = 2; b.offset = 10
    var c = b; c.id = UUID(); c.legacyIndex = 3; var settings = DataSettings(); settings.timeUnitsPerSecond = 2; c.dataSettings = settings
    let tables = try Telemetry.loadSources([a,b,c])
    XCTAssertTrue(tables[1] === tables[2]); XCTAssertFalse(tables[1] === tables[3])
    XCTAssertEqual(tables[1]?.duration,2); XCTAssertEqual(tables[3]?.duration,1)
  }
  func session(_ boundaries:[Int],duration:Int) throws -> Telemetry {
    let rows = (0...duration).map { i in "\(i),\(36+Double(i%10)*0.0001),\(-121+Double(i%7)*0.0001),\(1+boundaries.filter{$0 <= i}.count)" }
    let data = try Telemetry(text:"Time,Latitude,Longitude,Lap\n"+rows.joined(separator:"\n"))
    var settings = DataSettings(); settings.assignments["lap"] = "Lap"; data.configure(settings); return data
  }
  func testGhostUsesEqualElapsedTimeAndWaitsAtFinishWithoutStretching() throws {
    let a = try session([10,22],duration:32),b = try session([5,13],duration:23)
    var settings = MapComparisonSettings(); settings.mode = .lapGhost
    XCTAssertEqual(settings.referenceTime(primary:a,reference:b,primaryTime:16,timelineTime:1000),11)
    XCTAssertEqual(settings.referenceTime(primary:a,reference:b,primaryTime:21,timelineTime:nil),13.0.nextDown)
    settings.primaryLapStart = 22
    XCTAssertNil(settings.referenceTime(primary:a,reference:b,primaryTime:16,timelineTime:0))
    XCTAssertEqual(settings.referenceTime(primary:a,reference:b,primaryTime:24,timelineTime:1000),7)
    settings.referenceLapStart = 0
    XCTAssertEqual(settings.referenceTime(primary:a,reference:b,primaryTime:24,timelineTime:1000),2)
    settings.referenceLapStart = 999; XCTAssertNil(settings.referenceTime(primary:a,reference:b,primaryTime:24,timelineTime:1000))
    settings.mode = .timeline; XCTAssertEqual(settings.referenceTime(primary:a,reference:b,primaryTime:24,timelineTime:4),4)
  }
  func testIndependentDuplicateAndLapAlignmentPreserveOriginalClockMarksAndObjects() throws {
    var project = RaceProject(); var source = MediaInput(name:"Logger",path:"logger.csv",kind:"data",legacyIndex:3); source.duration = 40; source.offset = 3
    project.inputs = [source]; project.rangeStart = 2; project.rangeEnd = 8
    let copyID = try project.duplicateDataInput(source.id)
    XCTAssertEqual(project.inputs.count,2); XCTAssertTrue(project.objects.isEmpty); XCTAssertNotEqual(copyID,source.id)
    XCTAssertEqual(project.inputs[1].path,source.path); XCTAssertEqual(project.inputs[1].legacyIndex,4)
    let time = try project.alignDataLaps(primary:SourceSyncAnchor(source.id,at:10),reference:SourceSyncAnchor(copyID,at:5))
    XCTAssertEqual(time,7); XCTAssertEqual(project.inputs[0],source); XCTAssertEqual(project.inputs[1].offset,-2)
    XCTAssertEqual(project.sourceTime(for:4,at:7),5); XCTAssertEqual(project.rangeStart,2); XCTAssertEqual(project.rangeEnd,8)
    XCTAssertThrowsError(try project.alignDataLaps(primary:SourceSyncAnchor(source.id,at:10),reference:SourceSyncAnchor(source.id,at:5)))
  }
  func testSharedGeometryProjectsBothSourcesAgainstOneOriginAndBounds() throws {
    let a = try Telemetry(text:"Time,Latitude,Longitude\n0,36,-121\n1,36.5,-121.1\n2,37,-121\n")
    let b = try Telemetry(text:"Time,Latitude,Longitude\n0,37,-121\n1,36.5,-121.1\n2,36,-121\n")
    let trace = try XCTUnwrap(MapComparisonRenderer.Trace(primary:a,reference:b,settings:MapComparisonSettings()))
    let same = trace.point(latitude:36.5,longitude:-121.1)
    XCTAssertTrue(trace.bounds.contains(same)); XCTAssertGreaterThan(trace.bounds.height,100_000)
    XCTAssertEqual(trace.origin.latitude,36); XCTAssertEqual(trace.origin.longitude,-121)
    let xy = try Telemetry(text:"Time,X,Y\n0,0,0\n1,1,1\n")
    XCTAssertNil(MapComparisonRenderer.Trace(primary:a,reference:xy,settings:MapComparisonSettings()))
  }
  func testTimelineClearTemplateRolesAndRemappingRetainComparisonWithoutSessionLaps() throws {
    var p = RaceProject(); p.inputs = [MediaInput(name:"Primary",path:"private-a.csv",kind:"data",legacyIndex:2),MediaInput(name:"Other",path:"private-b.csv",kind:"data",legacyIndex:8)]
    var o = DisplayObject(name:"Comparison",kind:.map); o.inputIndex = 2
    var settings = MapComparisonSettings(); settings.referenceInputIndex = 8; settings.mode = .lapGhost; settings.primaryLapStart = 10; settings.referenceLapStart = 20; o.mapComparison = settings
    var value = o; value.mapComparison = nil; o.editSegment(at:2,from:o,to:value)
    XCTAssertNil(o.resolved(at:3).mapComparison); XCTAssertTrue(o.segments![0].clearedProperties!.contains(.mapComparison))
    p.objects = [o]; let layout = try p.reusableLayout(objectIDs:[o.id])
    XCTAssertEqual(Set(layout.inputs.map(\.legacyIndex)),[2,8]); XCTAssertNil(layout.objects[0].mapComparison?.primaryLapStart); XCTAssertNil(layout.objects[0].mapComparison?.referenceLapStart)
    XCTAssertTrue(layout.inputs.allSatisfy{$0.path.isEmpty})
    var target = RaceProject(); target.inputs = [MediaInput(name:"New primary",path:"",kind:"data",legacyIndex:11),MediaInput(name:"New reference",path:"",kind:"data",legacyIndex:19)]
    target.applyLayout(layout,replace:false,mapping:[2:11,8:19])
    XCTAssertEqual(target.objects[0].inputIndex,11); XCTAssertEqual(target.objects[0].mapComparison?.referenceInputIndex,19)
    XCTAssertNil(target.objects[0].resolved(at:3).mapComparison)
    XCTAssertThrowsError(try LegacyWriter.data(p,format:.rrp)) { XCTAssertTrue($0.localizedDescription.contains("Shared-map")) }
  }
  func testComparisonReferenceAssetsArePreflightDependenciesEvenWithoutOtherWidgets() throws {
    var p = RaceProject(); let here = #filePath
    p.inputs = [MediaInput(name:"Primary",path:here,kind:"data",legacyIndex:0),MediaInput(name:"Other",path:"/missing/comparison.csv",kind:"data",legacyIndex:1)]
    var o = DisplayObject(name:"Map",kind:.map); var settings = MapComparisonSettings(); settings.referenceInputIndex = 1; o.mapComparison = settings; p.objects = [o]
    XCTAssertThrowsError(try p.validateExportAssets(start:0,duration:1))
    p.inputs[1].path = here; XCTAssertNoThrow(try p.validateExportAssets(start:0,duration:1))
  }
}
