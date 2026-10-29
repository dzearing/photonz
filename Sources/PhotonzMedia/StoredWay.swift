import CoreMedia
import Foundation
import VideoToolbox

/// How a video track stores its pictures: the parameter sets in its sample
/// description (`avcC` for H.264, `hvcC` for HEVC), and the encoder profile
/// that says the same thing again.
///
/// Frames encoded afresh into a file of copied frames have to be stored the
/// same way, or the file gains a second sample description that only
/// QuickTime follows (`PieceCopyWriter`).
enum StoredWay {

    /// The sample description's parameter sets, byte for byte, or nil where
    /// the format carries none.
    static func parameterSets(of format: CMFormatDescription) -> Data? {
        let atoms = CMFormatDescriptionGetExtension(
            format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
            as? [String: Any]
        return (atoms?["avcC"] as? Data) ?? (atoms?["hvcC"] as? Data)
    }

    /// The encoder profile and level that writes what this format says, or
    /// nil where there is no such setting (the encoder then picks its own,
    /// and the frames it makes will not match).
    static func encoderProfile(of format: CMFormatDescription) -> CFString? {
        let codec = CMFormatDescriptionGetMediaSubType(format)
        let atoms = CMFormatDescriptionGetExtension(
            format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
            as? [String: Any]
        if codec == kCMVideoCodecType_H264, let avcC = atoms?["avcC"] as? Data {
            return h264Profile(avcC: avcC)
        }
        if codec == kCMVideoCodecType_HEVC, let hvcC = atoms?["hvcC"] as? Data {
            return hevcProfile(hvcC: hvcC)
        }
        return nil
    }

    /// An `avcC` is a version byte, then the profile, its constraint flags
    /// and the level, each a byte.
    static func h264Profile(avcC: Data) -> CFString? {
        let bytes = [UInt8](avcC.prefix(4))
        guard bytes.count == 4, bytes[0] == 1 else { return nil }
        let profile = bytes[1], constraints = bytes[2], level = bytes[3]
        // Constrained Baseline is Baseline with constraint_set1 on.
        let constrained = constraints & 0x40 != 0
        let levels: [UInt8: (baseline: CFString, constrained: CFString?, main: CFString, high: CFString)] = [
            30: (kVTProfileLevel_H264_Baseline_3_0, nil, kVTProfileLevel_H264_Main_3_0, kVTProfileLevel_H264_High_3_0),
            31: (kVTProfileLevel_H264_Baseline_3_1, nil, kVTProfileLevel_H264_Main_3_1, kVTProfileLevel_H264_High_3_1),
            32: (kVTProfileLevel_H264_Baseline_3_2, nil, kVTProfileLevel_H264_Main_3_2, kVTProfileLevel_H264_High_3_2),
            40: (kVTProfileLevel_H264_Baseline_4_0, nil, kVTProfileLevel_H264_Main_4_0, kVTProfileLevel_H264_High_4_0),
            41: (kVTProfileLevel_H264_Baseline_4_1, nil, kVTProfileLevel_H264_Main_4_1, kVTProfileLevel_H264_High_4_1),
            42: (kVTProfileLevel_H264_Baseline_4_2, nil, kVTProfileLevel_H264_Main_4_2, kVTProfileLevel_H264_High_4_2),
            50: (kVTProfileLevel_H264_Baseline_5_0, nil, kVTProfileLevel_H264_Main_5_0, kVTProfileLevel_H264_High_5_0),
            51: (kVTProfileLevel_H264_Baseline_5_1, nil, kVTProfileLevel_H264_Main_5_1, kVTProfileLevel_H264_High_5_1),
            52: (kVTProfileLevel_H264_Baseline_5_2, nil, kVTProfileLevel_H264_Main_5_2, kVTProfileLevel_H264_High_5_2),
        ]
        switch profile {
        case 66:
            if constrained { return kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel }
            return levels[level]?.baseline ?? kVTProfileLevel_H264_Baseline_AutoLevel
        case 77:
            return levels[level]?.main ?? kVTProfileLevel_H264_Main_AutoLevel
        case 100:
            return levels[level]?.high ?? kVTProfileLevel_H264_High_AutoLevel
        default:
            return nil
        }
    }

    /// An `hvcC` is a version byte, then two bits of profile space, a tier
    /// bit and five bits of profile. The encoder takes no level for HEVC.
    static func hevcProfile(hvcC: Data) -> CFString? {
        let bytes = [UInt8](hvcC.prefix(2))
        guard bytes.count == 2, bytes[0] == 1 else { return nil }
        switch bytes[1] & 0x1F {
        case 1: return kVTProfileLevel_HEVC_Main_AutoLevel
        case 2: return kVTProfileLevel_HEVC_Main10_AutoLevel
        default: return nil
        }
    }
}
