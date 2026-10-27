import AVFoundation
import XCTest
@testable import RaceCore

final class StereoAudioSourceTests:XCTestCase {
  func testMonoNormalizationPreservesSamplesAndReusesCache() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer {try? FileManager.default.removeItem(at:root)}
    var wav = Data("RIFF".utf8)
    func u16(_ value:UInt16) { var v = value.littleEndian; withUnsafeBytes(of:&v){wav.append(contentsOf:$0)} }
    func u32(_ value:UInt32) { var v = value.littleEndian; withUnsafeBytes(of:&v){wav.append(contentsOf:$0)} }
    let frames = 4410
    u32(UInt32(36+frames*2)); wav.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(44100); u32(88200); u16(2); u16(16)
    wav.append(Data("data".utf8)); u32(UInt32(frames*2))
    for i in 0..<frames { u16(UInt16(bitPattern:Int16(8192*sin(Double(i)*2 * .pi*440/44100)))) }
    let url = root.appendingPathComponent("mono.wav"); try wav.write(to:url)
    let asset = AVURLAsset(url:url),cache = StereoAudioSource(root:root.appendingPathComponent("cache"))
    let tracks = try await asset.loadTracks(withMediaType:.audio)
    let track = try XCTUnwrap(tracks.first)
    let first = try await cache.source(asset:asset,track:track,url:url),second = try await cache.source(asset:asset,track:track,url:url)
    XCTAssertEqual(first.asset.url,second.asset.url)
    let passthrough = try await cache.source(asset:first.asset,track:first.track,url:first.asset.url)
    XCTAssertEqual(passthrough.asset.url,first.asset.url)
    let mono = try samples(asset:asset,track:track,channels:1),stereo = try samples(asset:first.asset,track:first.track,channels:2)
    let count = min(mono.count,stereo.count/2); XCTAssertGreaterThan(count,1000)
    var leftDifference:Float = 0,rightDifference:Float = 0
    for i in 0..<count {
      let leftIndex = i*2,rightIndex = leftIndex+1
      let original:Float = mono[i],left:Float = stereo[leftIndex],right:Float = stereo[rightIndex]
      let leftError:Float = abs(left-original),rightError:Float = abs(right-original)
      leftDifference = max(leftDifference,leftError); rightDifference = max(rightDifference,rightError)
    }
    XCTAssertLessThan(leftDifference,1e-6); XCTAssertLessThan(rightDifference,1e-6)
    let cachedDuration = try await first.asset.load(.duration).seconds; XCTAssertEqual(cachedDuration,0.1,accuracy:1.0/44100.0)
    let resampled = try await cache.source(asset:asset,track:track,url:url,sampleRate:22050)
    XCTAssertNotEqual(resampled.asset.url,first.asset.url)
    let formats = try await resampled.track.load(.formatDescriptions)
    let description = try XCTUnwrap(formats.first)
    let rate = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(description)).pointee.mSampleRate
    XCTAssertEqual(rate,22050)
    let resampledDuration = try await resampled.asset.load(.duration).seconds
    XCTAssertEqual(resampledDuration,0.1,accuracy:1.0/22050.0)
    let reusedRate = try await cache.source(asset:asset,track:track,url:url,sampleRate:22050)
    XCTAssertEqual(resampled.asset.url,reusedRate.asset.url)
    try Data().write(to:first.asset.url)
    let recovered = try await cache.source(asset:asset,track:track,url:url)
    XCTAssertFalse(try samples(asset:recovered.asset,track:recovered.track,channels:2).isEmpty)
  }
  func samples(asset:AVURLAsset,track:AVAssetTrack,channels:Int) throws -> [Float] {
    let reader = try AVAssetReader(asset:asset)
    let output = AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:44100,AVNumberOfChannelsKey:channels,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false])
    reader.add(output); XCTAssertTrue(reader.startReading())
    var values:[Float] = []
    while let sample = output.copyNextSampleBuffer(),let block = CMSampleBufferGetDataBuffer(sample) {
      let size = CMBlockBufferGetDataLength(block); var bytes = [Float](repeating:0,count:size/4)
      let result = bytes.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:size,destination:$0.baseAddress!)}
      XCTAssertEqual(result,kCMBlockBufferNoErr); values += bytes
    }
    XCTAssertEqual(reader.status,.completed); return values
  }
}
