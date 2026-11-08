import Foundation
import Testing

@testable import whoa_stash

@MainActor
struct DeviceStatusTests {

  @Test("le glyphe est choisi d'après le nom de l'appareil")
  func classifiesByName() {
    #expect(DeviceKind.classify(name: "AirPods Pro") == .airPodsPro)
    #expect(DeviceKind.classify(name: "Ugolin's AirPods Max") == .airPodsMax)
    #expect(DeviceKind.classify(name: "AirPods") == .airPods)
    #expect(DeviceKind.classify(name: "Beats Studio") == .beatsHeadphones)
    #expect(DeviceKind.classify(name: "JBL Flip", minorType: "Speaker") == .speaker)
    #expect(DeviceKind.classify(name: "WH-1000XM5") == .headphones)
  }

  @Test("des écouteurs prennent la bague sur le plus faible niveau, un niveau unique la barre")
  func indicatorStyle() {
    #expect(DeviceBattery(left: 80, right: 60).indicator == .ring(percent: 60))
    #expect(DeviceBattery(main: 82).indicator == .bar(percent: 82))
    #expect(DeviceBattery(caseLevel: 50).indicator == nil)
  }

  @Test("le JSON de system_profiler donne le niveau de l'appareil connecté")
  func parsesProfile() throws {
    let json = """
      {"SPBluetoothDataType":[{"device_connected":[
        {"AirPods Max":{"device_batteryLevelMain":"82%","device_minorType":"Headphones"}},
        {"Magic Mouse":{"device_minorType":"Mouse"}}]}]}
      """
    let data = try #require(json.data(using: .utf8))

    #expect(
      SystemProfilerBatteryReader.parse(data, deviceName: "AirPods Max") == DeviceBattery(main: 82))
    #expect(SystemProfilerBatteryReader.parse(data, deviceName: "Magic Mouse") == nil)
    #expect(SystemProfilerBatteryReader.parse(data, deviceName: "Absent") == nil)
  }

  @Test("l'argument de simulation décrit un appareil, avec ou sans niveau")
  func simulationArgument() {
    let max = DeviceStatus.fromLaunchArguments(["--simulate-bluetooth-device=airpodsmax,82"])
    #expect(max?.kind == .airPodsMax)
    #expect(max?.battery?.indicator == .bar(percent: 82))

    let bare = DeviceStatus.fromLaunchArguments(["--simulate-bluetooth-device=airpodsmax"])
    #expect(bare?.battery == nil)
  }
}
