//
//  HwIdentifiers.swift
//  MacHwInfo
//
//  Created by User on 4/11/24.
//

import Foundation
import CryptoKit

func getMainPort() -> mach_port_t {
    if #available(macOS 12.0, *) {
        return kIOMainPortDefault
    } else {
        return kIOMasterPortDefault
    }
}

func getMacAddress() -> Data {
    let filter = IOServiceMatching("IOEthernetInterface") as NSMutableDictionary
    filter["IOPropertyMatch"] = [
        "IOPrimaryInterface": true
    ] as CFDictionary
    
    var iterator: io_iterator_t = 0
    IOServiceGetMatchingServices(getMainPort(), filter, &iterator)
    
    let ethService = IOIteratorNext(iterator)
    
    var parentService: io_registry_entry_t = 0
    IORegistryEntryGetParentEntry(ethService, kIOServicePlane, &parentService)
    
    return getData(parentService, "IOMACAddress")!
}

//func getRootDiskUuid() -> String {
//    return (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString ?? ""
//}

func sysctl(name: String) -> String {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    var val = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &val, &size, nil, 0)
    return String(cString: val)
}

func getData(_ device: io_registry_entry_t, _ val: String) -> Data? {
    print("reading val " + val)
    let value = IORegistryEntryCreateCFProperty(device, val as CFString, kCFAllocatorDefault, 0)
    return (value?.takeRetainedValue() as? NSData) as Data?
}

func getString(_ device: io_registry_entry_t, _ val: String) -> String? {
    print("reading val " + val)
    let value = IORegistryEntryCreateCFProperty(device, val as CFString, kCFAllocatorDefault, 0)
    return (value?.takeRetainedValue() as? NSString) as String?
}

func getItem(_ device: io_registry_entry_t, _ val: String) -> String? {
    let value = getData(device, val)
    if value == nil {
        return nil
    }
    return String(data: value!, encoding: .utf8)
}

func getHwInfo() -> Bbhwinfo_HwInfo {
    let deviceTree = IORegistryEntryFromPath(getMainPort(), "IODeviceTree:/")
    
    let ioPower = IORegistryEntryFromPath(getMainPort(), "IOPower:/")
    
    let optionsTree = IORegistryEntryFromPath(getMainPort(), "IODeviceTree:/options")
    
    let chosenTree = IORegistryEntryFromPath(getMainPort(), "IODeviceTree:/chosen")
    
    var rom = getData(optionsTree, "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14:ROM")
    if rom == nil {
        // m1
        let uniqueChipId = getData(chosenTree, "unique-chip-id")!
        let digest = SHA256.hash(data: uniqueChipId)
        rom = Data(digest.suffix(6))
    }
    
    return Bbhwinfo_HwInfo.with {
        $0.inner = Bbhwinfo_HwInfo.InnerHwInfo.with({
            $0.productName = (getItem(deviceTree, "product-name") ?? getItem(deviceTree, "model")!).trimmingCharacters(in: CharacterSet(["\0"]))
            $0.ioMacAddress = getMacAddress()
            $0.platformSerialNumber = getString(deviceTree, "IOPlatformSerialNumber")!
            $0.platformUuid = getString(deviceTree, "IOPlatformUUID")!
            $0.rootDiskUuid = getItem(chosenTree, "boot-uuid")!.trimmingCharacters(in: CharacterSet(["\0"]))
            $0.boardID = getItem(deviceTree, "board-id")?.trimmingCharacters(in: CharacterSet(["\0"])) ?? "Mac-" + getData(chosenTree, "board-id")!.map { String(format: "%02hhx", $0) }.joined()
            $0.osBuildNum = sysctl(name: "kern.osversion")
            $0.platformSerialNumberEnc = getData(ioPower, "Gq3489ugfi")!
            $0.platformUuidEnc = getData(ioPower, "Fyp98tpgj")!
            $0.rootDiskUuidEnc = getData(ioPower, "kbjfrfpoJU")!
            $0.rom = rom!
            $0.romEnc = getData(ioPower, "oycqAZloTNDm")!
            $0.mlb = getItem(optionsTree, "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14:MLB") ?? getItem(deviceTree, "mlb-serial-number")!.trimmingCharacters(in: CharacterSet(["\0"]))
            $0.mlbEnc = getData(ioPower, "abKPld1EcMni")!
        })
        $0.version = sysctl(name: "kern.osproductversion")
        $0.protocolVersion = 1640
        $0.deviceID = getString(deviceTree, "IOPlatformUUID")!
        $0.icloudUa = "com.apple.iCloudHelper/282 CFNetwork/1408.0.4 Darwin/22.5.0"
        $0.aoskitVersion = "com.apple.AOSKit/282 (com.apple.accountsd/113)"
    }
}

