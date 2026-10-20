import Cocoa
import SwiftUI
import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit
import Vision
import UniformTypeIdentifiers
import AudioToolbox
import ImageIO

// MARK: - 0. 단축키 및 파일명 일괄변환 패턴 설정 매니저 (UserDefaults 영구 저장)
class ShortcutSettings: ObservableObject {
    static let shared = ShortcutSettings()
    
    @Published var convertFlagsRaw: UInt {
        didSet { UserDefaults.standard.set(Int(convertFlagsRaw), forKey: "tangerine_sc_convert_v40") }
    }
    @Published var toolsFlagsRaw: UInt {
        didSet { UserDefaults.standard.set(Int(toolsFlagsRaw), forKey: "tangerine_sc_tools_v40") }
    }
    @Published var actionsFlagsRaw: UInt {
        didSet { UserDefaults.standard.set(Int(actionsFlagsRaw), forKey: "tangerine_sc_actions_v40") }
    }
    @Published var renamePattern: String {
        didSet { UserDefaults.standard.set(renamePattern, forKey: "tangerine_rename_pattern_v40") }
    }
    
    static let defaultConvertRaw: UInt = NSEvent.ModifierFlags.shift.rawValue
    static let defaultToolsRaw: UInt = NSEvent.ModifierFlags([.option, .shift]).rawValue
    static let defaultActionsRaw: UInt = NSEvent.ModifierFlags.control.rawValue
    static let defaultRenamePattern: String = "{YYYYMMDD}_{hhmmss}_{Originalname}"
    
    init() {
        let savedConv = UserDefaults.standard.integer(forKey: "tangerine_sc_convert_v40")
        let savedTools = UserDefaults.standard.integer(forKey: "tangerine_sc_tools_v40")
        let savedActions = UserDefaults.standard.integer(forKey: "tangerine_sc_actions_v40")
        let savedPattern = UserDefaults.standard.string(forKey: "tangerine_rename_pattern_v40")
        
        self.convertFlagsRaw = (savedConv != 0) ? UInt(savedConv) : Self.defaultConvertRaw
        self.toolsFlagsRaw = (savedTools != 0) ? UInt(savedTools) : Self.defaultToolsRaw
        self.actionsFlagsRaw = (savedActions != 0) ? UInt(savedActions) : Self.defaultActionsRaw
        self.renamePattern = (savedPattern?.isEmpty == false) ? savedPattern! : Self.defaultRenamePattern
    }
    
    var convertFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: convertFlagsRaw).intersection([.shift, .option, .control, .command])
    }
    var toolsFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: toolsFlagsRaw).intersection([.shift, .option, .control, .command])
    }
    var actionsFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: actionsFlagsRaw).intersection([.shift, .option, .control, .command])
    }
    
    func resetToTangerineDefaults() {
        convertFlagsRaw = Self.defaultConvertRaw
        toolsFlagsRaw = Self.defaultToolsRaw
        actionsFlagsRaw = Self.defaultActionsRaw
    }
    
    static func formatFlags(_ flags: NSEvent.ModifierFlags) -> String {
        let clean = flags.intersection([.control, .option, .shift, .command])
        var parts: [String] = []
        if clean.contains(.control) { parts.append("⌃ Control") }
        if clean.contains(.option) { parts.append("⌥ Option") }
        if clean.contains(.shift) { parts.append("⇧ Shift") }
        if clean.contains(.command) { parts.append("⌘ Command") }
        return parts.isEmpty ? "키를 눌러주세요..." : parts.joined(separator: " + ")
    }
    
    func matchWheelMode(for flags: NSEvent.ModifierFlags) -> WheelMode? {
        let clean = flags.intersection([.shift, .option, .control, .command])
        guard !clean.isEmpty else { return nil }
        let tFlags = toolsFlags; let aFlags = actionsFlags; let cFlags = convertFlags
        if clean == tFlags { return .tools }
        if clean == aFlags { return .actions }
        if clean == cFlags { return .convert }
        
        let candidates: [(WheelMode, NSEvent.ModifierFlags)] = [
            (.tools, tFlags), (.actions, aFlags), (.convert, cFlags)
        ].sorted { $0.1.rawValue.nonzeroBitCount > $1.1.rawValue.nonzeroBitCount }
        
        for (mode, req) in candidates where !req.isEmpty {
            if clean.isSuperset(of: req) { return mode }
        }
        return nil
    }
    
    // 촬영일자 및 파일 정보를 바탕으로 변환된 파일명 생성
    static func formatFileName(pattern: String, originalName: String, captureDate: Date, cameraModel: String, sequenceIndex: Int) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: captureDate)
        let m = cal.component(.month, from: captureDate)
        let d = cal.component(.day, from: captureDate)
        let hh = cal.component(.hour, from: captureDate)
        let mm = cal.component(.minute, from: captureDate)
        let ss = cal.component(.second, from: captureDate)
        
        let yyyyStr = String(format: "%04d", y)
        let yyStr = String(format: "%02d", y % 100)
        let mmMonthStr = String(format: "%02d", m)
        let ddStr = String(format: "%02d", d)
        let hhStr = String(format: "%02d", hh)
        let mmMinStr = String(format: "%02d", mm)
        let ssStr = String(format: "%02d", ss)
        let seqStr = String(format: "%03d", sequenceIndex)
        let cleanCam = cameraModel.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        
        var res = pattern
        let replacements: [(String, String)] = [
            ("{YYYYMMDD}", "\(yyyyStr)\(mmMonthStr)\(ddStr)"),
            ("{yyyyMMdd}", "\(yyyyStr)\(mmMonthStr)\(ddStr)"),
            ("{YYMMDD}", "\(yyStr)\(mmMonthStr)\(ddStr)"),
            ("{hhmmss}", "\(hhStr)\(mmMinStr)\(ssStr)"),
            ("{HHmmss}", "\(hhStr)\(mmMinStr)\(ssStr)"),
            ("{YYYY}", yyyyStr),
            ("{yyyy}", yyyyStr),
            ("{YY}", yyStr),
            ("{MM}", mmMonthStr),
            ("{DD}", ddStr),
            ("{dd}", ddStr),
            ("{hh}", hhStr),
            ("{HH}", hhStr),
            ("{mm}", mmMinStr),
            ("{ss}", ssStr),
            ("{filename}", originalName),
            ("{Filename}", originalName),
            ("{Originalname}", originalName),
            ("{originalname}", originalName),
            ("{OriginalName}", originalName),
            ("{Camera}", cleanCam.isEmpty ? "Camera" : cleanCam),
            ("{camera}", cleanCam.isEmpty ? "Camera" : cleanCam),
            ("{Seq}", seqStr),
            ("{seq}", seqStr)
        ]
        
        for (token, val) in replacements {
            res = res.replacingOccurrences(of: token, with: val)
        }
        res = res.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        return res.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 1. 작업 진행률 매니저
struct ActiveJob: Identifiable {
    let id: UUID
    let title: String
    var progress: Double
}

class JobProgressManager: ObservableObject {
    static let shared = JobProgressManager()
    @Published var jobs: [ActiveJob] = []
    var onUpdate: (() -> Void)?
    
    var overallProgress: Double? {
        guard !jobs.isEmpty else { return nil }
        return jobs.reduce(0.0) { $0 + $1.progress } / Double(jobs.count)
    }
    func startJob(title: String) -> UUID {
        let id = UUID()
        DispatchQueue.main.async {
            self.jobs.append(ActiveJob(id: id, title: title, progress: 0.0))
            self.onUpdate?()
        }
        return id
    }
    func updateJob(id: UUID, progress: Double) {
        DispatchQueue.main.async {
            if let idx = self.jobs.firstIndex(where: { $0.id == id }) {
                self.jobs[idx].progress = min(0.99, max(0.0, progress))
                self.onUpdate?()
            }
        }
    }
    func finishJob(id: UUID) {
        DispatchQueue.main.async {
            self.jobs.removeAll { $0.id == id }
            self.onUpdate?()
        }
    }
}

// MARK: - 2. 글로벌 상태 및 3종 휠 모델
enum WheelMode: String {
    case convert = "CONVERT"
    case tools = "TOOLS"
    case actions = "ACTIONS"
}

struct WheelItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let actionKey: String
    var estimatedSizeText: String? = nil
}

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var isDragging = false
    @Published var wheelMode: WheelMode = .convert
    @Published var draggedFiles: [URL] = []
    @Published var totalBytes: Int64 = 0
    @Published var totalSizeText: String = ""
    @Published var hoveredIndex: Int? = nil
    @Published var items: [WheelItem] = []
    
    var firstFileExtension: String {
        draggedFiles.first?.pathExtension.lowercased() ?? ""
    }
    
    func updateItems() {
        let ext = firstFileExtension
        let imageExts = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp", "gif", "avif", "arw", "cr2", "cr3", "nef", "dng", "orf", "raf"]
        let videoExts = ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
        let audioExts = ["mp3", "m4a", "wav", "flac", "ogg", "aac", "aiff", "caf"]
        var baseItems: [WheelItem] = []
        
        switch wheelMode {
        case .convert:
            if imageExts.contains(ext) {
                baseItems = [
                    WheelItem(title: "JPG", icon: "photo", actionKey: "conv_jpg"),
                    WheelItem(title: "PNG", icon: "photo.fill", actionKey: "conv_png"),
                    WheelItem(title: "WEBP", icon: "globe", actionKey: "conv_webp"),
                    WheelItem(title: "HEIC", icon: "camera", actionKey: "conv_heic"),
                    WheelItem(title: "TIFF", icon: "doc.richtext", actionKey: "conv_tiff"),
                    WheelItem(title: "BMP", icon: "square.grid.2x2", actionKey: "conv_bmp"),
                    WheelItem(title: "PDF", icon: "doc.fill", actionKey: "conv_pdf"),
                    WheelItem(title: "ICNS", icon: "app.dashed", actionKey: "conv_icns")
                ]
            } else if videoExts.contains(ext) {
                baseItems = [
                    WheelItem(title: "MP4", icon: "film", actionKey: "conv_mp4"),
                    WheelItem(title: "MOV", icon: "video", actionKey: "conv_mov"),
                    WheelItem(title: "GIF", icon: "sparkles.tv", actionKey: "conv_gif"),
                    WheelItem(title: "M4A (음원)", icon: "music.quarternote.3", actionKey: "conv_m4a"),
                    WheelItem(title: "MP3 (음원)", icon: "music.note", actionKey: "conv_mp3"),
                    WheelItem(title: "WAV (음원)", icon: "waveform", actionKey: "conv_wav"),
                    WheelItem(title: "MKV", icon: "play.rectangle", actionKey: "conv_mkv")
                ]
            } else if audioExts.contains(ext) {
                baseItems = [
                    WheelItem(title: "M4A", icon: "music.quarternote.3", actionKey: "conv_m4a"),
                    WheelItem(title: "WAV", icon: "waveform", actionKey: "conv_wav"),
                    WheelItem(title: "MP3", icon: "music.note", actionKey: "conv_mp3"),
                    WheelItem(title: "FLAC", icon: "hifispeaker", actionKey: "conv_flac"),
                    WheelItem(title: "AIFF", icon: "opticaldisc", actionKey: "conv_aiff"),
                    WheelItem(title: "CAF", icon: "speaker.wave.2", actionKey: "conv_caf")
                ]
            } else {
                baseItems = [
                    WheelItem(title: "ZIP 압축", icon: "doc.zipper", actionKey: "conv_zip"),
                    WheelItem(title: "TAR.GZ", icon: "archivebox", actionKey: "conv_targz"),
                    WheelItem(title: "PDF 변환", icon: "doc.richtext", actionKey: "conv_pdf")
                ]
            }
            let files = draggedFiles; let origTotal = totalBytes
            for i in 0..<baseItems.count {
                let targetExt = baseItems[i].actionKey.replacingOccurrences(of: "conv_", with: "")
                let estBytes = FileSizeEstimator.estimateConversionBytes(files: files, originalTotalBytes: origTotal, targetExt: targetExt)
                baseItems[i].estimatedSizeText = "~" + ByteCountFormatter.string(fromByteCount: estBytes, countStyle: .file)
            }
            items = baseItems
            if imageExts.contains(ext) {
                DispatchQueue.global(qos: .userInteractive).async {
                    var updated = baseItems
                    for i in 0..<updated.count {
                        let targetExt = updated[i].actionKey.replacingOccurrences(of: "conv_", with: "")
                        let exactBytes = FileSizeEstimator.exactImageConversionBytes(files: files, originalTotalBytes: origTotal, targetExt: targetExt)
                        updated[i].estimatedSizeText = "~" + ByteCountFormatter.string(fromByteCount: exactBytes, countStyle: .file)
                    }
                    DispatchQueue.main.async {
                        if self.isDragging && self.wheelMode == .convert { self.items = updated }
                    }
                }
            }
        case .tools:
            if imageExts.contains(ext) {
                items = [
                    WheelItem(title: "EDIT PHOTO", icon: "slider.horizontal.3", actionKey: "tool_edit_photo"),
                    WheelItem(title: "CROP", icon: "crop", actionKey: "tool_crop"),
                    WheelItem(title: "REDACT", icon: "eye.slash", actionKey: "tool_redact"),
                    WheelItem(title: "ADD BG", icon: "photo.artframe", actionKey: "tool_add_bg"),
                    WheelItem(title: "COMPRESS", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress"),
                    WheelItem(title: "RENAME", icon: "character.cursor.ibeam", actionKey: "tool_rename_date"),
                    WheelItem(title: "METADATA", icon: "tag", actionKey: "tool_metadata"),
                    WheelItem(title: "QR / PDF병합", icon: "qrcode.viewfinder", actionKey: "tool_qr_or_pdf")
                ]
            } else if audioExts.contains(ext) || videoExts.contains(ext) {
                items = [
                    WheelItem(title: "TRIM / 편집", icon: "scissors", actionKey: "tool_audio_video_trim"),
                    WheelItem(title: "CHANNELS", icon: "speaker.wave.3", actionKey: "tool_audio_channels"),
                    WheelItem(title: "COMPRESS", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress"),
                    WheelItem(title: "RENAME", icon: "character.cursor.ibeam", actionKey: "tool_rename_date"),
                    WheelItem(title: "BLEEP (삐-)", icon: "waveform.badge.exclamationmark", actionKey: "tool_audio_bleep"),
                    WheelItem(title: "메타데이터 삭제", icon: "trash.slash", actionKey: "tool_strip_meta")
                ]
            } else {
                items = [
                    WheelItem(title: "RENAME (일자)", icon: "character.cursor.ibeam", actionKey: "tool_rename_date"),
                    WheelItem(title: "ZIP 압축", icon: "doc.zipper", actionKey: "conv_zip"),
                    WheelItem(title: "PDF 병합", icon: "doc.on.doc.fill", actionKey: "tool_merge_pdf"),
                    WheelItem(title: "용량 압축", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress"),
                    WheelItem(title: "메타데이터 삭제", icon: "tag.slash", actionKey: "tool_strip_meta")
                ]
            }
        case .actions:
            items = [
                WheelItem(title: "촬영일자 이름변경", icon: "character.cursor.ibeam", actionKey: "tool_rename_date"),
                WheelItem(title: "경로 복사", icon: "doc.on.clipboard", actionKey: "act_copy_path"),
                WheelItem(title: "터미널 열기", icon: "terminal", actionKey: "act_terminal"),
                WheelItem(title: "AirDrop", icon: "airplayaudio", actionKey: "act_airdrop"),
                WheelItem(title: "Finder 표시", icon: "folder", actionKey: "act_finder"),
                WheelItem(title: "사본 만들기", icon: "plus.square.on.square", actionKey: "act_duplicate")
            ]
        }
    }
}

// MARK: - 3. 변환 및 압축 파일 예상 크기 계산 엔진
class FileSizeEstimator {
    static func estimateConversionBytes(files: [URL], originalTotalBytes: Int64, targetExt: String) -> Int64 {
        guard let first = files.first, originalTotalBytes > 0 else { return 0 }
        let srcExt = first.pathExtension.lowercased()
        let tgt = targetExt.lowercased()
        if srcExt == tgt { return originalTotalBytes }
        
        let videoExts = ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
        let audioExts = ["mp3", "m4a", "wav", "flac", "ogg", "aac", "aiff", "caf"]
        
        if videoExts.contains(srcExt) || audioExts.contains(srcExt) {
            let totalDuration = files.reduce(0.0) { $0 + FileProcessor.mediaDurationSeconds(for: $1) }
            if totalDuration > 0 {
                switch tgt {
                case "mp3", "m4a", "aac", "caf", "ogg": return max(4096, Int64(totalDuration * 24_000))
                case "wav", "aiff": return max(8192, Int64(totalDuration * 176_400))
                case "flac": return max(8192, Int64(totalDuration * 96_000))
                case "gif": return max(10_240, Int64(totalDuration * 380_000))
                case "mp4", "mov", "mkv":
                    let ratio: Double = (srcExt == "mov") ? 0.68 : 0.88
                    return max(16_384, Int64(Double(originalTotalBytes) * ratio))
                default: break
                }
            }
        }
        let weights: [String: Double] = [
            "bmp": 3.2, "tiff": 2.4, "png": 1.0, "pdf": 0.95,
            "jpg": 0.36, "jpeg": 0.36, "heic": 0.22, "webp": 0.25,
            "icns": 0.45, "zip": 0.72, "targz": 0.68
        ]
        let srcW = weights[srcExt] ?? 1.0
        let tgtW = weights[tgt] ?? 0.85
        return max(1024, Int64(Double(originalTotalBytes) * (tgtW / srcW)))
    }
    
    static func exactImageConversionBytes(files: [URL], originalTotalBytes: Int64, targetExt: String) -> Int64 {
        guard let first = files.first,
              let attrs = try? FileManager.default.attributesOfItem(atPath: first.path),
              let firstOrigSize = attrs[.size] as? Int64, firstOrigSize > 0,
              let cg = FileProcessor.loadRawCGImage(from: first) else {
            return estimateConversionBytes(files: files, originalTotalBytes: originalTotalBytes, targetExt: targetExt)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        let tgt = targetExt.lowercased()
        var sampleDataSize: Int64? = nil
        switch tgt {
        case "jpg", "jpeg": sampleDataSize = Int64(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.count ?? 0)
        case "png": sampleDataSize = Int64(rep.representation(using: .png, properties: [:])?.count ?? 0)
        case "tiff": sampleDataSize = Int64(rep.representation(using: .tiff, properties: [:])?.count ?? 0)
        case "bmp": sampleDataSize = Int64(rep.representation(using: .bmp, properties: [:])?.count ?? 0)
        case "heic", "webp":
            if let jpgCount = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.count {
                sampleDataSize = Int64(Double(jpgCount) * 0.62)
            }
        case "pdf":
            if let jpgCount = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.90])?.count {
                sampleDataSize = Int64(jpgCount + 4096)
            }
        default: break
        }
        if let sSize = sampleDataSize, sSize > 0 {
            return max(1024, Int64(Double(originalTotalBytes) * (Double(sSize) / Double(firstOrigSize))))
        }
        return estimateConversionBytes(files: files, originalTotalBytes: originalTotalBytes, targetExt: targetExt)
    }
    
    static func estimateCompressedBytes(files: [URL], quality: Double) -> (original: Int64, estimated: Int64) {
        var origTotal: Int64 = 0; var estTotal: Int64 = 0
        for (index, f) in files.enumerated() {
            let fSize = (try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64) ?? 0
            origTotal += fSize
            let ext = f.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "webp"].contains(ext) {
                if index == 0, let cg = FileProcessor.loadRawCGImage(from: f) {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality / 100.0]) {
                        estTotal += Int64(data.count); continue
                    }
                }
                let ratio = pow(quality / 100.0, 1.35) * (ext == "png" || ext == "tiff" || ext == "bmp" ? 0.45 : 0.85)
                estTotal += max(1024, Int64(Double(fSize) * ratio))
            } else {
                let crf = 40.0 - (quality / 100.0) * 20.0
                let ratio = min(0.95, max(0.08, pow(2.0, (23.0 - crf) / 6.0) * 0.78))
                estTotal += max(4096, Int64(Double(fSize) * ratio))
            }
        }
        return (origTotal, estTotal)
    }
}

// MARK: - 4. 파일 처리, 메타데이터 100% 보존 및 촬영일자 이름 일괄변환 엔진
class FileProcessor {
    static var ffmpegPath: String? {
        let candidates = [
            Bundle.main.path(forResource: "ffmpeg", ofType: nil),
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg"
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    
    static func uniqueOutputURL(for url: URL, newExt: String, suffix: String = "") -> URL {
        let folder = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent + suffix
        var outURL = folder.appendingPathComponent("\(baseName).\(newExt)")
        var counter = 1
        while FileManager.default.fileExists(atPath: outURL.path) {
            outURL = folder.appendingPathComponent("\(baseName)_\(counter).\(newExt)")
            counter += 1
        }
        return outURL
    }
    
    // 원본 파일의 생성일/수정일 등 파일 시스템 속성까지 새 파일에 그대로 복사
    static func preserveFileDates(from src: URL, to dst: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: src.path) else { return }
        var newAttrs: [FileAttributeKey: Any] = [:]
        if let cDate = attrs[.creationDate] { newAttrs[.creationDate] = cDate }
        if let mDate = attrs[.modificationDate] { newAttrs[.modificationDate] = mDate }
        if !newAttrs.isEmpty {
            try? FileManager.default.setAttributes(newAttrs, ofItemAtPath: dst.path)
        }
    }
    
    // 사진(EXIF/TIFF), 영상(QuickTime), 일반 파일에서 실제 촬영일자(Capture Date)와 카메라 모델 추출
    static func extractCaptureDateAndCamera(for url: URL) -> (date: Date, camera: String) {
        var cameraModel = ""
        let exirDateFormatter = DateFormatter()
        exirDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        exirDateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        
        // 1) 이미지/RAW 파일의 EXIF 및 TIFF 메타데이터에서 촬영일자 추출
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let model = tiff[kCGImagePropertyTIFFModel] as? String {
                cameraModel = model
            }
            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                if let dtOrig = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
                   let d = exirDateFormatter.date(from: dtOrig) {
                    return (d, cameraModel)
                }
                if let dtDig = exif[kCGImagePropertyExifDateTimeDigitized] as? String,
                   let d = exirDateFormatter.date(from: dtDig) {
                    return (d, cameraModel)
                }
            }
            if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let dtTiff = tiff[kCGImagePropertyTIFFDateTime] as? String,
               let d = exirDateFormatter.date(from: dtTiff) {
                return (d, cameraModel)
            }
        }
        
        // 2) Spotlight / MDItem 메타데이터(영상 촬영일 kMDItemContentCreationDate) 확인
        if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) {
            if let contentDate = MDItemCopyAttribute(mdItem, kMDItemContentCreationDate) as? Date {
                return (contentDate, cameraModel)
            }
        }
        
        // 3) 파일 생성일(Creation Date) 또는 수정일 폴백
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let cDate = attrs[.creationDate] as? Date { return (cDate, cameraModel) }
            if let mDate = attrs[.modificationDate] as? Date { return (mDate, cameraModel) }
        }
        return (Date(), cameraModel)
    }
    
    // 설정된 패턴(예: {YYYYMMDD}_{hhmmss}_{Originalname})으로 파일 이름 일괄 변경 실행
    static func batchRenameFilesWithCaptureDate(files: [URL]) {
        let pattern = ShortcutSettings.shared.renamePattern
        var renamedCount = 0
        var lastNewName = ""
        
        for (idx, fileURL) in files.enumerated() {
            let folder = fileURL.deletingLastPathComponent()
            let ext = fileURL.pathExtension
            let origName = fileURL.deletingPathExtension().lastPathComponent
            let info = extractCaptureDateAndCamera(for: fileURL)
            
            let newBaseName = ShortcutSettings.formatFileName(
                pattern: pattern,
                originalName: origName,
                captureDate: info.date,
                cameraModel: info.camera,
                sequenceIndex: idx + 1
            )
            
            guard !newBaseName.isEmpty, newBaseName != origName else { continue }
            
            var targetURL = ext.isEmpty ? folder.appendingPathComponent(newBaseName) : folder.appendingPathComponent("\(newBaseName).\(ext)")
            var dupCounter = 1
            while FileManager.default.fileExists(atPath: targetURL.path) && targetURL.path != fileURL.path {
                targetURL = ext.isEmpty ?
                    folder.appendingPathComponent("\(newBaseName)_\(dupCounter)") :
                    folder.appendingPathComponent("\(newBaseName)_\(dupCounter).\(ext)")
                dupCounter += 1
            }
            
            do {
                try FileManager.default.moveItem(at: fileURL, to: targetURL)
                renamedCount += 1
                lastNewName = targetURL.lastPathComponent
                
                // 만약 같은 이름의 .xmp 사이드카 파일이 존재하면 함께 이름 변경
                let xmpSource = fileURL.deletingPathExtension().appendingPathExtension("xmp")
                if FileManager.default.fileExists(atPath: xmpSource.path) {
                    let xmpTarget = targetURL.deletingPathExtension().appendingPathExtension("xmp")
                    try? FileManager.default.moveItem(at: xmpSource, to: xmpTarget)
                }
                let xmpUpperSource = fileURL.deletingPathExtension().appendingPathExtension("XMP")
                if FileManager.default.fileExists(atPath: xmpUpperSource.path) {
                    let xmpUpperTarget = targetURL.deletingPathExtension().appendingPathExtension("XMP")
                    try? FileManager.default.moveItem(at: xmpUpperSource, to: xmpUpperTarget)
                }
            } catch {
                continue
            }
        }
        
        if renamedCount == 1 {
            showToast("이름 변경 완료: \(lastNewName)")
        } else if renamedCount > 1 {
            showToast("총 \(renamedCount)개 파일 촬영일자 이름 변경 완료!")
        } else {
            showToast("이름이 이미 적용되어 있거나 변경할 수 없습니다.")
        }
    }
    
    static func mediaDurationSeconds(for url: URL) -> Double {
        var result: Double = 0
        let sem = DispatchSemaphore(value: 0)
        let asset = AVURLAsset(url: url)
        Task {
            if let dur = try? await asset.load(.duration) {
                let sec = CMTimeGetSeconds(dur)
                if sec.isFinite && sec > 0 { result = sec }
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 1.5)
        return result
    }
    
    static func runFFmpegWithProgress(args: [String], totalDuration: Double, jobTitle: String, completion: @escaping (Bool) -> Void) {
        guard let ffmpeg = ffmpegPath else { completion(false); return }
        let jobID = JobProgressManager.shared.startJob(title: jobTitle)
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: ffmpeg)
            task.arguments = args
            let pipe = Pipe()
            task.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                if totalDuration > 0, let currentSec = parseFFmpegTime(from: line) {
                    JobProgressManager.shared.updateJob(id: jobID, progress: min(0.99, max(0.01, currentSec / totalDuration)))
                }
            }
            do {
                try task.run()
                task.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                JobProgressManager.shared.finishJob(id: jobID)
                DispatchQueue.main.async { completion(task.terminationStatus == 0) }
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                JobProgressManager.shared.finishJob(id: jobID)
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    static func parseFFmpegTime(from log: String) -> Double? {
        guard let range = log.range(of: "time=") else { return nil }
        let timeStr = String(log[range.upperBound...].prefix(11))
        let parts = timeStr.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]), let m = Double(parts[1]),
              let s = Double(parts[2].split(separator: " ").first ?? "") else { return nil }
        return h * 3600.0 + m * 60.0 + s
    }
    
    static func runShell(_ launchPath: String, args: [String], completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: launchPath)
            task.arguments = args
            do {
                try task.run()
                task.waitUntilExit()
                DispatchQueue.main.async { completion(task.terminationStatus == 0) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    static func execute(actionKey: String, files: [URL]) {
        guard !files.isEmpty else { return }
        if actionKey == "tool_rename_date" {
            batchRenameFilesWithCaptureDate(files: files)
            return
        }
        if actionKey == "tool_edit_photo", let first = files.first { ToolWindowManager.shared.showEditPhotoWindow(url: first); return }
        if actionKey == "tool_crop", let first = files.first { ToolWindowManager.shared.showRedactCropWindow(url: first, initialTab: 1); return }
        if actionKey == "tool_redact", let first = files.first { ToolWindowManager.shared.showRedactCropWindow(url: first, initialTab: 0); return }
        if actionKey == "tool_add_bg", let first = files.first { ToolWindowManager.shared.showAddBGWindow(url: first); return }
        if actionKey == "tool_compress" { ToolWindowManager.shared.showCompressWindow(urls: files); return }
        if actionKey == "tool_metadata", let first = files.first { ToolWindowManager.shared.showMetadataWindow(url: first); return }
        if ["tool_audio_video_trim", "tool_audio_channels", "tool_audio_bleep"].contains(actionKey), let first = files.first {
            ToolWindowManager.shared.showMediaStudioWindow(url: first, initialTab: actionKey); return
        }
        if actionKey == "tool_qr_or_pdf" {
            if files.count > 1 { mergeToPDF(files: files) }
            else if let first = files.first { readQRCode(from: first) }
            return
        }
        if actionKey == "tool_merge_pdf" { mergeToPDF(files: files); return }
        
        if actionKey == "act_copy_path" {
            let paths = files.map { $0.path }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths, forType: .string)
            showToast("파일 경로가 클립보드에 복사되었습니다.")
            return
        }
        if actionKey == "act_terminal", let first = files.first {
            let folder = first.hasDirectoryPath ? first.path : first.deletingLastPathComponent().path
            runShell("/usr/bin/open", args: ["-a", "Terminal", folder]) { _ in }
            return
        }
        if actionKey == "act_finder" { NSWorkspace.shared.activateFileViewerSelecting(files); return }
        if actionKey == "act_airdrop" {
            if let service = NSSharingService(named: .sendViaAirDrop) { service.perform(withItems: files) }
            return
        }
        if actionKey == "act_duplicate" {
            for f in files {
                let out = uniqueOutputURL(for: f, newExt: f.pathExtension, suffix: "_copy")
                try? FileManager.default.copyItem(at: f, to: out)
                preserveFileDates(from: f, to: out)
            }
            showToast("사본 생성 완료!")
            return
        }
        for file in files {
            if actionKey.hasPrefix("conv_") {
                convertFile(file, to: actionKey.replacingOccurrences(of: "conv_", with: ""))
            } else if actionKey == "tool_strip_meta" {
                stripMetadata(file: file)
            }
        }
    }
    
    static func convertFile(_ file: URL, to ext: String) {
        if ext == "zip" {
            let out = uniqueOutputURL(for: file, newExt: "zip")
            runShell("/usr/bin/ditto", args: ["-c", "-k", "--sequesterRsrc", file.path, out.path]) { _ in
                preserveFileDates(from: file, to: out)
                showToast("ZIP 압축 완료: \(out.lastPathComponent)")
            }
            return
        }
        if ext == "targz" {
            let out = uniqueOutputURL(for: file, newExt: "tar.gz")
            runShell("/usr/bin/tar", args: ["-czf", out.path, "-C", file.deletingLastPathComponent().path, file.lastPathComponent]) { _ in
                preserveFileDates(from: file, to: out)
                showToast("TAR.GZ 압축 완료: \(out.lastPathComponent)")
            }
            return
        }
        
        // 이미지 포맷 변환 시 원본 EXIF/GPS/TIFF 메타데이터를 100% 보존하여 변환
        let cgSupportedExts = ["jpg", "jpeg", "png", "heic", "tiff", "bmp"]
        if cgSupportedExts.contains(ext), let cgImg = loadRawCGImage(from: file) {
            let out = uniqueOutputURL(for: file, newExt: ext)
            if saveCGImage(cgImg, to: out, formatExt: ext, quality: 0.94, sourceURLForMetadata: file) {
                preserveFileDates(from: file, to: out)
                showToast("\(ext.uppercased()) 변환 완료 (메타데이터 보존됨)!")
                return
            }
        }
        
        let sipsFormats = ["jpg": "jpeg", "png": "png", "heic": "heic", "tiff": "tiff", "bmp": "bmp", "icns": "icns"]
        if let sipsFormat = sipsFormats[ext] {
            let out = uniqueOutputURL(for: file, newExt: ext)
            runShell("/usr/bin/sips", args: ["-s", "format", sipsFormat, file.path, "--out", out.path]) { ok in
                if ok {
                    preserveFileDates(from: file, to: out)
                    showToast("\(ext.uppercased()) 변환 완료!")
                } else {
                    convertMediaHybrid(file, to: ext)
                }
            }
            return
        }
        if ext == "pdf", let img = NSImage(contentsOf: file) {
            let out = uniqueOutputURL(for: file, newExt: "pdf")
            let pdf = PDFDocument()
            if let page = PDFPage(image: img) {
                pdf.insert(page, at: 0); pdf.write(to: out)
                preserveFileDates(from: file, to: out)
                showToast("PDF 변환 완료: \(out.lastPathComponent)")
                return
            }
        }
        convertMediaHybrid(file, to: ext)
    }
    
    static func convertMediaHybrid(_ file: URL, to ext: String) {
        let out = uniqueOutputURL(for: file, newExt: ext)
        let duration = mediaDurationSeconds(for: file)
        let jobTitle = "\(file.lastPathComponent) → \(ext.uppercased())"
        if ffmpegPath != nil {
            // -map_metadata 0 옵션을 통해 원본 영상/오디오의 촬영일·태그 메타데이터를 그대로 보존
            var args = ["-y", "-i", file.path, "-map_metadata", "0"]
            if ext == "mp4" { args += ["-movflags", "use_metadata_tags", "-c:v", "libx264", "-preset", "fast", "-crf", "22", "-c:a", "aac", "-pix_fmt", "yuv420p", out.path] }
            else if ext == "mov" { args += ["-movflags", "use_metadata_tags", "-c:v", "libx264", "-c:a", "aac", out.path] }
            else if ext == "gif" { args += ["-vf", "fps=12,scale=640:-1:flags=lanczos", out.path] }
            else if ext == "mp3" { args += ["-vn", "-c:a", "libmp3lame", "-q:a", "2", out.path] }
            else if ext == "m4a" { args += ["-vn", "-c:a", "aac", "-b:a", "192k", out.path] }
            else if ext == "wav" { args += ["-vn", "-c:a", "pcm_s16le", out.path] }
            else if ext == "flac" { args += ["-vn", "-c:a", "flac", out.path] }
            else { args.append(out.path) }
            runFFmpegWithProgress(args: args, totalDuration: duration, jobTitle: jobTitle) { ok in
                if ok && FileManager.default.fileExists(atPath: out.path) {
                    preserveFileDates(from: file, to: out)
                    showToast("\(ext.uppercased()) 변환 완료: \(out.lastPathComponent)")
                } else {
                    try? FileManager.default.removeItem(at: out)
                    avAssetConvertWithProgress(file: file, to: ext, outURL: out, jobTitle: jobTitle)
                }
            }
        } else {
            avAssetConvertWithProgress(file: file, to: ext, outURL: out, jobTitle: jobTitle)
        }
    }
    
    static func avAssetConvertWithProgress(file: URL, to ext: String, outURL: URL, jobTitle: String) {
        let asset = AVURLAsset(url: file)
        let isAudioOnly = ["m4a", "mp3", "wav", "aiff", "flac", "caf"].contains(ext)
        let preset = isAudioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            showToast("변환기를 초기화할 수 없습니다."); return
        }
        var targetURL = outURL
        if isAudioOnly { targetURL = uniqueOutputURL(for: file, newExt: "m4a"); exporter.outputFileType = .m4a }
        else if ext == "mp4" { exporter.outputFileType = .mp4 }
        else { exporter.outputFileType = .mov }
        exporter.outputURL = targetURL
        
        let jobID = JobProgressManager.shared.startJob(title: jobTitle)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            JobProgressManager.shared.updateJob(id: jobID, progress: Double(exporter.progress))
        }
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                timer.invalidate()
                JobProgressManager.shared.finishJob(id: jobID)
                if exporter.status == .completed {
                    preserveFileDates(from: file, to: targetURL)
                    if ["wav", "aiff", "flac", "caf"].contains(ext) {
                        let finalURL = uniqueOutputURL(for: file, newExt: ext)
                        let fmt = ext == "wav" ? "WAVE" : (ext == "aiff" ? "AIFF" : (ext == "caf" ? "caff" : "flac"))
                        let dat = ext == "flac" ? "flac" : (ext == "wav" ? "LEI16" : (ext == "caf" ? "aac" : "BEI16"))
                        runShell("/usr/bin/afconvert", args: ["-f", fmt, "-d", dat, targetURL.path, finalURL.path]) { ok in
                            try? FileManager.default.removeItem(at: targetURL)
                            preserveFileDates(from: file, to: finalURL)
                            showToast(ok ? "\(ext.uppercased()) 변환 완료!" : "변환 완료: \(targetURL.lastPathComponent)")
                        }
                    } else {
                        showToast("변환 완료: \(targetURL.lastPathComponent)")
                    }
                } else {
                    showToast("변환 실패: \(exporter.error?.localizedDescription ?? "지원되지 않는 형식")")
                }
            }
        }
    }
    
    // 사용자가 명시적으로 '메타데이터 삭제'를 눌렀을 때만 메타데이터를 제거함
    static func stripMetadata(file: URL) {
        let out = uniqueOutputURL(for: file, newExt: file.pathExtension, suffix: "_clean")
        if let cgImg = loadRawCGImage(from: file) {
            _ = saveCGImage(cgImg, to: out, formatExt: file.pathExtension, quality: 0.95, sourceURLForMetadata: nil)
            showToast("메타데이터 제거 완료: \(out.lastPathComponent)")
        } else if ffmpegPath != nil {
            let dur = mediaDurationSeconds(for: file)
            runFFmpegWithProgress(args: ["-y", "-i", file.path, "-map_metadata", "-1", "-c", "copy", out.path], totalDuration: dur, jobTitle: "메타데이터 삭제") { _ in
                showToast("미디어 메타데이터 제거 완료!")
            }
        }
    }
    
    static func loadRawCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
    
    // MARK: 핵심 — CGImageDestination을 사용하여 원본 사진의 EXIF/GPS/TIFF/IPTC 메타데이터를 손실 없이 그대로 복사하여 저장
    @discardableResult
    static func saveCGImage(_ cgImage: CGImage, to url: URL, formatExt: String, quality: Double = 0.95, sourceURLForMetadata: URL? = nil) -> Bool {
        let ext = formatExt.lowercased()
        let utType: CFString
        switch ext {
        case "png": utType = UTType.png.identifier as CFString
        case "heic": utType = UTType.heic.identifier as CFString
        case "tiff", "tif": utType = UTType.tiff.identifier as CFString
        case "bmp": utType = UTType.bmp.identifier as CFString
        case "gif": utType = UTType.gif.identifier as CFString
        default: utType = UTType.jpeg.identifier as CFString
        }
        
        var metadataProps: [CFString: Any] = [:]
        if let srcURL = sourceURLForMetadata,
           let src = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
           let origProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            metadataProps = origProps
            // 회전 방향은 이미 CGImage 픽셀에 반영되었거나 동일하므로 정상 방향(1)으로 유지 및 해상도 갱신
            metadataProps[kCGImagePropertyPixelWidth] = cgImage.width
            metadataProps[kCGImagePropertyPixelHeight] = cgImage.height
        }
        metadataProps[kCGImageDestinationLossyCompressionQuality] = quality
        
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) {
            CGImageDestinationAddImage(dest, cgImage, metadataProps as CFDictionary)
            if CGImageDestinationFinalize(dest) {
                if let srcURL = sourceURLForMetadata {
                    preserveFileDates(from: srcURL, to: url)
                }
                return true
            }
        }
        
        // 폴백 저장
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let data: Data?
        if ext == "png" { data = rep.representation(using: .png, properties: [:]) }
        else if ext == "tiff" { data = rep.representation(using: .tiff, properties: [:]) }
        else if ext == "bmp" { data = rep.representation(using: .bmp, properties: [:]) }
        else { data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) }
        do {
            try data?.write(to: url)
            if let srcURL = sourceURLForMetadata { preserveFileDates(from: srcURL, to: url) }
            return true
        } catch {
            return false
        }
    }
    
    static func readQRCode(from url: URL) {
        guard let ciImage = CIImage(contentsOf: url) else { return }
        let request = VNDetectBarcodesRequest { req, _ in
            if let results = req.results as? [VNBarcodeObservation], let payload = results.first?.payloadStringValue {
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(payload, forType: .string)
                    let alert = NSAlert()
                    alert.messageText = "QR 코드 인식 성공 (클립보드 복사됨)"
                    alert.informativeText = payload
                    alert.runModal()
                }
            } else {
                DispatchQueue.main.async { showToast("이미지에서 QR 코드를 찾지 못했습니다.") }
            }
        }
        try? VNImageRequestHandler(ciImage: ciImage, options: [:]).perform([request])
    }
    
    static func mergeToPDF(files: [URL]) {
        guard let first = files.first else { return }
        let pdf = PDFDocument()
        for f in files {
            if f.pathExtension.lowercased() == "pdf", let sub = PDFDocument(url: f) {
                for i in 0..<sub.pageCount { if let page = sub.page(at: i) { pdf.insert(page, at: pdf.pageCount) } }
            } else if let img = NSImage(contentsOf: f), let page = PDFPage(image: img) {
                pdf.insert(page, at: pdf.pageCount)
            }
        }
        let out = uniqueOutputURL(for: first, newExt: "pdf", suffix: "_merged")
        pdf.write(to: out)
        preserveFileDates(from: first, to: out)
        showToast("PDF 병합 완료: \(out.lastPathComponent)")
    }
    
    static func showToast(_ message: String) {
        DispatchQueue.main.async { ToolWindowManager.shared.showBanner(message: message) }
    }
}

// MARK: - 5. 마우스 휠 확대/축소 감지 뷰 및 원형 다이얼 휠 UI
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    func makeNSView(context: Context) -> ScrollWheelNSView {
        let v = ScrollWheelNSView(); v.onScroll = onScroll; return v
    }
    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) { nsView.onScroll = onScroll }
    class ScrollWheelNSView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            if abs(event.scrollingDeltaY) > 0.01 { onScroll?(event.scrollingDeltaY) }
        }
    }
}

struct PieSliceShape: Shape {
    var startAngle: Angle; var endAngle: Angle; var innerRadiusRatio: CGFloat = 0.35
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusRatio
        var path = Path()
        path.addArc(center: center, radius: innerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: outerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct RadialWheelView: View {
    @ObservedObject var state = AppState.shared
    let wheelSize: CGFloat = 324
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: wheelSize + 16, height: wheelSize + 16)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 8)
            slicesView
            centerBadgeView
        }.frame(width: wheelSize + 30, height: wheelSize + 30)
    }
    var slicesView: some View {
        let count = max(state.items.count, 1)
        let angleStep = 360.0 / Double(count)
        return ForEach(0..<state.items.count, id: \.self) { index in sliceItemView(index: index, angleStep: angleStep) }
    }
    func sliceItemView(index: Int, angleStep: Double) -> some View {
        let item = state.items[index]
        let start = Angle(degrees: Double(index) * angleStep - 90.0 - angleStep / 2.0 + 1.8)
        let end = Angle(degrees: Double(index + 1) * angleStep - 90.0 - angleStep / 2.0 - 1.8)
        let midAngle = (start.radians + end.radians) / 2.0
        let isHovered = (state.hoveredIndex == index)
        let labelRadius = (wheelSize / 2.0) * 0.68
        let fillGrad = isHovered ?
            LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing) :
            LinearGradient(colors: [Color.white.opacity(0.78), Color.white.opacity(0.48)], startPoint: .top, endPoint: .bottom)
        return ZStack {
            PieSliceShape(startAngle: start, endAngle: end).fill(fillGrad)
                .overlay(PieSliceShape(startAngle: start, endAngle: end).stroke(isHovered ? Color.white : Color.black.opacity(0.08), lineWidth: 1.2))
            VStack(spacing: 2) {
                Image(systemName: item.icon).font(.system(size: 15, weight: .semibold))
                Text(item.title).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
                if let est = item.estimatedSizeText {
                    Text(est).font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(isHovered ? .white.opacity(0.95) : .black.opacity(0.62))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(isHovered ? Color.black.opacity(0.22) : Color.black.opacity(0.06), in: Capsule())
                }
            }
            .foregroundColor(isHovered ? .white : .black.opacity(0.85))
            .position(x: wheelSize / 2.0 + CGFloat(cos(midAngle)) * labelRadius, y: wheelSize / 2.0 + CGFloat(sin(midAngle)) * labelRadius)
        }.frame(width: wheelSize, height: wheelSize)
    }
    var centerBadgeView: some View {
        VStack(spacing: 2) {
            Text(state.wheelMode.rawValue).font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundColor(.orange)
            Text(state.totalSizeText).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.primary)
            if let idx = state.hoveredIndex, idx < state.items.count, let est = state.items[idx].estimatedSizeText {
                Text("예상 \(est)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.orange)
            } else {
                Text("\(state.draggedFiles.count)개 파일").font(.system(size: 9.5, weight: .medium)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - 6. 도구 창 매니저 및 단축키 + 파일명 변환 양식 설정 창
class ToolWindowManager {
    static let shared = ToolWindowManager()
    var activeWindows: [NSWindow] = []
    var bannerWindow: NSPanel?
    
    func openWindow<V: View>(title: String, view: V, size: NSSize, minSize: NSSize = NSSize(width: 680, height: 500)) {
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = title; win.minSize = minSize; win.isReleasedWhenClosed = false
        win.center(); win.contentView = NSHostingView(rootView: view)
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        activeWindows.append(win)
    }
    
    func showBanner(message: String) {
        bannerWindow?.close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 52), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .statusBar
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 210, y: screen.frame.maxY - 90)) }
        panel.contentView = NSHostingView(rootView:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.orange).font(.title2)
                Text(message).font(.system(size: 13, weight: .semibold)).foregroundColor(.primary)
            }
            .padding(.horizontal, 18).padding(.vertical, 12).background(.regularMaterial, in: Capsule()).shadow(radius: 10)
        )
        panel.orderFrontRegardless(); bannerWindow = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { panel.close() }
    }
    
    func showHelpAndSettingsWindow() {
        openWindow(title: "🍊 MyTangerine — 설명 및 설정", view: HelpAndSettingsView(), size: NSSize(width: 820, height: 680), minSize: NSSize(width: 740, height: 580))
    }
    func showEditPhotoWindow(url: URL) {
        openWindow(title: "Pro Photo Editor — \(url.lastPathComponent)", view: EditPhotoView(fileURL: url), size: NSSize(width: 1120, height: 780), minSize: NSSize(width: 860, height: 600))
    }
    func showRedactCropWindow(url: URL, initialTab: Int) {
        openWindow(title: "Redact & Crop Studio — \(url.lastPathComponent)", view: RedactCropStudioView(fileURL: url, mode: initialTab), size: NSSize(width: 1100, height: 780), minSize: NSSize(width: 860, height: 600))
    }
    func showAddBGWindow(url: URL) {
        openWindow(title: "Add Background — \(url.lastPathComponent)", view: AddBGView(fileURL: url), size: NSSize(width: 840, height: 680))
    }
    func showCompressWindow(urls: [URL]) {
        openWindow(title: "Compress Files", view: CompressToolView(files: urls), size: NSSize(width: 480, height: 370), minSize: NSSize(width: 440, height: 340))
    }
    func showMetadataWindow(url: URL) {
        openWindow(title: "File Metadata", view: MetadataToolView(fileURL: url), size: NSSize(width: 560, height: 520))
    }
    func showMediaStudioWindow(url: URL, initialTab: String) {
        openWindow(title: "QuickTime & Multi-Channel Studio — \(url.lastPathComponent)", view: ProMediaStudioView(fileURL: url, initialMode: initialTab), size: NSSize(width: 1060, height: 800), minSize: NSSize(width: 900, height: 680))
    }
}

struct HelpAndSettingsView: View {
    @ObservedObject var settings = ShortcutSettings.shared
    @State private var selectedTab: Int = 0
    @State private var recordingTarget: String? = nil
    @State private var tempRecordedFlags: NSEvent.ModifierFlags = []
    @State private var localMonitor: Any? = nil
    
    let sampleDate: Date = {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 10; comp.day = 11
        comp.hour = 17; comp.minute = 5; comp.second = 35
        return Calendar.current.date(from: comp) ?? Date()
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 36)).foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MyTangerine 4.0 Pro").font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text("메타데이터 보존 변환 · 촬영일자 이름 일괄변환 · 전문가 미디어 스튜디오").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: $selectedTab) {
                    Text("⌨️ 단축키 설정").tag(0)
                    Text("🏷️ 이름 변환 양식").tag(1)
                    Text("📖 사용 설명서").tag(2)
                }.pickerStyle(.segmented).frame(width: 380)
            }
            .padding(18).background(.regularMaterial)
            Divider()
            
            if selectedTab == 0 {
                shortcutRecorderTab
            } else if selectedTab == 1 {
                renamePatternTab
            } else {
                usageGuideTab
            }
            
            Divider()
            HStack {
                Text("💡 모든 포맷 변환·압축·편집 시 원본 사진/영상의 촬영일자와 EXIF 메타데이터가 자동 보존됩니다.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("기본 설정 복원") {
                    stopRecording()
                    settings.resetToTangerineDefaults()
                    settings.renamePattern = ShortcutSettings.defaultRenamePattern
                    FileProcessor.showToast("단축키 및 파일명 양식이 기본값으로 복원되었습니다.")
                }
                Button("닫기") { stopRecording(); NSApp.keyWindow?.close() }
                    .buttonStyle(.borderedProminent).tint(.orange)
            }
            .padding(14).background(.regularMaterial)
        }.onDisappear { stopRecording() }
    }
    
    // MARK: 탭 2 — 촬영일자 기반 파일명 일괄변환 양식 설정 탭
    var renamePatternTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("촬영일자 기반 파일명 일괄 변환 (RENAME) 설정").font(.headline).foregroundColor(.orange)
                    Text("파일을 드래그하여 TOOLS(Option+Shift) 또는 ACTIONS(Control) 휠의 [RENAME]에 놓으면, 메타데이터(EXIF/생성일)의 촬영일시를 읽어 아래 입력한 양식대로 파일명을 즉시 변경합니다.")
                        .font(.caption).foregroundColor(.secondary)
                }
                
                // 양식 입력 텍스트박스 및 실시간 미리보기 카드
                VStack(alignment: .leading, spacing: 12) {
                    Text("파일명 변환 양식 입력").font(.subheadline.bold())
                    HStack(spacing: 10) {
                        TextField("예: {YYYYMMDD}_{hhmmss}_{Originalname}", text: $settings.renamePattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        
                        Button("기본 양식") {
                            settings.renamePattern = "{YYYYMMDD}_{hhmmss}_{Originalname}"
                        }
                        Button("연-월-일 양식") {
                            settings.renamePattern = "{YYYY}-{MM}-{DD}_{hh}{mm}{ss}_{filename}"
                        }
                    }
                    
                    // 실시간 변환 예시 미리보기
                    let previewResult = ShortcutSettings.formatFileName(
                        pattern: settings.renamePattern,
                        originalName: "_DSC3015",
                        captureDate: sampleDate,
                        cameraModel: "ILCE-7M4",
                        sequenceIndex: 1
                    )
                    HStack(spacing: 12) {
                        Text("실시간 미리보기:").font(.caption.bold()).foregroundColor(.secondary)
                        Text("_DSC3015.JPG").font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Image(systemName: "arrow.right.circle.fill").foregroundColor(.orange)
                        Text("\(previewResult).JPG")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                
                // 사용 가능한 코드(토큰) 안내 표
                VStack(alignment: .leading, spacing: 10) {
                    Text("📌 텍스트박스에 넣을 수 있는 치환 코드 안내 (클릭하면 양식 끝에 추가됩니다)")
                        .font(.subheadline.bold()).foregroundColor(.orange)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        tokenInfoRow(code: "{YYYYMMDD}", desc: "촬영 년월일 8자리 (예: 20261011)")
                        tokenInfoRow(code: "{hhmmss}", desc: "촬영 시분초 6자리 (예: 170535)")
                        tokenInfoRow(code: "{Originalname}", desc: "원래 파일 이름 (예: _DSC3015)")
                        tokenInfoRow(code: "{filename}", desc: "원래 파일 이름 ({Originalname}과 동일)")
                        tokenInfoRow(code: "{YYYY}", desc: "촬영 연도 4자리 (예: 2026)")
                        tokenInfoRow(code: "{YY}", desc: "촬영 연도 2자리 (예: 26)")
                        tokenInfoRow(code: "{MM}", desc: "촬영 월 2자리 (예: 10)")
                        tokenInfoRow(code: "{DD}", desc: "촬영 일 2자리 (예: 11)")
                        tokenInfoRow(code: "{hh}", desc: "촬영 시 24시간제 (예: 17)")
                        tokenInfoRow(code: "{mm}", desc: "촬영 분 2자리 (예: 05)")
                        tokenInfoRow(code: "{ss}", desc: "촬영 초 2자리 (예: 35)")
                        tokenInfoRow(code: "{Camera}", desc: "카메라 기종 모델명 (예: ILCE-7M4)")
                        tokenInfoRow(code: "{Seq}", desc: "다중 파일 일괄 변경 시 순번 (001, 002...)")
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(22)
        }
    }
    
    func tokenInfoRow(code: String, desc: String) -> some View {
        Button(action: {
            settings.renamePattern += code
        }) {
            HStack(spacing: 8) {
                Text(code)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(8)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    var shortcutRecorderTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("3가지 원형 휠 단축키 직접 입력 설정").font(.headline).foregroundColor(.orange)
                    Text("바꾸고 싶은 기능의 [단축키 입력하기] 버튼을 누른 뒤, 키보드에서 원하는 조합(예: Shift, Option+Shift, Control 등)을 누르고 마우스로 [완료] 버튼을 클릭하면 적용됩니다.")
                        .font(.caption).foregroundColor(.secondary)
                }
                VStack(spacing: 14) {
                    recorderCard(
                        targetID: "convert", title: "🔄 포맷 변환 휠 (CONVERT)",
                        subtitle: "파일을 드래그하면서 이 키를 누르면 메타데이터를 보존한 채 JPG, PNG, WEBP, HEIC, PDF, MP4, MOV, GIF, MP3, WAV 등으로 즉시 변환합니다.",
                        currentFlags: settings.convertFlags,
                        onSave: { newFlags in settings.convertFlagsRaw = newFlags.rawValue; FileProcessor.showToast("변환(CONVERT) 단축키가 저장되었습니다.") }
                    )
                    recorderCard(
                        targetID: "tools", title: "🛠️ 전용 편집 도구 휠 (TOOLS)",
                        subtitle: "파일을 드래그하면서 이 키를 누르면 사진 보정(Edit), 크롭(Crop), 모자이크(Redact), 촬영일자 이름변경(Rename), 영상/오디오 트림, 압축 도구가 열립니다.",
                        currentFlags: settings.toolsFlags,
                        onSave: { newFlags in settings.toolsFlagsRaw = newFlags.rawValue; FileProcessor.showToast("도구(TOOLS) 단축키가 저장되었습니다.") }
                    )
                    recorderCard(
                        targetID: "actions", title: "⚡ 빠른 액션 휠 (ACTIONS)",
                        subtitle: "파일을 드래그하면서 이 키를 누르면 촬영일자 이름변경, 경로 복사, 터미널 열기, AirDrop 전송, Finder 표시, 사본 만들기 휠이 열립니다.",
                        currentFlags: settings.actionsFlags,
                        onSave: { newFlags in settings.actionsFlagsRaw = newFlags.rawValue; FileProcessor.showToast("빠른 액션(ACTIONS) 단축키가 저장되었습니다.") }
                    )
                }
            }.padding(22)
        }
    }
    
    @ViewBuilder
    func recorderCard(targetID: String, title: String, subtitle: String, currentFlags: NSEvent.ModifierFlags, onSave: @escaping (NSEvent.ModifierFlags) -> Void) -> some View {
        let isRecordingThis = (recordingTarget == targetID)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold))
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: isRecordingThis ? "keyboard.badge.ellipsis" : "keyboard").foregroundColor(isRecordingThis ? .orange : .secondary)
                    if isRecordingThis {
                        Text(tempRecordedFlags.isEmpty ? "원하는 키 조합(Shift, Option, Control, Command)을 누르세요..." : ShortcutSettings.formatFlags(tempRecordedFlags))
                            .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(.orange)
                    } else {
                        Text("파일 드래그 + " + ShortcutSettings.formatFlags(currentFlags))
                            .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.black.opacity(isRecordingThis ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isRecordingThis ? Color.orange : Color.white.opacity(0.2), lineWidth: isRecordingThis ? 2 : 1))
                
                if isRecordingThis {
                    Button("완료") {
                        if !tempRecordedFlags.isEmpty { onSave(tempRecordedFlags) }
                        stopRecording()
                    }.buttonStyle(.borderedProminent).tint(.green).disabled(tempRecordedFlags.isEmpty)
                    Button("취소") { stopRecording() }
                } else {
                    Button("단축키 입력하기") { startRecording(for: targetID) }.buttonStyle(.borderedProminent).tint(.orange)
                }
            }
        }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    func startRecording(for targetID: String) {
        stopRecording(); recordingTarget = targetID; tempRecordedFlags = []
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if !flags.isEmpty { self.tempRecordedFlags = flags }
            return nil
        }
    }
    func stopRecording() {
        if let mon = localMonitor { NSEvent.removeMonitor(mon); localMonitor = nil }
        recordingTarget = nil; tempRecordedFlags = []
    }
    
    var usageGuideTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                guideCard(icon: "hand.draw.fill", title: "1. 3가지 원형 휠 작동법 & 메타데이터 완벽 보존", items: [
                    "🔄 Shift + 드래그 (CONVERT): 원본의 EXIF 촬영일자·카메라 정보·GPS 메타데이터를 삭제하지 않고 그대로 유지하며 포맷을 변환합니다.",
                    "🛠️ Option + Shift + 드래그 (TOOLS): 사진 보정(Edit), 크롭(Crop), 모자이크(Redact), 촬영일자 이름변경(Rename), 트림, 압축을 실행합니다.",
                    "⚡ Control + 드래그 (ACTIONS): 촬영일자 이름변경, 파일 경로 복사, 터미널 열기, AirDrop 공유, 사본 생성 등 빠른 액션이 실행됩니다."
                ])
                guideCard(icon: "character.cursor.ibeam", title: "2. 촬영일자 파일명 일괄 변환 (RENAME)", items: [
                    "여러 장의 사진(JPG, HEIC, RAW 등)이나 영상을 한꺼번에 잡고 TOOLS 또는 ACTIONS 휠의 [RENAME]에 놓으세요.",
                    "각 파일의 EXIF 촬영일시(DateTimeOriginal)를 읽어 '20261011_170535__DSC3015.JPG' 형태로 즉시 일괄 변경합니다.",
                    "[이름 변환 양식] 탭에서 {YYYYMMDD}_{hhmmss}_{Originalname} 또는 {YYYY}{MM}{DD}_{hh}{mm}{ss}_{filename} 등 원하는 규칙으로 자유롭게 꾸밀 수 있습니다."
                ])
                guideCard(icon: "film.stack", title: "3. 영상/오디오 정밀 트림 & 다중 채널 스튜디오", items: [
                    "타임라인 양끝의 노란색 트림 바(시작점 In ~ 종료점 Out) 안쪽 구간만 정확하게 보고 들을 수 있도록 재생 범위가 고정됩니다.",
                    "다중 채널 오디오 믹서: 2채널부터 4채널, 8채널 이상의 오디오 트랙을 자동 감지하여 원하는 채널만 켜고 끄거나(ON/MUTE) 단독 청취(SOLO)할 수 있습니다."
                ])
            }.padding(22)
        }
    }
    func guideCard(icon: String, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { Image(systemName: icon).foregroundColor(.orange).font(.title3); Text(title).font(.headline) }
            ForEach(items, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) { Text("•").foregroundColor(.orange).bold(); Text(line).font(.system(size: 13)) }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
