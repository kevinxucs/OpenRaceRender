import XCTest
@testable import RaceCore

final class CameraTelemetryTests:XCTestCase {
  func be(_ v:UInt64,_ n:Int = 4) -> Data {Data((0..<n).reversed().map{UInt8(truncatingIfNeeded:v >> ($0*8))})}
  func atom(_ name:String,_ body:Data) -> Data {be(UInt64(body.count+8))+Data(name.utf8)+body}
  func klv(_ name:String,_ type:UInt8,_ width:Int,_ count:Int,_ body:Data) -> Data {
    Data(name.utf8)+Data([type,UInt8(width)])+be(UInt64(count),2)+body+Data(repeating:0,count:(4-body.count%4)%4)
  }
  func stream(_ body:Data) -> Data {klv("STRM",0,1,body.count,body)}
  func packet(fix:UInt64,gps9:Bool = false) -> Data {
    let scale:[UInt64] = gps9 ? [10_000_000,10_000_000,1000,1000,1000,1,1000,100,1] : [10_000_000,10_000_000,1000,1000,1000]
    let row:[UInt64] = gps9 ? [100_000_000,200_000_000,50_000,10_000,11_000,9000,10_000,150,fix] : [100_000_000,200_000_000,50_000,10_000,11_000]
    let row2 = row.enumerated().map { $0.offset == 0 ? $0.element+1000 : $0.element }
    var gps = klv("SCAL",76,4,scale.count,scale.reduce(into:Data()){$0 += be($1)})
    gps += klv("GPSF",76,4,1,be(fix))+klv("GPSP",83,2,1,be(150,2))
    gps += klv("GPSU",99,1,16,Data("241024171843.000".utf8))
    gps += klv(gps9 ? "GPS9" : "GPS5",108,row.count*4,2,(row+row2).reduce(into:Data()){$0 += be($1)})
    let accel = klv("SCAL",108,4,1,be(100))+klv("ACCL",115,6,2,[UInt64(100),200,300,200,300,400].reduce(into:Data()){$0 += be($1,2)})
    let body = stream(gps)+stream(accel)
    return klv("DEVC",0,1,body.count,body)
  }
  func movie(gps9:Bool = false,co64:Bool = false) -> Data {
    let a = packet(fix:3,gps9:gps9),b = packet(fix:0,gps9:gps9)
    let clock = Data(repeating:0,count:12)+be(1000)+be(3000)+Data(repeating:0,count:4)
    let description = atom("stsd",be(0)+be(1)+atom("gpmd",Data(repeating:0,count:8)))
    let sizes = atom("stsz",be(0)+be(0)+be(2)+be(UInt64(a.count))+be(UInt64(b.count)))
    let chunks = atom(co64 ? "co64" : "stco",be(0)+be(2)+be(8,co64 ? 8 : 4)+be(UInt64(8+a.count),co64 ? 8 : 4))
    let mapping = atom("stsc",be(0)+be(1)+be(1)+be(1)+be(1))
    let times = atom("stts",be(0)+be(1)+be(2)+be(1000))
    let table = atom("stbl",description+sizes+chunks+mapping+times)
    let edits = atom("edts",atom("elst",be(0)+be(2)+be(1000)+be(UInt64(UInt32.max))+be(1,2)+be(0,2)+be(2000)+be(0)+be(1,2)+be(0,2)))
    let track = atom("trak",edits+atom("mdia",atom("mdhd",clock)+atom("minf",table)))
    return atom("mdat",a+b)+atom("moov",atom("mvhd",clock)+track)
  }
  func fixture(_ data:Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
    try data.write(to:url);addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url
  }
  func testGPS5ScalingInvalidFixMovieZeroAndCameraAxes() throws {
    let url = try fixture(movie());XCTAssertTrue(try CameraTelemetry.isAvailable(in:url))
    let table = try CameraTelemetry.read(url)
    XCTAssertEqual(table.times.first,0);XCTAssertEqual(table.times.last,3)
    let data = try Telemetry(url:url)
    XCTAssertEqual(data.duration,3)
    XCTAssertNil(data.value("Latitude (deg)",at:0))
    XCTAssertEqual(try XCTUnwrap(data.value("Latitude (deg)",at:1)),10,accuracy:1e-9)
    XCTAssertEqual(data.speed(at:1,unit:"m/s"),10)
    XCTAssertNil(data.value("Latitude (deg)",at:2))
    XCTAssertEqual(try XCTUnwrap(data.value("Camera acceleration axis 1 (m/s²)",at:1)),1,accuracy:1e-9)
    XCTAssertEqual(try XCTUnwrap(data.value("GPS DOP",at:1)),1.5,accuracy:1e-9)
    XCTAssertNil(table.aliases["gx"]);XCTAssertNil(table.aliases["accuracy"])
    XCTAssertNotNil(data.firstSampleUnixTime)
    XCTAssertFalse(Telemetry.supportedExtensions.contains("mp4"))
  }
  func testGPS9And64BitChunkOffsets() throws {
    let table = try CameraTelemetry.read(fixture(movie(gps9:true,co64:true)))
    XCTAssertEqual(try XCTUnwrap(table.epoch),946684800+9000*86400+10-1,accuracy:1e-6)
    let row = try XCTUnwrap(table.times.firstIndex(of:1))
    XCTAssertEqual(table.columns[try XCTUnwrap(table.aliases["lat"])][row],10)
  }
  func testMalformedContainersAndMissingTrackFailSafely() throws {
    XCTAssertThrowsError(try CameraMP4.read(fixture(Data([0,0,0,4,109,111,111,118]))))
    var bad = movie();bad.removeLast(10)
    XCTAssertThrowsError(try CameraMP4.read(fixture(bad)))
    let clock = Data(repeating:0,count:12)+be(1000)+be(1000)
    let noTrack = try fixture(atom("moov",atom("mvhd",clock)))
    XCTAssertFalse(try CameraTelemetry.isAvailable(in:noTrack));XCTAssertThrowsError(try Telemetry(url:noTrack))
    var corrupt = movie();corrupt[8+4] = 255
    XCTAssertThrowsError(try CameraTelemetry.read(fixture(corrupt)))
  }
  func testLinkedCameraClockTrimRateLoopSyncAndPersistence() throws {
    var project = RaceProject();var camera = MediaInput(name:"Camera",path:"/example.mp4",kind:"video",legacyIndex:0)
    camera.duration = 10;camera.timing = InputTiming();camera.timing?.trimStart = 2;camera.timing?.trimEnd = 6;camera.timing?.projectStart = 1;camera.timing?.rate = 2;camera.timing?.loop = true
    var data = MediaInput(name:"Embedded",path:camera.path,kind:"data",legacyIndex:1);data.duration = 10;data.cameraVideoID = camera.id
    project.inputs = [camera,data];project.explicitDuration = 7
    XCTAssertEqual(project.sourceTime(for:1,at:1.5),3)
    XCTAssertEqual(project.sourceTime(for:1,at:3.5),3)
    try project.synchronize(inputIndex:1,sourceTime:3.2,projectTime:1.5)
    XCTAssertEqual(try XCTUnwrap(project.sourceTime(for:1,at:3.5)),3.2,accuracy:1e-8)
    XCTAssertEqual(project.placements.filter{$0.input.id == data.id}.count,3)
    project.inputs[0].timing?.rate = 1
    XCTAssertEqual(try XCTUnwrap(project.sourceTime(for:1,at:1.5)),2.7,accuracy:1e-8)
    let draft = try SequenceDraft(project:project,inputID:camera.id)
    let sequenced = try draft.applying(to:project)
    let physical = try XCTUnwrap(sequenced.inputs.first(where:{$0.joinedTo == camera.legacyIndex}))
    XCTAssertEqual(sequenced.inputs.first(where:{$0.kind == "data"})?.cameraVideoID,physical.id)
    XCTAssertEqual(sequenced.sourceTime(for:1,at:1.5),project.sourceTime(for:1,at:1.5))
    project.objects = [DisplayObject(name:"Speed",kind:.speed)]
    project.objects[0].inputIndex = 1
    let layout = try project.reusableLayout();XCTAssertTrue(layout.inputs.allSatisfy{$0.cameraVideoID == nil && $0.path.isEmpty})
    let bytes = try JSONEncoder().encode(project),loaded = try JSONDecoder().decode(RaceProject.self,from:bytes)
    XCTAssertEqual(loaded.inputs[1].cameraVideoID,camera.id)
  }
}
