import Foundation
@testable import PhotonzMedia
import Testing
import VideoToolbox

/// Which encoder profile writes what a recording's sample description says
/// (`StoredWay`), read off real `avcC` bytes.
struct StoredWayTests {

    private func bytes(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return data
    }

    @Test func aMacScreenRecordingIsMainAtFivePointTwo() {
        // The avcC of a 3456 by 2234 recording the Mac's recorder wrote.
        let avcC = bytes("014d0034ffe10010274d0034ab2806c008cfc9350101010201000428ee3c80")
        #expect(StoredWay.h264Profile(avcC: avcC) == kVTProfileLevel_H264_Main_5_2)
    }

    @Test func highIsHighAtItsLevel() {
        let avcC = bytes("01640033ffe1001127640033ac56700d80119f926a0202020401000428ee3cb0fdf8f800")
        #expect(StoredWay.h264Profile(avcC: avcC) == kVTProfileLevel_H264_High_5_1)
    }

    @Test func aLevelWithNoSettingFallsBackToAutomatic() {
        #expect(StoredWay.h264Profile(avcC: bytes("014d000dffe1")) == kVTProfileLevel_H264_Main_AutoLevel)
    }

    @Test func constrainedBaselineIsItsOwnProfile() {
        #expect(StoredWay.h264Profile(avcC: bytes("0142c01fffe1"))
                == kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel)
    }

    @Test func anUnknownProfileOrABrokenRecordHasNone() {
        #expect(StoredWay.h264Profile(avcC: bytes("016e0034")) == nil)
        #expect(StoredWay.h264Profile(avcC: bytes("01")) == nil)
        #expect(StoredWay.h264Profile(avcC: bytes("024d0034")) == nil)
    }

    @Test func hevcMainAndMainTen() {
        #expect(StoredWay.hevcProfile(hvcC: bytes("0101")) == kVTProfileLevel_HEVC_Main_AutoLevel)
        #expect(StoredWay.hevcProfile(hvcC: bytes("0102")) == kVTProfileLevel_HEVC_Main10_AutoLevel)
        #expect(StoredWay.hevcProfile(hvcC: bytes("0104")) == nil)
    }
}
