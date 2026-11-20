import Cocoa
import Carbon
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
import IOKit.pwr_mgt
import IOKit.ps

// MARK: - 0. 단축키, 홀드/토글 방식, 퀄리티 옵션 키 및 파일명 패턴 설정 매니저
class ShortcutSettings: ObservableObject {
    static let shared = ShortcutSettings()
    
    @Published var convertFlagsRaw: UInt {
        didSet { UserDefaults.standard.set(Int(convertFlagsRaw), forKey: "tangerine_sc_convert_v44") }
    }
    @Published var toolsFlagsRaw: UInt {
        didSet { UserDefaults.standard.set(Int(toolsFlagsRaw), forKey: "tangerine_sc_tools_v44") }
    }
    @Published var actionsFlagsRaw: UInt {
        didSet { UserDefaults.standard.set(Int(actionsFlagsRaw), forKey: "tangerine_sc_actions_v44") }
    }
    @Published var qualityModifierRaw: UInt {
        didSet { UserDefaults.standard.set(Int(qualityModifierRaw), forKey: "tangerine_sc_quality_v44") }
    }
    @Published var isToggleMode: Bool {
        didSet { UserDefaults.standard.set(isToggleMode, forKey: "tangerine_sc_toggle_mode_v44") }
    }
    // 4.8 안전 모드: 입력은 항상 수동 감시하고, macOS 원본 드래그는 건드리지 않습니다.
    @Published var wheelDetectionEnabled: Bool {
        didSet { UserDefaults.standard.set(wheelDetectionEnabled, forKey: "tangerine_safe_enabled_v48") }
    }
    @Published var finderOnlyDetection: Bool {
        didSet { UserDefaults.standard.set(finderOnlyDetection, forKey: "tangerine_safe_finder_only_v48") }
    }
    @Published var renamePattern: String {
        didSet { UserDefaults.standard.set(renamePattern, forKey: "tangerine_rename_pattern_v40") }
    }
    
    static let defaultConvertRaw: UInt = NSEvent.ModifierFlags.shift.rawValue
    static let defaultToolsRaw: UInt = NSEvent.ModifierFlags([.option, .shift]).rawValue
    static let defaultActionsRaw: UInt = NSEvent.ModifierFlags.control.rawValue
    static let defaultQualityRaw: UInt = NSEvent.ModifierFlags.command.rawValue
    static let defaultRenamePattern: String = "{YYYYMMDD}_{hhmmss}_{Originalname}"
    
    init() {
        let savedConv = UserDefaults.standard.integer(forKey: "tangerine_sc_convert_v44")
        let savedTools = UserDefaults.standard.integer(forKey: "tangerine_sc_tools_v44")
        let savedActions = UserDefaults.standard.integer(forKey: "tangerine_sc_actions_v44")
        let savedQual = UserDefaults.standard.integer(forKey: "tangerine_sc_quality_v44")
        let savedToggle = UserDefaults.standard.bool(forKey: "tangerine_sc_toggle_mode_v44")
        let defaults = UserDefaults.standard
        // HK7: 구버전에서 진단 목적으로 꺼둔 값은 새 실행에 승계하지 않습니다.
        // 일반 Finder 안전 모드는 항상 적용하고, 휠 입력 감지는 자동 활성화합니다.
        let savedFinderOnly = defaults.object(forKey: "tangerine_safe_finder_only_v48") as? Bool
        let savedPattern = UserDefaults.standard.string(forKey: "tangerine_rename_pattern_v40")
        
        self.convertFlagsRaw = (savedConv != 0) ? UInt(savedConv) : Self.defaultConvertRaw
        self.toolsFlagsRaw = (savedTools != 0) ? UInt(savedTools) : Self.defaultToolsRaw
        self.actionsFlagsRaw = (savedActions != 0) ? UInt(savedActions) : Self.defaultActionsRaw
        self.qualityModifierRaw = (savedQual != 0) ? UInt(savedQual) : Self.defaultQualityRaw
        self.isToggleMode = savedToggle
        self.wheelDetectionEnabled = true
        defaults.set(true, forKey: "tangerine_safe_enabled_v48")
        self.finderOnlyDetection = savedFinderOnly ?? true
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
    var qualityFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: qualityModifierRaw).intersection([.shift, .option, .control, .command])
    }
    
    func resetToFavoriteDefaults() {
        convertFlagsRaw = Self.defaultConvertRaw
        toolsFlagsRaw = Self.defaultToolsRaw
        actionsFlagsRaw = Self.defaultActionsRaw
        qualityModifierRaw = Self.defaultQualityRaw
        isToggleMode = false
        wheelDetectionEnabled = true
        finderOnlyDetection = true
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
    
    // 불필요한 상위 조합 인식 금지: ⌃/⌥/⇧/⌘가 함께 눌려도 정확히 설정된 조합만 동작합니다.
    func matchWheelMode(for flags: NSEvent.ModifierFlags) -> WheelMode? {
        let clean = flags.intersection([.shift, .option, .control, .command])
        guard !clean.isEmpty else { return nil }
        let choices: [(WheelMode, NSEvent.ModifierFlags)] = [
            (.tools, toolsFlags), (.actions, actionsFlags), (.convert, convertFlags)
        ]
        for (mode, req) in choices where !req.isEmpty && clean == req { return mode }
        let quality = qualityFlags
        if !quality.isEmpty && clean.isSuperset(of: quality) {
            let withoutQuality = clean.subtracting(quality)
            for (mode, req) in choices where !req.isEmpty && withoutQuality == req { return mode }
        }
        return nil
    }

    // 같은 조합이 여러 휠에 지정되거나 퀄리티 키가 휠 단축키에 포함되는 실수를 차단합니다.
    func validationMessage(for flags: NSEvent.ModifierFlags, target: String) -> String? {
        let clean = flags.intersection([.shift, .option, .control, .command])
        if clean.isEmpty { return "수정키를 하나 이상 선택해 주세요." }
        let otherWheels: [(String, NSEvent.ModifierFlags)] = [
            ("convert", convertFlags), ("tools", toolsFlags), ("actions", actionsFlags)
        ]
        if target == "quality" {
            for (_, wheelKeys) in otherWheels where wheelKeys.isSuperset(of: clean) {
                return "퀄리티 키는 휠 단축키 안에 포함될 수 없습니다. 다른 조합을 선택하세요."
            }
        } else {
            for (name, wheelKeys) in otherWheels where name != target && clean == wheelKeys {
                return "다른 휠이 이미 사용하는 단축키입니다."
            }
            if clean.isSuperset(of: qualityFlags) && !qualityFlags.isEmpty {
                return "퀄리티 옵션 키를 이미 포함하고 있습니다. 다른 단축키를 선택하세요."
            }
        }
        return nil
    }

    static func formatFileName(pattern: String, originalName: String, captureDate: Date, cameraModel: String, sequenceIndex: Int) -> String {
        // 촬영기기의 시계값을 GMT 기준 Date에 보관한 뒤 같은 GMT에서 추출합니다.
        // 컴퓨터의 현재 시간대로 재변환하여 촬영 시간에 9시간이 더해지지 않게 합니다.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: captureDate)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let hh = comps.hour ?? 0
        let mm = comps.minute ?? 0
        let ss = comps.second ?? 0
        
        let yyyyStr = String(format: "%04d", y)
        let yyStr = String(format: "%02d", y % 100)
        let mmMonthStr = String(format: "%02d", m)
        let ddStr = String(format: "%02d", d)
        let hhStr = String(format: "%02d", hh)
        let mmMinStr = String(format: "%02d", mm)
        let ssStr = String(format: "%02d", ss)
        let seqStr = String(format: "%04d", sequenceIndex)
        let cleanCam = cameraModel.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        
        var res = pattern
        let replacements: [(String, String)] = [
            ("{YYYYMMDD}", "\(yyyyStr)\(mmMonthStr)\(ddStr)"),
            ("{yyyyMMdd}", "\(yyyyStr)\(mmMonthStr)\(ddStr)"),
            ("{YYMMDD}", "\(yyStr)\(mmMonthStr)\(ddStr)"),
            ("{hhmmss}", "\(hhStr)\(mmMinStr)\(ssStr)"),
            ("{HHmmss}", "\(hhStr)\(mmMinStr)\(ssStr)"),
            ("{YYYY}", yyyyStr), ("{yyyy}", yyyyStr), ("{YY}", yyStr),
            ("{MM}", mmMonthStr), ("{DD}", ddStr), ("{dd}", ddStr),
            ("{hh}", hhStr), ("{HH}", hhStr), ("{mm}", mmMinStr), ("{ss}", ssStr),
            ("{filename}", originalName), ("{Filename}", originalName),
            ("{Originalname}", originalName), ("{originalname}", originalName), ("{OriginalName}", originalName),
            ("{Camera}", cleanCam.isEmpty ? "Camera" : cleanCam), ("{camera}", cleanCam.isEmpty ? "Camera" : cleanCam),
            ("{Seq}", seqStr), ("{seq}", seqStr)
        ]
        for (token, val) in replacements { res = res.replacingOccurrences(of: token, with: val) }
        res = res.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        return res.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


// MARK: - 촬영일시 근거 점검 (Camera DateShift의 판별 원칙 이식)
// 파일 생성·수정일이나 현재 시각을 촬영 시각으로 대신 사용하지 않습니다.
struct CaptureDateEvidence {
    let date: Date?
    let camera: String
    let state: String            // ready / review / missing / error
    let source: String
    let confidence: String
    let raw: String
    let note: String
}

struct RenameCandidate: Identifiable {
    let url: URL
    var date: Date?
    let camera: String
    let state: String
    var source: String
    let confidence: String
    let note: String
    let raw: String
    let fileSize: Int64
    let modificationTime: Date?
    var quickTimeMode: String = "utc"
    var id: String { url.path }
}

enum CaptureDateInspector {
    private static let photos: Set<String> = ["jpg","jpeg","heic","heif","png","tif","tiff","webp","bmp","gif","avif","dng","arw","cr2","cr3","nef","raf","orf","rw2"]
    private static let videos: Set<String> = ["mp4","mov","m4v","mkv","avi","mts","m2ts","3gp","webm","wmv"]
    private static let dateRegex = try! NSRegularExpression(pattern: #"^\s*(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:\s*(Z|[+\-]\d{2}:?\d{2}))?\s*$"#)

    private static func parsed(_ text: String) -> (wall: Date, offset: Int?)? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = dateRegex.firstMatch(in: input, range: range) else { return nil }
        func part(_ n: Int) -> String? {
            let ns = match.range(at: n)
            guard ns.location != NSNotFound, let r = Range(ns, in: input) else { return nil }
            return String(input[r])
        }
        guard let yy = part(1).flatMap(Int.init), let mo = part(2).flatMap(Int.init),
              let dd = part(3).flatMap(Int.init), let h = part(4).flatMap(Int.init),
              let m = part(5).flatMap(Int.init), let s = part(6).flatMap(Int.init),
              (1900...2100).contains(yy), (1...12).contains(mo), (0...23).contains(h),
              (0...59).contains(m), (0...59).contains(s) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let dc = DateComponents(timeZone: cal.timeZone, year: yy, month: mo, day: dd, hour: h, minute: m, second: s)
        guard let wall = cal.date(from: dc),
              cal.dateComponents([.year,.month,.day], from: wall).year == yy,
              cal.dateComponents([.year,.month,.day], from: wall).month == mo,
              cal.dateComponents([.year,.month,.day], from: wall).day == dd else { return nil }
        var offset: Int? = nil
        if let zone = part(7) {
            if zone.uppercased() == "Z" { offset = 0 }
            else {
                let digits = String(zone.dropFirst()).replacingOccurrences(of: ":", with: "")
                guard digits.count == 4, let hh = Int(digits.prefix(2)), let mm = Int(digits.suffix(2)),
                      hh <= 14, mm < 60, !(hh == 14 && mm != 0) else { return nil }
                offset = (zone.hasPrefix("-") ? -1 : 1) * (hh * 60 + mm)
            }
        }
        return (wall, offset)
    }

    private static func dateText(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.string(from: date)
    }
    static func displayDate(_ date: Date?) -> String { date.map(dateText) ?? "촬영일 미확인" }

    private static func imageTags(_ url: URL) -> [String: String] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            for (key, val) in exif { result["ExifIFD:" + key] = "\(val)" }
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            for (key, val) in tiff { result["IFD0:" + key] = "\(val)" }
        }
        return result
    }

    // Camera DateShift와 마찬가지로 원본 카메라 태그를 읽습니다.
    // macOS 기본 API만으로 읽히지 않는 카메라 RAW/QuickTime 계열을 위해 ExifTool을 앱에 동봉합니다.
    private static func exifTags(_ url: URL) -> [String: String]? {
        guard let script = Bundle.main.path(forResource: "exiftool", ofType: "pl"),
              let resources = Bundle.main.resourceURL else { return nil }
        let lib = resources.appendingPathComponent("exiftool-lib", isDirectory:true).path
        guard FileManager.default.fileExists(atPath:lib) else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [script, "-j", "-G1", "-a", "-s", "-api", "QuickTimeUTC=0", "-api", "LargeFileSupport=1", url.path]
        var env = ProcessInfo.processInfo.environment
        env["PERL5LIB"] = lib
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0,
                  let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let obj = arr.first else { return nil }
            var tags: [String: String] = [:]
            for (key, value) in obj {
                if let s = value as? String { tags[key] = s }
                else if let n = value as? NSNumber { tags[key] = n.stringValue }
            }
            return tags
        } catch { return nil }
    }

    private static func candidate(_ tags: [String: String], _ names: [String]) -> (tag: String, raw: String, wall: Date, offset: Int?)? {
        for name in names {
            // 완전 일치 우선, 그다음 ExifTool의 그룹이 붙은 동명이인 태그 탐색.
            let keys = tags.keys.filter { $0 == name || $0.hasSuffix(":" + name) }
                .filter { !$0.hasPrefix("File:") && !$0.hasPrefix("System:") && !$0.hasPrefix("Composite:") }
                .sorted { ($0 == name ? 0 : 1, $0) < ($1 == name ? 0 : 1, $1) }
            for key in keys {
                guard let raw = tags[key], let dt = parsed(raw) else { continue }
                return (key, raw, dt.wall, dt.offset)
            }
        }
        return nil
    }
    private static func named(_ tags: [String: String], _ names: [String]) -> (tag: String, raw: String, wall: Date, offset: Int?)? {
        for name in names { if let raw = tags[name], let dt = parsed(raw) { return (name,raw,dt.wall,dt.offset) } }
        return nil
    }
    private static func sonyXML(_ url: URL) -> (raw: String, wall: Date, offset: Int?)? {
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              let filename = names.first(where: { $0.caseInsensitiveCompare(stem + "M01.XML") == .orderedSame }) else { return nil }
        let file = folder.appendingPathComponent(filename)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber, size.int64Value < 1_048_576,
              let xml = try? String(contentsOf: file, encoding: .utf8),
              xml.contains("NonRealTimeMeta"), xml.contains("schemas-professionalDisc:nonRealTimeMeta") else { return nil }
        let regex = try! NSRegularExpression(pattern: #"<CreationDate\s+value=\"([^\"]+)\""#)
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, range: range),
              let r = Range(match.range(at: 1), in: xml) else { return nil }
        let raw = String(xml[r])
        guard let dt = parsed(raw), dt.offset != nil else { return nil }
        return (raw,dt.wall,dt.offset)
    }

    static func inspect(_ url: URL, quickTimeMode: String = "utc") -> CaptureDateEvidence {
        let ext = url.pathExtension.lowercased()
        guard photos.contains(ext) || videos.contains(ext) else {
            return CaptureDateEvidence(date:nil,camera:"",state:"missing",source:"지원 대상 아님",confidence:"없음",raw:"",note:"카메라 사진·영상이 아닙니다. 파일 생성일을 촬영일로 대체하지 않습니다.")
        }
        let externalTags = exifTags(url)
        if videos.contains(ext) && externalTags == nil {
            return CaptureDateEvidence(date:nil,camera:"",state:"error",source:"ExifTool 촬영일시 판독 실패",confidence:"확인 불가",raw:"",note:"영상 메타데이터를 읽지 못했습니다. 앱에 동봉한 ExifTool 설치·실행 상태 또는 파일 손상을 확인하세요.")
        }
        let tags = externalTags ?? (photos.contains(ext) ? imageTags(url) : [:])
        let camera = tags["IFD0:Model"] ?? tags["ExifIFD:Model"] ?? tags["QuickTime:Model"] ?? ""
        func result(_ dt: (tag: String, raw: String, wall: Date, offset: Int?), state: String, source: String, confidence: String, note: String = "") -> CaptureDateEvidence {
            CaptureDateEvidence(date:dt.wall,camera:camera,state:state,source:source,confidence:confidence,raw:dt.raw,note:note)
        }
        if photos.contains(ext) {
            if let main = named(tags,["ExifIFD:SubSecDateTimeOriginal","ExifIFD:DateTimeOriginal","EXIF:DateTimeOriginal"]) {
                return result(main,state:"ready",source:main.tag,confidence:"높음",note:"카메라 EXIF 촬영 시계값입니다. 시간대가 없으면 현지 시계값 그대로 이름에 사용합니다.")
            }
            if let weakOriginal = candidate(tags,["SubSecDateTimeOriginal","DateTimeOriginal"]) {
                return result(weakOriginal,state:"review",source:weakOriginal.tag,confidence:"확인 필요",note:"ExifIFD 원본 필드가 아닌 위치의 촬영일시입니다. 편집된 XMP일 가능성을 확인해 주세요.")
            }
            if let alt = named(tags,["ExifIFD:CreateDate","ExifIFD:DateTimeDigitized","EXIF:CreateDate"]) {
                return result(alt,state:"ready",source:alt.tag,confidence:"조건부",note:"원본 촬영 태그가 없어 카메라 EXIF 디지털 생성일을 사용합니다.")
            }
            if let weak = candidate(tags,["DateTimeDigitized","CreateDate","CreationDate","DateTime"]) {
                return result(weak,state:"review",source:weak.tag,confidence:"확인 필요",note:"촬영 시작일 대신 이미지 생성·가공일일 수 있습니다. 확인 후 승인해 주세요.")
            }
            return CaptureDateEvidence(date:nil,camera:camera,state:"missing",source:"촬영일 필드 없음",confidence:"없음",raw:"",note:"파일 생성일·수정일·현재 시간은 촬영일로 사용하지 않습니다.")
        }
        if let xml = sonyXML(url) {
            let movie = named(tags,["QuickTime:CreateDate","MovieHeader:CreateDate"]) ?? candidate(tags,["CreateDate"])
            var conflict = false
            if let m = movie, m.offset == nil, let xmlOffset = xml.offset {
                // UTC 숫자와 XML의 +09:00 카메라 시각은 동일한 순간일 수 있습니다.
                let xmlUTC = xml.wall.addingTimeInterval(TimeInterval(-xmlOffset * 60))
                conflict = abs(xmlUTC.timeIntervalSince(m.wall)) > 120
            }
            let dt = (tag:"Sony XML:CreationDate",raw:xml.raw,wall:xml.wall,offset:xml.offset)
            return result(dt,state: conflict ? "review" : "ready",source:dt.tag,confidence:conflict ? "확인 필요" : "높음",note:conflict ? "Sony XML과 QuickTime UTC 숫자가 일치하지 않습니다. 촬영 시간 확인 후 승인하세요." : "Sony XML의 명시적 시간대 기준. QuickTime UTC 오프셋을 추가하지 않습니다.")
        }
        let explicit = named(tags,["Keys:CreationDate","UserData:DateTimeOriginal","UserData:CreationDate","QuickTime:CreationDate","XMP-exif:DateTimeOriginal","XMP-xmp:CreateDate"]) ?? candidate(tags,["CreationDate","DateTimeOriginal"])
        if let e = explicit {
            if e.offset != nil { return result(e,state:"ready",source:e.tag,confidence:"높음",note:"영상 내부에 시간대가 명시된 원본 촬영 기록입니다.") }
            if e.tag.hasSuffix(":DateTimeOriginal") || e.tag.hasSuffix(":CreationDate") {
                return result(e,state:"ready",source:e.tag,confidence:"시계값",note:"녹화 시계값은 있으나 오프셋이 없습니다. 컴퓨터 시간대로 강제 보정하지 않았습니다.")
            }
            return result(e,state:"review",source:e.tag,confidence:"확인 필요",note:"영상 생성 메타데이터의 촬영일 여부를 확인해야 합니다.")
        }
        if let movie = named(tags,["QuickTime:CreateDate","MovieHeader:CreateDate"]) ?? candidate(tags,["TrackCreateDate","MediaCreateDate","CreateDate"]) {
            // QuickTime 헤더의 숫자는 UTC 또는 현지 시각일 수 있어 자동 실행하지 않습니다.
            let systemOffset = TimeZone.current.secondsFromGMT(for: movie.wall)
            let localDisplay = movie.wall.addingTimeInterval(TimeInterval(systemOffset))
            let useLocal = quickTimeMode == "local"
            let chosen = useLocal ? movie.wall : localDisplay
            let note = "원시값 \(dateText(movie.wall)) / UTC 가정 후 이 Mac 시간대 \(dateText(localDisplay)). 두 해석 중 실제 촬영 시각을 선택하세요."
            return CaptureDateEvidence(date:chosen,camera:camera,state:"review",source:movie.tag + (useLocal ? " (현지 숫자 가정)" : " (UTC 가정)"),confidence:"시간대 미확정",raw:movie.raw,note:note)
        }
        return CaptureDateEvidence(date:nil,camera:camera,state:"missing",source:"촬영일 필드 없음",confidence:"없음",raw:"",note:"동반 XML이 없어도 내부 원본 촬영일이 있으면 사용합니다. 지금 파일에는 근거를 찾지 못했습니다.")
    }
    static func adjustQuickTime(_ candidate: RenameCandidate, mode: String) -> RenameCandidate {
        guard candidate.state == "review", candidate.source.contains("(UTC 가정)") || candidate.source.contains("(현지 숫자 가정)"),
              let rawDate = parsed(candidate.raw)?.wall else { return candidate }
        var adjusted = candidate
        adjusted.quickTimeMode = mode
        let isLocal = mode == "local"
        adjusted.date = isLocal ? rawDate : rawDate.addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT(for: rawDate)))
        let prefix = candidate.source.replacingOccurrences(of:" (UTC 가정)",with:"").replacingOccurrences(of:" (현지 숫자 가정)",with:"")
        adjusted.source = prefix + (isLocal ? " (현지 숫자 가정)" : " (UTC 가정)")
        return adjusted
    }
    static func scan(_ url: URL) -> RenameCandidate {
        let e = inspect(url)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
        return RenameCandidate(url:url,date:e.date,camera:e.camera,state:e.state,source:e.source,confidence:e.confidence,note:e.note,raw:e.raw,fileSize:bytes,modificationTime:attrs?[.modificationDate] as? Date)
    }
}

// MARK: - 1. 작업 진행률 매니저 (UI 스로틀링으로 수천 개 파일 처리 시 렉 방지)
struct ActiveJob: Identifiable {
    let id: UUID
    let title: String
    var progress: Double
}

class JobProgressManager: ObservableObject {
    static let shared = JobProgressManager()
    @Published var jobs: [ActiveJob] = []
    var onUpdate: (() -> Void)?
    private var lastUIUpdateTime: TimeInterval = 0
    
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
        // 같은 메인 큐에서 시간제한과 Published 상태를 함께 갱신하여 경쟁 상태를 피합니다.
        DispatchQueue.main.async {
            let now = CACurrentMediaTime()
            guard now - self.lastUIUpdateTime >= 0.06 || progress >= 0.99 else { return }
            self.lastUIUpdateTime = now
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
    @Published var isQualityOptionActive: Bool = false
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
            // 파일이 50개 이하일 때만 백그라운드 실제 이미지 인코딩 샘플링 수행 (수천 개 파일 드래그 시 즉시 반응 보장)
            if imageExts.contains(ext) && files.count <= 50 {
                DispatchQueue.global(qos: .utility).async {
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
            if draggedFiles.filter({ ImageJoinProcessor.isSupportedImage($0) }).count >= 2 {
                items.append(WheelItem(title: "이미지 합치기", icon: "square.stack", actionKey: "act_join_images"))
            }
        }
    }
}

// MARK: - 3. 변환 및 압축 파일 예상 크기 초고속 계산 엔진 (대량 파일 샘플링 최적화)
class FileSizeEstimator {
    static func estimateConversionBytes(files: [URL], originalTotalBytes: Int64, targetExt: String, qualityPercent: Double = 90.0) -> Int64 {
        guard let first = files.first, originalTotalBytes > 0 else { return 0 }
        let srcExt = first.pathExtension.lowercased()
        let tgt = targetExt.lowercased()
        if qualityPercent >= 99.5 && srcExt == tgt { return originalTotalBytes }
        
        let qFactor = max(0.05, qualityPercent / 100.0)
        let videoExts = ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
        let audioExts = ["mp3", "m4a", "wav", "flac", "ogg", "aac", "aiff", "caf"]
        
        if videoExts.contains(srcExt) || audioExts.contains(srcExt) {
            // 수천 개 파일 드래그 시 멈춤 방지를 위해 최대 앞쪽 5개 파일만 샘플링하여 전체 재생시간 비례 추정
            let sampleFiles = Array(files.prefix(5))
            let sampleDur = sampleFiles.reduce(0.0) { $0 + FileProcessor.mediaDurationSeconds(for: $1) }
            let totalDuration = sampleFiles.isEmpty ? 0 : (sampleDur * Double(files.count) / Double(sampleFiles.count))
            if totalDuration > 0 {
                switch tgt {
                case "mp3", "m4a", "aac", "caf", "ogg":
                    let kbps = 64.0 + 256.0 * qFactor
                    return max(4096, Int64(totalDuration * (kbps * 1000.0 / 8.0)))
                case "wav", "aiff": return max(8192, Int64(totalDuration * 176_400))
                case "flac": return max(8192, Int64(totalDuration * 96_000))
                case "gif": return max(10_240, Int64(totalDuration * 260_000 * qFactor))
                case "mp4", "mov", "mkv":
                    if qualityPercent >= 99.5 { return originalTotalBytes }
                    let baseRatio: Double = (srcExt == "mov") ? 0.68 : 0.88
                    return max(16_384, Int64(Double(originalTotalBytes) * baseRatio * pow(qFactor, 1.4)))
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
        let lossyTargets = ["jpg", "jpeg", "heic", "webp", "pdf"]
        let qWeight = lossyTargets.contains(tgt) ? pow(qFactor, 1.35) : 1.0
        return max(1024, Int64(Double(originalTotalBytes) * (tgtW / srcW) * qWeight))
    }
    
    static func exactImageConversionBytes(files: [URL], originalTotalBytes: Int64, targetExt: String, qualityPercent: Double = 88.0) -> Int64 {
        guard let first = files.first,
              let attrs = try? FileManager.default.attributesOfItem(atPath: first.path),
              let firstOrigSize = attrs[.size] as? Int64, firstOrigSize > 0,
              let cg = FileProcessor.loadRawCGImage(from: first) else {
            return estimateConversionBytes(files: files, originalTotalBytes: originalTotalBytes, targetExt: targetExt, qualityPercent: qualityPercent)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        let tgt = targetExt.lowercased()
        let q = max(0.01, min(1.0, qualityPercent / 100.0))
        var sampleDataSize: Int64? = nil
        
        switch tgt {
        case "jpg", "jpeg":
            sampleDataSize = Int64(rep.representation(using: .jpeg, properties: [.compressionFactor: q])?.count ?? 0)
        case "png":
            sampleDataSize = Int64(rep.representation(using: .png, properties: [:])?.count ?? 0)
        case "tiff":
            sampleDataSize = Int64(rep.representation(using: .tiff, properties: [:])?.count ?? 0)
        case "bmp":
            sampleDataSize = Int64(rep.representation(using: .bmp, properties: [:])?.count ?? 0)
        case "heic", "webp":
            if let jpgCount = rep.representation(using: .jpeg, properties: [.compressionFactor: q])?.count {
                sampleDataSize = Int64(Double(jpgCount) * 0.62)
            }
        case "pdf":
            if let jpgCount = rep.representation(using: .jpeg, properties: [.compressionFactor: q])?.count {
                sampleDataSize = Int64(jpgCount + 4096)
            }
        default: break
        }
        if let sSize = sampleDataSize, sSize > 0 {
            return max(1024, Int64(Double(originalTotalBytes) * (Double(sSize) / Double(firstOrigSize))))
        }
        return estimateConversionBytes(files: files, originalTotalBytes: originalTotalBytes, targetExt: targetExt, qualityPercent: qualityPercent)
    }
    
    static func estimateCompressedBytes(files: [URL], quality: Double) -> (original: Int64, estimated: Int64) {
        var origTotal: Int64 = 0; var estTotal: Int64 = 0
        let sampleLimit = 200
        for (index, f) in files.prefix(sampleLimit).enumerated() {
            let fSize = (try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64) ?? 0
            origTotal += fSize
            if quality >= 99.5 { estTotal += fSize; continue }
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
                let crf = 40.0 - (quality / 100.0) * 22.0
                let ratio = min(0.98, max(0.08, pow(2.0, (23.0 - crf) / 6.0) * 0.78))
                estTotal += max(4096, Int64(Double(fSize) * ratio))
            }
        }
        if files.count > sampleLimit && sampleLimit > 0 {
            let multiplier = Double(files.count) / Double(sampleLimit)
            origTotal = Int64(Double(origTotal) * multiplier)
            estTotal = Int64(Double(estTotal) * multiplier)
        }
        return (origTotal, estTotal)
    }
}

// MARK: - 4. 초고속 파일 처리, 대용량(2,000개+) 일괄 이름변경 및 메타데이터 보존 엔진
class FileProcessor {
    private static var cachedAppIcon: NSImage? = nil
    private static var didLoadAppIcon: Bool = false
    
    // DateFormatter를 매번 생성하지 않고 상수로 캐싱하여 2,000개 파일 처리 시 속도 30배 향상!
    private static let exifDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return df
    }()
    
    static func customAppIconImage() -> NSImage? {
        if didLoadAppIcon { return cachedAppIcon }
        didLoadAppIcon = true
        if let path = Bundle.main.path(forResource: "icon", ofType: "png"), let img = NSImage(contentsOfFile: path) {
            cachedAppIcon = img; return img
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"), let img = NSImage(contentsOfFile: path) {
            cachedAppIcon = img; return img
        }
        return nil
    }
    
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
    
    static func preserveFileDates(from src: URL, to dst: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: src.path) else { return }
        var newAttrs: [FileAttributeKey: Any] = [:]
        if let cDate = attrs[.creationDate] { newAttrs[.creationDate] = cDate }
        if let mDate = attrs[.modificationDate] { newAttrs[.modificationDate] = mDate }
        if !newAttrs.isEmpty { try? FileManager.default.setAttributes(newAttrs, ofItemAtPath: dst.path) }
    }
    
    static func extractCaptureDateAndCamera(for url: URL) -> CaptureDateEvidence {
        CaptureDateInspector.inspect(url)
    }

    // 직접 이름 변경을 수행하기 전에 출처·확인 여부·새 파일명을 검토합니다.
    static func batchRenameFilesWithCaptureDate(files: [URL]) {
        guard !files.isEmpty else { return }
        DispatchQueue.main.async {
            ToolWindowManager.shared.showRenameReviewWindow(urls: files)
        }
    }

    static func executeVerifiedRename(_ decisions: [RenameCandidate], approved: Set<String>) {
        let selected = decisions.filter { approved.contains($0.url.path) && $0.date != nil }
        guard !selected.isEmpty else { return }
        let pattern = ShortcutSettings.shared.renamePattern
        let jobID = JobProgressManager.shared.startJob(title: "촬영일자 확인 후 이름 변경 (\(selected.count)개)")
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var renamed = 0
            var skipped = 0
            var failed = 0
            var errors: [String] = []
            for (idx, entry) in selected.enumerated() {
                autoreleasepool {
                    do {
                        let attrs = try fm.attributesOfItem(atPath: entry.url.path)
                        let nowSize = (attrs[.size] as? NSNumber)?.int64Value ?? -1
                        let nowMod = attrs[.modificationDate] as? Date
                        guard nowSize == entry.fileSize, nowMod == entry.modificationTime else {
                            throw NSError(domain:"Rename",code:1,userInfo:[NSLocalizedDescriptionKey:"불러온 뒤 원본 파일이 변경됨"])
                        }
                        // Camera DateShift와 동일한 원칙: 실행 직전에 메타데이터를 다시 읽습니다.
                        let fresh = CaptureDateInspector.inspect(entry.url,quickTimeMode:entry.quickTimeMode)
                        guard let date = fresh.date, entry.date == date,
                              fresh.source == entry.source, fresh.state == entry.state else {
                            throw NSError(domain:"Rename",code:2,userInfo:[NSLocalizedDescriptionKey:"촬영일시 근거가 달라짐. 다시 확인 필요"])
                        }
                        let folder = entry.url.deletingLastPathComponent()
                        let ext = entry.url.pathExtension
                        let oldName = entry.url.deletingPathExtension().lastPathComponent
                        let newBase = ShortcutSettings.formatFileName(pattern:pattern,originalName:oldName,captureDate:date,cameraModel:fresh.camera,sequenceIndex:idx + 1)
                        var cameraCalendar = Calendar(identifier:.gregorian)
                        cameraCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
                        let dc = cameraCalendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from:date)
                        let prefix = String(format:"%04d%02d%02d_%02d%02d%02d_",dc.year ?? 0,dc.month ?? 0,dc.day ?? 0,dc.hour ?? 0,dc.minute ?? 0,dc.second ?? 0)
                        guard !newBase.isEmpty, !newBase.contains("\\"), !newBase.contains("\u{0000}"),
                              newBase.utf8.count <= 220 else { throw NSError(domain:"Rename",code:3,userInfo:[NSLocalizedDescriptionKey:"새 파일명이 비었거나 너무 깁니다."]) }
                        if newBase == oldName || (pattern == ShortcutSettings.defaultRenamePattern && oldName.hasPrefix(prefix)) {
                            skipped += 1
                            return
                        }
                        // Sony XML 및 XMP는 영상/사진의 이름과 연결되어 있으므로 함께 옮깁니다.
                        let contents = try fm.contentsOfDirectory(atPath: folder.path)
                        let companions = contents.filter {
                            $0.caseInsensitiveCompare(oldName + ".xmp") == .orderedSame ||
                            $0.caseInsensitiveCompare(oldName + "M01.XML") == .orderedSame
                        }
                        var destination: URL?
                        var pairs: [(URL, URL)] = []
                        for suffix in 0..<10000 {
                            let base = suffix == 0 ? newBase : newBase + "_\(suffix)"
                            let fileDest = folder.appendingPathComponent(ext.isEmpty ? base : base + "." + ext)
                            if fm.fileExists(atPath:fileDest.path) { continue }
                            let companionPairs = companions.map { name -> (URL,URL) in
                                let isXML = name.lowercased().hasSuffix("m01.xml")
                                let companionExt = name.hasSuffix(".XMP") ? ".XMP" : ".xmp"
                                let targetName = isXML ? base + "M01.XML" : base + companionExt
                                return (folder.appendingPathComponent(name),folder.appendingPathComponent(targetName))
                            }
                            if companionPairs.contains(where: { fm.fileExists(atPath:$0.1.path) }) { continue }
                            destination = fileDest; pairs = companionPairs; break
                        }
                        guard let finalURL = destination else { throw NSError(domain:"Rename",code:4,userInfo:[NSLocalizedDescriptionKey:"중복 이름이 너무 많습니다."]) }
                        try fm.moveItem(at:entry.url,to:finalURL)
                        var movedCompanions: [(URL,URL)] = []
                        do {
                            for (source,target) in pairs {
                                try fm.moveItem(at:source,to:target)
                                movedCompanions.append((source,target))
                            }
                        } catch {
                            for (source,target) in movedCompanions.reversed() { try? fm.moveItem(at:target,to:source) }
                            try? fm.moveItem(at:finalURL,to:entry.url)
                            throw error
                        }
                        renamed += 1
                    } catch {
                        failed += 1
                        if errors.count < 6 { errors.append("\(entry.url.lastPathComponent): \(error.localizedDescription)") }
                    }
                }
                JobProgressManager.shared.updateJob(id:jobID,progress:Double(idx + 1)/Double(selected.count))
            }
            JobProgressManager.shared.finishJob(id:jobID)
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "촬영일시 검증 후 이름 변경 결과"
                alert.informativeText = "완료 \(renamed)개 / 이미 적용됨 \(skipped)개 / 실패 \(failed)개" +
                    (errors.isEmpty ? "" : "\n\n" + errors.joined(separator:"\n"))
                alert.runModal()
            }
        }
    }

    static func mediaDurationSeconds(for url: URL) -> Double {
        if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let sec = MDItemCopyAttribute(mdItem, kMDItemDurationSeconds) as? Double,
           sec.isFinite && sec > 0 { return sec }
        if let af = try? AVAudioFile(forReading: url) {
            let sr = af.processingFormat.sampleRate
            if sr > 0 { return Double(af.length) / sr }
        }
        return 10.0
    }
    
    static func convertVideoToAnimatedGIFNative(file: URL, outURL: URL, qualityPercent: Double) {
        let jobTitle = "\(file.lastPathComponent) → GIF"
        let jobID = JobProgressManager.shared.startJob(title: jobTitle)
        
        Task {
            let asset = AVURLAsset(url: file)
            var durationSec: Double = 5.0
            if let cmDur = try? await asset.load(.duration) {
                let s = CMTimeGetSeconds(cmDur)
                if s.isFinite && s > 0 { durationSec = s }
            }
            
            let qRatio = max(0.1, min(1.0, qualityPercent / 100.0))
            let fps: Double = qualityPercent >= 85 ? 12.0 : (qualityPercent >= 50 ? 10.0 : 8.0)
            let maxDimension: CGFloat = CGFloat(320.0 + 640.0 * qRatio)
            let totalFrames = max(2, min(360, Int((durationSec * fps).rounded())))
            let frameDelay = 1.0 / fps
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.04, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
            
            guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.gif.identifier as CFString, totalFrames, nil) else {
                JobProgressManager.shared.finishJob(id: jobID)
                showToast("GIF 생성기를 초기화할 수 없습니다.")
                return
            }
            
            let fileProps: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
            CGImageDestinationSetProperties(dest, fileProps as CFDictionary)
            
            let frameProps: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frameDelay,
                    kCGImagePropertyGIFUnclampedDelayTime: frameDelay
                ]
            ]
            
            var addedCount = 0
            for i in 0..<totalFrames {
                let sec = min(durationSec - 0.01, Double(i) * frameDelay)
                let cmTime = CMTime(seconds: max(0.0, sec), preferredTimescale: 600)
                if let cgImg = try? generator.copyCGImage(at: cmTime, actualTime: nil) {
                    CGImageDestinationAddImage(dest, cgImg, frameProps as CFDictionary)
                    addedCount += 1
                }
                JobProgressManager.shared.updateJob(id: jobID, progress: Double(i + 1) / Double(totalFrames))
            }
            
            let ok = addedCount > 0 && CGImageDestinationFinalize(dest)
            JobProgressManager.shared.finishJob(id: jobID)
            
            if ok {
                preserveFileDates(from: file, to: outURL)
                showToast("움직이는 GIF 변환 완료: \(outURL.lastPathComponent)")
            } else {
                try? FileManager.default.removeItem(at: outURL)
                showToast("GIF 변환에 실패했습니다.")
            }
        }
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
                try task.run(); task.waitUntilExit()
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
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]),
              let s = Double(parts[2].split(separator: " ").first ?? "") else { return nil }
        return h * 3600.0 + m * 60.0 + s
    }
    
    static func runShell(_ launchPath: String, args: [String], completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: launchPath)
            task.arguments = args
            do {
                try task.run(); task.waitUntilExit()
                DispatchQueue.main.async { completion(task.terminationStatus == 0) }
            } catch { DispatchQueue.main.async { completion(false) } }
        }
    }
    
    static func execute(actionKey: String, files: [URL], openQualityPopup: Bool = false) {
        guard !files.isEmpty else { return }
        if actionKey == "act_join_images" { ToolWindowManager.shared.showImageJoinWindow(urls: files); return }
        if actionKey == "tool_rename_date" { batchRenameFilesWithCaptureDate(files: files); return }
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
            if files.count > 1 { mergeToPDF(files: files) } else if let first = files.first { readQRCode(from: first) }
            return
        }
        if actionKey == "tool_merge_pdf" { mergeToPDF(files: files); return }
        if actionKey == "act_copy_path" {
            let paths = files.map { $0.path }.joined(separator: "\n")
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(paths, forType: .string)
            showToast("\(files.count)개 파일 경로가 클립보드에 복사되었습니다."); return
        }
        if actionKey == "act_terminal", let first = files.first {
            let folder = first.hasDirectoryPath ? first.path : first.deletingLastPathComponent().path
            runShell("/usr/bin/open", args: ["-a", "Terminal", folder]) { _ in }; return
        }
        if actionKey == "act_finder" { NSWorkspace.shared.activateFileViewerSelecting(files); return }
        if actionKey == "act_airdrop" {
            if let service = NSSharingService(named: .sendViaAirDrop) { service.perform(withItems: files) }
            return
        }
        if actionKey == "act_duplicate" {
            DispatchQueue.global(qos: .userInitiated).async {
                for f in files {
                    autoreleasepool {
                        let out = uniqueOutputURL(for: f, newExt: f.pathExtension, suffix: "_copy")
                        try? FileManager.default.copyItem(at: f, to: out)
                        preserveFileDates(from: f, to: out)
                    }
                }
                showToast("총 \(files.count)개 파일 사본 생성 완료!")
            }
            return
        }
        
        if actionKey.hasPrefix("conv_") {
            let targetExt = actionKey.replacingOccurrences(of: "conv_", with: "")
            if openQualityPopup && !["zip", "targz"].contains(targetExt) {
                ToolWindowManager.shared.showConvertQualityWindow(urls: files, targetExt: targetExt)
                return
            }
            batchConvertFiles(files, to: targetExt, qualityPercent: 92.0)
            return
        }
        
        if actionKey == "tool_strip_meta" {
            DispatchQueue.global(qos: .userInitiated).async {
                let jobID = JobProgressManager.shared.startJob(title: "메타데이터 삭제 (\(files.count)개)")
                for (i, file) in files.enumerated() {
                    autoreleasepool { stripMetadata(file: file, silent: files.count > 1) }
                    JobProgressManager.shared.updateJob(id: jobID, progress: Double(i + 1) / Double(files.count))
                }
                JobProgressManager.shared.finishJob(id: jobID)
                if files.count > 1 { showToast("총 \(files.count)개 파일 메타데이터 제거 완료!") }
            }
        }
    }
    
    // 수백~수천 개 파일 일괄 포맷 변환 시 백그라운드 큐에서 순차적으로 메모리 누수 없이 변환
    static func batchConvertFiles(_ files: [URL], to ext: String, qualityPercent: Double) {
        if files.count == 1, let first = files.first {
            convertFile(first, to: ext, qualityPercent: qualityPercent)
            return
        }
        let cgSupportedExts = ["jpg", "jpeg", "png", "heic", "tiff", "bmp"]
        if cgSupportedExts.contains(ext) {
            let total = files.count
            let jobID = JobProgressManager.shared.startJob(title: "\(ext.uppercased()) 일괄 변환 (\(total)개)")
            let qNorm = max(0.01, min(1.0, qualityPercent / 100.0))
            DispatchQueue.global(qos: .userInitiated).async {
                var successCount = 0
                for (idx, file) in files.enumerated() {
                    autoreleasepool {
                        if let cgImg = loadRawCGImage(from: file) {
                            let out = uniqueOutputURL(for: file, newExt: ext)
                            if saveCGImage(cgImg, to: out, formatExt: ext, quality: qNorm, sourceURLForMetadata: file) {
                                preserveFileDates(from: file, to: out)
                                successCount += 1
                            }
                        }
                    }
                    JobProgressManager.shared.updateJob(id: jobID, progress: Double(idx + 1) / Double(total))
                }
                JobProgressManager.shared.finishJob(id: jobID)
                showToast("총 \(successCount)개 파일 \(ext.uppercased()) 변환 완료!")
            }
        } else {
            for f in files {
                convertFile(f, to: ext, qualityPercent: qualityPercent)
            }
        }
    }
    
    static func convertFile(_ file: URL, to ext: String, qualityPercent: Double = 92.0) {
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
        if ext == "gif" {
            let out = uniqueOutputURL(for: file, newExt: "gif")
            convertVideoToAnimatedGIFNative(file: file, outURL: out, qualityPercent: qualityPercent)
            return
        }
        
        let qNormalized = max(0.01, min(1.0, qualityPercent / 100.0))
        let cgSupportedExts = ["jpg", "jpeg", "png", "heic", "tiff", "bmp"]
        if cgSupportedExts.contains(ext) {
            DispatchQueue.global(qos: .userInitiated).async {
                if let cgImg = loadRawCGImage(from: file) {
                    let out = uniqueOutputURL(for: file, newExt: ext)
                    if saveCGImage(cgImg, to: out, formatExt: ext, quality: qNormalized, sourceURLForMetadata: file) {
                        preserveFileDates(from: file, to: out)
                        let qLabel = Int(qualityPercent.rounded())
                        showToast("\(ext.uppercased()) 변환 완료 (퀄리티 \(qLabel)%, 메타데이터 보존)!")
                        return
                    }
                }
            }
            return
        }
        
        let sipsFormats = ["jpg": "jpeg", "png": "png", "heic": "heic", "tiff": "tiff", "bmp": "bmp", "icns": "icns"]
        if let sipsFormat = sipsFormats[ext] {
            let out = uniqueOutputURL(for: file, newExt: ext)
            let qArg = String(format: "%.0f", qualityPercent)
            runShell("/usr/bin/sips", args: ["-s", "format", sipsFormat, "-s", "formatOptions", qArg, file.path, "--out", out.path]) { ok in
                if ok {
                    preserveFileDates(from: file, to: out)
                    showToast("\(ext.uppercased()) 변환 완료!")
                } else {
                    convertMediaHybrid(file, to: ext, qualityPercent: qualityPercent)
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
        convertMediaHybrid(file, to: ext, qualityPercent: qualityPercent)
    }
    
    static func convertMediaHybrid(_ file: URL, to ext: String, qualityPercent: Double = 92.0) {
        let out = uniqueOutputURL(for: file, newExt: ext)
        if ext == "gif" {
            convertVideoToAnimatedGIFNative(file: file, outURL: out, qualityPercent: qualityPercent)
            return
        }
        let duration = mediaDurationSeconds(for: file)
        let qInt = Int(qualityPercent.rounded())
        let jobTitle = "\(file.lastPathComponent) → \(ext.uppercased()) (\(qInt)%)"
        
        let crf = qualityPercent >= 99.5 ? 0 : Int((42.0 - (qualityPercent / 100.0) * 24.0).rounded())
        let audioBitrateK = Int((64.0 + (qualityPercent / 100.0) * 256.0).rounded())
        
        if ffmpegPath != nil {
            var args = ["-y", "-i", file.path, "-map_metadata", "0"]
            if ext == "mp4" {
                args += ["-movflags", "use_metadata_tags", "-c:v", "libx264", "-preset", "fast", "-crf", "\(crf)", "-c:a", "aac", "-b:a", "\(audioBitrateK)k", "-pix_fmt", "yuv420p", out.path]
            } else if ext == "mov" {
                args += ["-movflags", "use_metadata_tags", "-c:v", "libx264", "-crf", "\(crf)", "-c:a", "aac", "-b:a", "\(audioBitrateK)k", out.path]
            } else if ext == "mp3" {
                args += ["-vn", "-c:a", "libmp3lame", "-b:a", "\(audioBitrateK)k", out.path]
            } else if ext == "m4a" {
                args += ["-vn", "-c:a", "aac", "-b:a", "\(audioBitrateK)k", out.path]
            } else if ext == "wav" {
                args += ["-vn", "-c:a", "pcm_s16le", out.path]
            } else if ext == "flac" {
                args += ["-vn", "-c:a", "flac", out.path]
            } else {
                args.append(out.path)
            }
            runFFmpegWithProgress(args: args, totalDuration: duration, jobTitle: jobTitle) { ok in
                if ok && FileManager.default.fileExists(atPath: out.path) && ((try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int64) ?? 0) > 256 {
                    preserveFileDates(from: file, to: out)
                    showToast("\(ext.uppercased()) 변환 완료 (\(qInt)%): \(out.lastPathComponent)")
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
        if ext == "gif" {
            convertVideoToAnimatedGIFNative(file: file, outURL: outURL, qualityPercent: 90.0)
            return
        }
        let asset = AVURLAsset(url: file)
        let isAudioOnly = ["m4a", "mp3", "wav", "aiff", "flac", "caf"].contains(ext)
        let preset = isAudioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            showToast("변환기를 초기화할 수 없습니다."); return
        }
        var targetURL = outURL
        if isAudioOnly { targetURL = uniqueOutputURL(for: file, newExt: "m4a"); exporter.outputFileType = .m4a }
        else if ext == "mp4" { exporter.outputFileType = .mp4 }
        else { targetURL = uniqueOutputURL(for: file, newExt: "mov"); exporter.outputFileType = .mov }
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
    
    static func stripMetadata(file: URL, silent: Bool = false) {
        let out = uniqueOutputURL(for: file, newExt: file.pathExtension, suffix: "_clean")
        if let cgImg = loadRawCGImage(from: file) {
            _ = saveCGImage(cgImg, to: out, formatExt: file.pathExtension, quality: 0.95, sourceURLForMetadata: nil)
            if !silent { showToast("메타데이터 제거 완료: \(out.lastPathComponent)") }
        } else if ffmpegPath != nil {
            let dur = mediaDurationSeconds(for: file)
            runFFmpegWithProgress(args: ["-y", "-i", file.path, "-map_metadata", "-1", "-c", "copy", out.path], totalDuration: dur, jobTitle: "메타데이터 삭제") { _ in
                if !silent { showToast("미디어 메타데이터 제거 완료!") }
            }
        }
    }
    
    static func loadRawCGImage(from url: URL) -> CGImage? {
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary)
    }
    
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
           let src = CGImageSourceCreateWithURL(srcURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let origProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            metadataProps = origProps
            metadataProps[kCGImagePropertyPixelWidth] = cgImage.width
            metadataProps[kCGImagePropertyPixelHeight] = cgImage.height
        }
        metadataProps[kCGImageDestinationLossyCompressionQuality] = quality
        
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) {
            CGImageDestinationAddImage(dest, cgImage, metadataProps as CFDictionary)
            if CGImageDestinationFinalize(dest) {
                if let srcURL = sourceURLForMetadata { preserveFileDates(from: srcURL, to: url) }
                return true
            }
        }
        
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let data: Data?
        if ext == "png" { data = rep.representation(using: .png, properties: [:]) }
        else if ext == "tiff" { data = rep.representation(using: .tiff, properties: [:]) }
        else if ext == "bmp" { data = rep.representation(using: .bmp, properties: [:]) }
        else { data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) }
        guard let data = data else { return false }
        do {
            try data.write(to: url)
            if let srcURL = sourceURLForMetadata { preserveFileDates(from: srcURL, to: url) }
            return true
        } catch { return false }
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
        let jobID = JobProgressManager.shared.startJob(title: "PDF 병합 (\(files.count)개)")
        DispatchQueue.global(qos: .userInitiated).async {
            let pdf = PDFDocument()
            for (idx, f) in files.enumerated() {
                autoreleasepool {
                    if f.pathExtension.lowercased() == "pdf", let sub = PDFDocument(url: f) {
                        for i in 0..<sub.pageCount { if let page = sub.page(at: i) { pdf.insert(page, at: pdf.pageCount) } }
                    } else if let img = NSImage(contentsOf: f), let page = PDFPage(image: img) {
                        pdf.insert(page, at: pdf.pageCount)
                    }
                }
                JobProgressManager.shared.updateJob(id: jobID, progress: Double(idx + 1) / Double(files.count))
            }
            let out = uniqueOutputURL(for: first, newExt: "pdf", suffix: "_merged")
            pdf.write(to: out)
            preserveFileDates(from: first, to: out)
            JobProgressManager.shared.finishJob(id: jobID)
            showToast("PDF 병합 완료: \(out.lastPathComponent)")
        }
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
    let wheelSize: CGFloat = 316
    let containerSize: CGFloat = 440
    
    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: wheelSize + 18, height: wheelSize + 18)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.8))
                .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 6)
            
            slicesView
            centerBadgeView
        }
        .frame(width: containerSize, height: containerSize)
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
            LinearGradient(colors: [Color.white.opacity(0.82), Color.white.opacity(0.52)], startPoint: .top, endPoint: .bottom)
        return ZStack {
            PieSliceShape(startAngle: start, endAngle: end).fill(fillGrad)
                .overlay(PieSliceShape(startAngle: start, endAngle: end).stroke(isHovered ? Color.white : Color.black.opacity(0.08), lineWidth: 1.2))
            VStack(spacing: 2) {
                Image(systemName: item.icon).font(.system(size: 15, weight: .semibold))
                Text(item.title).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
                if let est = item.estimatedSizeText {
                    Text(state.isQualityOptionActive ? "1~100% 설정" : est)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(isHovered ? .white.opacity(0.95) : (state.isQualityOptionActive ? .orange : .black.opacity(0.62)))
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
            Text(state.wheelMode.rawValue)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.orange)
            Text(state.totalSizeText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text("\(state.draggedFiles.count)개 파일 선택됨")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.secondary)
            
            if state.wheelMode == .convert && state.isQualityOptionActive {
                Text("🎯 퀄리티 선택 · 키 떼면 일반")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Color.orange, in: Capsule())
            } else if let idx = state.hoveredIndex, idx < state.items.count, let est = state.items[idx].estimatedSizeText {
                Text("예상 \(est)").font(.system(size: 9.5, weight: .heavy, design: .monospaced)).foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(state.isQualityOptionActive ? Color.orange : Color.white.opacity(0.5), lineWidth: 1.5))
    }
}

// MARK: - macOS 파일·폴더 접근 안내 (사용자 동의 우선)
// 이 앱은 App Sandbox를 사용하지 않으므로 '보안 범위 북마크를 통한 영구 권한'을
// 가장하지 않습니다. NSOpenPanel에서 사용자가 폴더를 고르면 macOS에 그 선택을
// 명시적으로 전달합니다. 저장하는 경로 목록은 편의 기능이며 TCC 권한 자체가 아닙니다.
final class FolderAccessPreferences: ObservableObject {
    static let shared = FolderAccessPreferences()
    private let pathsKey = "tangerine_selected_folders_v48"
    private let introKey = "tangerine_folder_access_intro_v48"

    @Published private(set) var selectedPaths: [String]
    @Published var notice: String = "폴더를 선택하면 macOS가 해당 접근을 확인할 수 있습니다."

    private init() {
        selectedPaths = UserDefaults.standard.stringArray(forKey: pathsKey) ?? []
    }

    var shouldShowIntro: Bool {
        !UserDefaults.standard.bool(forKey: introKey)
    }
    func markIntroShown() {
        UserDefaults.standard.set(true, forKey: introKey)
    }
    func chooseFolders(startAt preferred: URL? = nil) {
        let panel = NSOpenPanel()
        panel.title = "00Favorite에서 사용할 폴더 선택"
        panel.message = "본인이 사용할 폴더를 선택하세요. 모든 디스크 권한을 자동으로 요청하지 않습니다."
        panel.prompt = "이 폴더 선택"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if let preferred = preferred { panel.directoryURL = preferred }
        guard panel.runModal() == .OK else { return }
        let selected = panel.urls.map { $0.standardizedFileURL.path }
        let unique = Set(selectedPaths).union(selected)
        selectedPaths = unique.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        UserDefaults.standard.set(selectedPaths, forKey: pathsKey)
        notice = "폴더 \(selected.count)개를 선택했습니다. 실제 접근 권한은 macOS가 관리합니다."
    }
    func removeRecentPath(_ path: String) {
        selectedPaths.removeAll { $0 == path }
        UserDefaults.standard.set(selectedPaths, forKey: pathsKey)
        notice = "최근 선택 목록에서 삭제했습니다. macOS가 승인한 권한은 시스템 설정에서 별도로 관리합니다."
    }
    func openFilesAndFoldersSettings() {
        openSystemSettings("Privacy_FilesAndFolders")
    }
    func openFullDiskAccessSettings() {
        openSystemSettings("Privacy_AllFiles")
    }
    func openInputMonitoringSettings() {
        openSystemSettings("Privacy_ListenEvent")
    }
    func openAccessibilitySettings() {
        openSystemSettings("Privacy_Accessibility")
    }
    private func openSystemSettings(_ target: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(target)"),
           NSWorkspace.shared.open(url) { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            _ = NSWorkspace.shared.open(url)
        }
    }
}

struct FolderPermissionView: View {
    @ObservedObject private var permissions = FolderAccessPreferences.shared

    private func suggested(_ kind: FileManager.SearchPathDirectory) -> URL? {
        FileManager.default.urls(for: kind, in: .userDomainMask).first
    }

    var body: some View {
        ScrollView { content }
    }

    // 고급 설정 내부에 중첩 ScrollView 없이 삽입할 수 있는 동일한 폴더 접근 UI.
    var content: some View {
            VStack(alignment: .leading, spacing: 16) {
                Label("파일·폴더 접근 설정", systemImage: "folder.badge.gearshape")
                    .font(.title3.bold()).foregroundColor(.orange)
                Text("다운로드·문서·바탕화면 등 필요한 폴더를 미리 지정할 수 있습니다. 버튼을 누르면 macOS의 기본 폴더 선택 창이 나타납니다. 사용자가 직접 선택해야 하며, 앱이 권한을 강제로 허용하지는 않습니다.")
                    .font(.subheadline).foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("1. 자주 사용하는 폴더 선택").font(.headline)
                    HStack(spacing: 10) {
                        Button("다운로드 폴더") { permissions.chooseFolders(startAt: suggested(.downloadsDirectory)) }
                        Button("문서 폴더") { permissions.chooseFolders(startAt: suggested(.documentDirectory)) }
                        Button("바탕화면 폴더") { permissions.chooseFolders(startAt: suggested(.desktopDirectory)) }
                    }
                    Button("다른 폴더 / 외장 디스크 선택…") { permissions.chooseFolders() }
                    Text("폴더 선택 후에도 macOS에서 추가 승인 창이 나타날 수 있습니다. 선택한 경로의 읽기·쓰기 권한을 무조건 보장하는 기능은 아닙니다.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 9) {
                    Text("2. 최근 선택한 폴더").font(.headline)
                    if permissions.selectedPaths.isEmpty {
                        Text("아직 선택한 폴더가 없습니다.").foregroundColor(.secondary)
                    } else {
                        ForEach(permissions.selectedPaths, id: \.self) { path in
                            HStack(spacing: 9) {
                                Image(systemName: "folder").foregroundColor(.orange)
                                Text(path).font(.system(.caption, design: .monospaced)).lineLimit(2)
                                    .textSelection(.enabled)
                                Spacer(minLength: 8)
                                Button("목록에서 제거") { permissions.removeRecentPath(path) }
                                    .font(.caption).buttonStyle(.borderless)
                            }
                        }
                    }
                    Text("이 목록은 사용자가 선택한 폴더를 기억하는 용도이며 macOS의 실제 권한 상태를 표시하지 않습니다.")
                        .font(.caption2).foregroundColor(.secondary)
                    Text(permissions.notice).font(.caption).foregroundColor(.secondary)
                }
                .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 10) {
                    Text("3. macOS 개인정보 접근 권한 관리").font(.headline)
                    HStack(spacing: 10) {
                        Button("파일 및 폴더 설정 열기") { permissions.openFilesAndFoldersSettings() }
                        Button("손쉬운 사용 설정 열기") { permissions.openAccessibilitySettings() }
                    }
                    Button("전체 디스크 접근 설정 열기 (선택 사항)") {
                        permissions.openFullDiskAccessSettings()
                    }
                    Text("전체 디스크 접근은 일반적인 이미지·영상 변환에 필요하지 않습니다. 반드시 필요한 경우에만 Mac 시스템 설정에서 직접 승인하세요. macOS 버전에 따라 설정 화면의 위치가 다를 수 있습니다.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                Text("참고: 현재 GitHub 앱은 임시 서명입니다. 앱을 새로 빌드해 설치하면 macOS가 접근 권한을 다시 요청할 수 있으며, 이 현상은 폴더 선택만으로 완전히 해결되지 않습니다.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(22)
    }
}

// MARK: - 6. 도구 창 매니저 및 설정 창
class ToolWindowManager {
    static let shared = ToolWindowManager()
    var activeWindows: [NSWindow] = []
    var bannerWindow: NSPanel?
    private var settingsWindow: NSWindow?
    static let settingsNavigation = Notification.Name("00Favorite.Settings.Navigate")
    
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
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 52), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .statusBar
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 220, y: screen.frame.maxY - 90)) }
        panel.contentView = NSHostingView(rootView:
            HStack(spacing: 10) {
                if let customIcon = FileProcessor.customAppIconImage() {
                    Image(nsImage: customIcon).resizable().scaledToFit().frame(width: 24, height: 24)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.orange).font(.title2)
                }
                Text(message).font(.system(size: 13, weight: .semibold)).foregroundColor(.primary)
            }
            .padding(.horizontal, 18).padding(.vertical, 12).background(.regularMaterial, in: Capsule()).shadow(radius: 10)
        )
        panel.orderFrontRegardless(); bannerWindow = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { panel.close() }
    }
    
    func showRenameReviewWindow(urls: [URL]) {
        openWindow(title: "촬영일시 근거 확인 후 이름 변경", view: RenameReviewView(files: urls), size: NSSize(width: 860, height: 670), minSize: NSSize(width: 690, height: 520))
    }
    func showImageJoinWindow(urls: [URL]) {
        openWindow(title: "이미지 세로 합치기", view: ImageJoinView(files: urls), size: NSSize(width: 780, height: 660), minSize: NSSize(width: 640, height: 500))
    }
    func showHelpAndSettingsWindow(tab: Int? = nil) {
        // 설명 및 설정은 단 하나의 창만 유지합니다. 최소화·가림·닫힘 상태도 복원합니다.
        if let window = settingsWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            // 평소 설정 버튼 재클릭은 기존 탭을 유지합니다. 명시적 고급 설정 이동에만 탭 변경.
            if let tab = tab {
                NotificationCenter.default.post(name: Self.settingsNavigation, object: nil,
                                                userInfo: ["tab": tab])
            }
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 860, height: 740)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "⭐ 00Favorite — 설명 및 설정"
        window.minSize = NSSize(width: 740, height: 600)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: HelpAndSettingsView(initialTab: tab ?? 0))
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func showFolderPermissionsWindow() {
        // 최초 폴더 접근 안내도 같은 설정창의 고급 설정으로 열립니다.
        showHelpAndSettingsWindow(tab: 3)
    }
    func showConvertQualityWindow(urls: [URL], targetExt: String) {
        openWindow(title: "포맷 변환 퀄리티 설정 (\(targetExt.uppercased()))", view: ConvertQualityPopupView(files: urls, targetExt: targetExt), size: NSSize(width: 500, height: 390), minSize: NSSize(width: 460, height: 360))
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
        openWindow(title: "QuickTime & Multi-Channel Studio — \(url.lastPathComponent)", view: ProMediaStudioView(fileURL: url, initialMode: initialTab), size: NSSize(width: 1080, height: 830), minSize: NSSize(width: 920, height: 700))
    }
}

struct HelpAndSettingsView: View {
    @ObservedObject var settings = ShortcutSettings.shared
    @State private var selectedTab: Int

    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }
    @State private var recordingTarget: String? = nil
    @State private var tempRecordedFlags: NSEvent.ModifierFlags = []
    @State private var localMonitor: Any? = nil
    @State private var shortcutValidationWarning: String = ""
    @State private var awakeMinutes: Int = FavoriteAwakeHotKey.shared.toggleMinutes
    @State private var awakeHotkeyNotice: String = ""
    @State private var awakeIsRecording = false
    @State private var awakeKeyCode: UInt32? = nil
    @State private var awakeKeyName: String = ""
    @State private var awakeKeyFlags: NSEvent.ModifierFlags = []
    @State private var awakeKeyMonitor: Any? = nil
    @State private var wheelMonitorStatus = "확인 전"
    @State private var wheelRecentDiagnostic = "아직 파일 드래그 시도 없음"
    
    let sampleDate: Date = {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 10; comp.day = 11
        comp.hour = 17; comp.minute = 5; comp.second = 35
        return Calendar.current.date(from: comp) ?? Date()
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    if let customIcon = FileProcessor.customAppIconImage() {
                        Image(nsImage: customIcon).resizable().scaledToFit().frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "circle.hexagongrid.fill").font(.system(size: 36)).foregroundColor(.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("00Favorite 4.8 Pro").font(.system(size: 20, weight: .heavy, design: .rounded))
                        Text("수천 개 대량 파일 일괄 처리 엔진 · 초저전력 최적화 · 무결점 3종 휠").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Picker("설정 항목", selection: $selectedTab) {
                    Text("⌨️ 단축키 설정").tag(0)
                    Text("🏷️ 이름 변환 양식").tag(1)
                    Text("📖 사용 설명서").tag(2)
                    Text("⚙️ 고급 설정").tag(3)
                }.labelsHidden().pickerStyle(.segmented)
            }
            .padding(18).background(.regularMaterial)
            Divider()
            
            if selectedTab == 0 {
                shortcutRecorderTab
            } else if selectedTab == 1 {
                renamePatternTab
            } else if selectedTab == 3 {
                advancedTab
            } else {
                usageGuideTab
            }
            
            Divider()
            HStack {
                Text("💡 수천 개의 파일을 한 번에 드래그해도 누락 없이 백그라운드에서 초고속으로 처리됩니다.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("기본 설정 복원") {
                    stopRecording()
                    settings.resetToFavoriteDefaults()
                    settings.renamePattern = ShortcutSettings.defaultRenamePattern
                    _ = FavoriteAwakeHotKey.shared.changePreset(.controlOptionPeriod)
                    FavoriteAwakeHotKey.shared.setToggleMinutes(60)
                    awakeMinutes = FavoriteAwakeHotKey.shared.toggleMinutes
                    (NSApp.delegate as? AppDelegate)?.updateStatusBarMenu()
                    FileProcessor.showToast("단축키 및 작동 방식이 기본값으로 복원되었습니다.")
                }
                Button("닫기") { stopRecording(); stopAwakeRecording(); NSApp.keyWindow?.close() }
                    .buttonStyle(.borderedProminent).tint(.orange)
            }
            .padding(14).background(.regularMaterial)
        }.onAppear { refreshWheelMonitorStatus() }
         .onReceive(NotificationCenter.default.publisher(for: ToolWindowManager.settingsNavigation)) { note in
             if let newTab = note.userInfo?["tab"] as? Int, (0...3).contains(newTab) {
                 selectedTab = newTab
             }
         }
         .onChange(of: selectedTab) { _ in stopRecording(); stopAwakeRecording() }
         .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
             if let window = note.object as? NSWindow,
                window.title == "⭐ 00Favorite — 설명 및 설정" {
                 stopRecording()
                 stopAwakeRecording()
             }
         }
         .onDisappear { stopRecording(); stopAwakeRecording() }
    }
    
    // 사용자에게는 필요할 때만 표시하는 입력 감시·폴더 접근 관리 화면.
    var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("고급 설정").font(.title3.bold()).foregroundColor(.orange)
                Text("평상시에는 변경하지 않아도 됩니다. 휠 안전 모드는 기본 적용되며, 문제가 있을 때만 진단·재연결을 사용하세요.")
                    .font(.caption).foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 9) {
                    Label("안전 모드 (항상 적용)", systemImage: "shield.checkered")
                        .font(.headline).foregroundColor(.green)
                    Text("Finder의 키 입력과 마우스 드래그를 가로채거나 변경하지 않습니다. 휠 조각 위에 실제 파일을 드롭한 경우에만 00Favorite 작업이 시작됩니다. 다른 위치에 놓으면 macOS가 원래 드롭을 처리합니다.")
                        .font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                        Text("휠 감지: 자동 켜짐 (설정할 필요 없음)")
                            .font(.subheadline)
                    }
                    Toggle("Finder에서 시작한 파일 드래그만 감지 (권장)", isOn: $settings.finderOnlyDetection)
                    HStack(spacing: 8) {
                        Text("휠 입력 감시: \(wheelMonitorStatus)")
                            .font(.caption.bold())
                        Spacer()
                        Button("상태 새로고침") { refreshWheelMonitorStatus() }
                        Button("감시 재연결") {
                            guard let delegate = NSApp.delegate as? AppDelegate else { return }
                            let connected = delegate.reconnectWheelMonitor()
                            refreshWheelMonitorStatus()
                            if !connected {
                                awakeHotkeyNotice = "휠 감시 연결 실패: macOS 개인정보 보호 및 보안 → 입력 모니터링·손쉬운 사용에서 00Favorite 권한을 확인하고 앱을 재시작해 주세요."
                            }
                        }
                    }
                    Text("최근 드래그 진단: \(wheelRecentDiagnostic)")
                        .font(.caption2).foregroundColor(.secondary)
                        .textSelection(.enabled)
                    Text("휠 감시 '정상 연결'은 이벤트 탭 활성화만 뜻합니다. 변환이 안 되면 Finder에서 드래그→수정키를 누른 뒤 '상태 새로고침'을 눌러 위 진단을 확인하세요.")
                        .font(.caption2).foregroundColor(.secondary)
                        .font(.caption2).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Button("입력 모니터링 설정") { FolderAccessPreferences.shared.openInputMonitoringSettings() }
                        Button("손쉬운 사용 설정") { FolderAccessPreferences.shared.openAccessibilitySettings() }
                    }
                    Text("기본값: 변환 Shift / 편집 Option+Shift / 액션 Control. 설정에서 다른 조합으로 변경했다면 그 조합을 사용하세요. Finder 파일 드래그 시작 후 키를 새로 눌러야 휠이 열립니다.")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(14).background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                Divider()
                FolderPermissionView().content
            }
            .padding(20)
        }
    }

    var shortcutRecorderTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("원형 휠 표시 방식").font(.headline).foregroundColor(.orange)
                    Picker("작동 방식", selection: $settings.isToggleMode) {
                        Text("누르고 있는 동안만 켜기 (Hold 방식)").tag(false)
                        Text("한 번 누르면 켜지고 다시 누르면 끄기 (Toggle 버튼 방식)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    
                    Text(settings.isToggleMode ?
                         "✅ 현재 [토글(버튼) 방식]: 파일을 드래그하면서 단축키(예: Shift)를 톡! 한 번만 눌렀다 떼도 휠이 계속 유지되며, 다시 한 번 누르면 꺼집니다." :
                         "✅ 현재 [홀드(누름 유지) 방식]: 파일을 드래그하면서 단축키를 누르고 있는 동안 휠이 표시되고, 키에서 손을 떼면 닫힙니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("단축키 설정").font(.headline).foregroundColor(.orange)
                    Text("모든 단축키를 같은 방식으로 설정합니다. 각 항목에서 [단축키 입력하기]를 누른 후 실제 키 조합을 눌러 저장하세요.")
                        .font(.caption).foregroundColor(.secondary)
                }
                
                if !shortcutValidationWarning.isEmpty {
                    Text(shortcutValidationWarning).font(.caption.bold()).foregroundColor(.red)
                }
                VStack(spacing: 12) {
                    recorderCard(
                        targetID: "convert", title: "🔄 포맷 변환 휠 (CONVERT)",
                        subtitle: "파일 드래그 중 이 키를 누르면 포맷 변환 휠이 열립니다.",
                        currentFlags: settings.convertFlags,
                        onSave: { newFlags in settings.convertFlagsRaw = newFlags.rawValue; FileProcessor.showToast("변환(CONVERT) 단축키가 저장되었습니다.") }
                    )
                    recorderCard(
                        targetID: "quality", title: "🎯 변환 시 1~100% 퀄리티 선택 옵션 키 (기본: ⌘ Command)",
                        subtitle: "변환 휠에서 이 키를 누른 채 확장자에 놓으면 퀄리티 창이 열립니다. 키를 떼면 즉시 일반 변환으로 돌아옵니다. Finder의 원본 파일 이동/복사 이벤트는 변경하지 않습니다.",
                        currentFlags: settings.qualityFlags,
                        onSave: { newFlags in settings.qualityModifierRaw = newFlags.rawValue; FileProcessor.showToast("퀄리티 옵션 단축키가 저장되었습니다.") }
                    )
                    recorderCard(
                        targetID: "tools", title: "🛠️ 전용 편집 도구 휠 (TOOLS)",
                        subtitle: "사진 보정(Edit), 크롭(Crop), 모자이크(Redact), 촬영일자 이름변경(Rename), 영상/오디오 트림, 압축 도구가 열립니다.",
                        currentFlags: settings.toolsFlags,
                        onSave: { newFlags in settings.toolsFlagsRaw = newFlags.rawValue; FileProcessor.showToast("도구(TOOLS) 단축키가 저장되었습니다.") }
                    )
                    recorderCard(
                        targetID: "actions", title: "⚡ 빠른 액션 휠 (ACTIONS)",
                        subtitle: "촬영일자 이름변경, 경로 복사, 터미널 열기, AirDrop 전송, Finder 표시, 사본 만들기 휠이 열립니다.",
                        currentFlags: settings.actionsFlags,
                        onSave: { newFlags in settings.actionsFlagsRaw = newFlags.rawValue; FileProcessor.showToast("빠른 액션(ACTIONS) 단축키가 저장되었습니다.") }
                    )
                }
                awakeHotkeySettingsCard

            }.padding(20)
        }
    }
    
    // 원형 휠과 동일한 카드 레이아웃으로 표시하는 잠자기 방지 단축키.
    // 다른 입력 감시 코드와 별도로 등록되며, 파일 변환과 연동하지 않습니다.
    var awakeHotkeySettingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("🌙 잠자기 방지 켜기/끄기").font(.system(size: 14, weight: .bold))
                Text("파일 드래그와 무관하게 사용합니다. Control을 포함한 수정키 2개 이상 + 일반 키 1개. 기본 ⌃⌥.")
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: awakeIsRecording ? "keyboard.badge.ellipsis" : "keyboard")
                        .foregroundColor(awakeIsRecording ? .orange : .secondary)
                    Text(awakeIsRecording
                         ? (awakeKeyCode == nil
                             ? (awakeKeyFlags.isEmpty ? "원하는 단축키를 눌러주세요..." : ShortcutSettings.formatFlags(awakeKeyFlags) + " + 일반 키")
                             : ShortcutSettings.formatFlags(awakeKeyFlags) + " + " + awakeKeyName)
                         : FavoriteAwakeHotKey.shared.shortcutLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(awakeIsRecording ? .orange : .primary)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.black.opacity(awakeIsRecording ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(awakeIsRecording ? Color.orange : Color.white.opacity(0.2),
                            lineWidth: awakeIsRecording ? 2 : 1))
                if awakeIsRecording {
                    Button("완료") {
                        guard let code = awakeKeyCode else { return }
                        if FavoriteAwakeHotKey.shared.changeCustomShortcut(keyCode: code,
                              keyName: awakeKeyName, flags: awakeKeyFlags) {
                            awakeHotkeyNotice = "잠자기 방지 단축키가 저장되었습니다."
                            stopAwakeRecording()
                            (NSApp.delegate as? AppDelegate)?.updateStatusBarMenu()
                        } else {
                            awakeHotkeyNotice = FavoriteAwakeHotKey.shared.lastNotice
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .disabled(awakeKeyCode == nil)
                    Button("취소") { stopAwakeRecording() }
                } else {
                    Button("단축키 입력하기") { startAwakeRecording() }
                        .buttonStyle(.borderedProminent).tint(.orange)
                    Button("초기화") {
                        if FavoriteAwakeHotKey.shared.changePreset(.controlOptionPeriod) {
                            awakeHotkeyNotice = "기본 단축키 ⌃⌥.으로 복원했습니다."
                            (NSApp.delegate as? AppDelegate)?.updateStatusBarMenu()
                        } else { awakeHotkeyNotice = FavoriteAwakeHotKey.shared.lastNotice }
                    }
                    Button("사용 안 함") {
                        if FavoriteAwakeHotKey.shared.changePreset(.disabled) {
                            awakeHotkeyNotice = "잠자기 방지 단축키가 비활성화되었습니다."
                            (NSApp.delegate as? AppDelegate)?.updateStatusBarMenu()
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Text("단축키로 켰을 때 유지 시간")
                Picker("지속 시간", selection: $awakeMinutes) {
                    Text("5분").tag(5)
                    Text("15분").tag(15)
                    Text("30분").tag(30)
                    Text("1시간").tag(60)
                    Text("2시간").tag(120)
                    Text("4시간").tag(240)
                    Text("8시간").tag(480)
                    Text("직접 해제").tag(-1)
                }
                .frame(width: 190)
                .onChange(of: awakeMinutes) { minutes in
                    FavoriteAwakeHotKey.shared.setToggleMinutes(minutes)
                    (NSApp.delegate as? AppDelegate)?.updateStatusBarMenu()
                }
            }
            if !awakeHotkeyNotice.isEmpty {
                Text(awakeHotkeyNotice).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    var renamePatternTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("촬영일자 기반 파일명 일괄 변환 (RENAME) 설정").font(.headline).foregroundColor(.orange)
                    Text("RENAME으로 파일을 선택하면 EXIF·Sony XML·영상 내부 촬영일시를 분석해 출처와 신뢰도를 표시합니다. 촬영일이 없으면 변경하지 않으며, QuickTime 시간대가 불명확할 때는 파일별 확인 후 진행합니다.")
                        .font(.caption).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("파일명 변환 양식 입력").font(.subheadline.bold())
                    HStack(spacing: 10) {
                        TextField("예: {YYYYMMDD}_{hhmmss}_{Originalname}", text: $settings.renamePattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        Button("기본 양식") { settings.renamePattern = "{YYYYMMDD}_{hhmmss}_{Originalname}" }
                        Button("연-월-일 양식") { settings.renamePattern = "{YYYY}-{MM}-{DD}_{hh}{mm}{ss}_{filename}" }
                    }
                    let previewResult = ShortcutSettings.formatFileName(pattern: settings.renamePattern, originalName: "_DSC3015", captureDate: sampleDate, cameraModel: "ILCE-7M4", sequenceIndex: 1)
                    HStack(spacing: 12) {
                        Text("실시간 미리보기:").font(.caption.bold()).foregroundColor(.secondary)
                        Text("_DSC3015.JPG").font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Image(systemName: "arrow.right.circle.fill").foregroundColor(.orange)
                        Text("\(previewResult).JPG").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(12).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                
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
                        tokenInfoRow(code: "{Seq}", desc: "다중 파일 일괄 변경 시 순번 (0001, 0002...)")
                    }
                }
                .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }.padding(22)
        }
    }
    
    func tokenInfoRow(code: String, desc: String) -> some View {
        Button(action: { settings.renamePattern += code }) {
            HStack(spacing: 8) {
                Text(code).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                Text(desc).font(.caption).foregroundColor(.primary)
                Spacer()
            }
            .padding(8).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
    
    @ViewBuilder
    func recorderCard(targetID: String, title: String, subtitle: String, currentFlags: NSEvent.ModifierFlags, onSave: @escaping (NSEvent.ModifierFlags) -> Void) -> some View {
        let isRecordingThis = (recordingTarget == targetID)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: isRecordingThis ? "keyboard.badge.ellipsis" : "keyboard").foregroundColor(isRecordingThis ? .orange : .secondary)
                    if isRecordingThis {
                        Text(tempRecordedFlags.isEmpty ? "원하는 키 조합(Shift, Option, Control, Command)을 누르세요..." : ShortcutSettings.formatFlags(tempRecordedFlags))
                            .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.orange)
                    } else {
                        Text(ShortcutSettings.formatFlags(currentFlags))
                            .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.black.opacity(isRecordingThis ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isRecordingThis ? Color.orange : Color.white.opacity(0.2), lineWidth: isRecordingThis ? 2 : 1))
                
                if isRecordingThis {
                    Button("완료") {
                        if let warning = settings.validationMessage(for: tempRecordedFlags, target: targetID) {
                            shortcutValidationWarning = warning
                        } else {
                            shortcutValidationWarning = ""
                            onSave(tempRecordedFlags)
                            stopRecording()
                        }
                    }.buttonStyle(.borderedProminent).tint(.green).disabled(tempRecordedFlags.isEmpty)
                    Button("취소") { stopRecording() }
                } else {
                    Button("단축키 입력하기") { startRecording(for: targetID) }
                        .buttonStyle(.borderedProminent).tint(.orange)
                    Button("초기화") {
                        let original: NSEvent.ModifierFlags
                        switch targetID {
                        case "convert": original = NSEvent.ModifierFlags(rawValue: ShortcutSettings.defaultConvertRaw)
                        case "tools": original = NSEvent.ModifierFlags(rawValue: ShortcutSettings.defaultToolsRaw)
                        case "actions": original = NSEvent.ModifierFlags(rawValue: ShortcutSettings.defaultActionsRaw)
                        default: original = NSEvent.ModifierFlags(rawValue: ShortcutSettings.defaultQualityRaw)
                        }
                        if let warning = settings.validationMessage(for: original, target: targetID) {
                            shortcutValidationWarning = warning
                        } else {
                            shortcutValidationWarning = ""
                            onSave(original)
                        }
                    }
                }
            }
        }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func refreshWheelMonitorStatus() {
        if let app = NSApp.delegate as? AppDelegate {
            wheelMonitorStatus = app.isWheelMonitorConnected ? "정상 연결" : "연결되지 않음"
            wheelRecentDiagnostic = app.lastWheelDiagnostic
        } else { wheelMonitorStatus = "앱 상태 확인 불가" }
    }

    // 영문 자판의 물리 키 위치를 사용해 한글 키보드 레이아웃에서도 단축키를 지정합니다.
    private func awakeKeyLetter(_ code: UInt16) -> String? {
        let letters: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
            UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
            UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
            UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
            UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_ANSI_Period): ".", UInt16(kVK_ANSI_Comma): ",",
            UInt16(kVK_ANSI_Slash): "/", UInt16(kVK_ANSI_Minus): "-",
            UInt16(kVK_ANSI_Equal): "=", UInt16(kVK_ANSI_Semicolon): ";",
            UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_LeftBracket): "[",
            UInt16(kVK_ANSI_RightBracket): "]", UInt16(kVK_ANSI_Backslash): "\\",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1",
            UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
            UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
            UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9"
        ]
        return letters[code]
    }
    private func startAwakeRecording() {
        stopRecording()
        stopAwakeRecording()
        awakeHotkeyNotice = ""
        awakeIsRecording = true
        FavoriteAwakeHotKey.shared.suspendForRecorder()
        awakeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            guard self.awakeIsRecording else { return event }
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if event.type == .flagsChanged {
                if self.awakeKeyCode == nil { self.awakeKeyFlags = flags }
            } else if let label = self.awakeKeyLetter(event.keyCode) {
                self.awakeKeyCode = UInt32(event.keyCode)
                self.awakeKeyName = label
                self.awakeKeyFlags = flags
                self.awakeHotkeyNotice = "입력한 키를 확인한 뒤 [저장]을 누르세요."
            } else {
                self.awakeHotkeyNotice = "영문 A~Z, 숫자 0~9 또는 일반 문장부호 중 하나를 사용하세요."
            }
            return nil
        }
    }
    private func stopAwakeRecording() {
        if let m = awakeKeyMonitor { NSEvent.removeMonitor(m); awakeKeyMonitor = nil }
        awakeIsRecording = false
        awakeKeyCode = nil
        awakeKeyName = ""
        awakeKeyFlags = []
        FavoriteAwakeHotKey.shared.resumeAfterRecorder()
    }

    func startRecording(for targetID: String) {
        stopAwakeRecording()
        stopRecording(); shortcutValidationWarning = ""; recordingTarget = targetID; tempRecordedFlags = []
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
                guideCard(icon: "dial.high.fill", title: "1. 파일 변환 시 1~100% 퀄리티 선택 기능 & 순정 GIF 변환", items: [
                    "파일 드래그 중 Shift를 눌러 변환(CONVERT) 휠을 표시하고, 선택한 조각 위에 실제 파일을 놓으면 변환을 시작합니다. 휠 외부의 드롭은 Finder가 그대로 처리합니다.",
                    "변환 휠에서 ⌘ Command 키를 함께 누른 채로 확장자(JPG, WEBP, GIF, MP4 등)에 놓으면 1~100% 퀄리티 설정 창이 열립니다.",
                    "영상을 GIF로 변환할 때는 Apple 순정 애니메이션 GIF 엔진이 작동하여 깨짐 없이 미리보기/사파리에서 완벽히 열리는 GIF를 생성합니다."
                ])
                guideCard(icon: "scissors", title: "2. 타임라인 20배 확대/축소 정밀 트림 기능", items: [
                    "트림(TRIM) 창에서 타임라인 위쪽의 확대 슬라이더(1x ~ 20x)를 조절하거나 타임라인 위에서 마우스 휠을 굴리면 타임라인이 최대 20배까지 확대됩니다.",
                    "[🎯 트림 구간만 꽉 차게 확대] 버튼을 누르면 현재 선택된 시작~끝 구간만 화면에 큼직하게 확대되어 1프레임 단위로 미세 조정이 가능합니다."
                ])
                guideCard(icon: "square.stack", title: "3. 이미지 세로 합치기 (ACTIONS)", items: [
                    "파인더에서 이미지 2장 이상을 선택해 드래그하며 Control 키를 누른 뒤, ACTIONS 휠의 [이미지 합치기] 조각 위에 실제 파일을 놓습니다.",
                    "열린 창에서 순서, 가로폭, 간격, PNG/JPG/TIFF 또는 자동(초장축 TIFF 전환) 형식을 선택합니다.",
                    "원본 이미지는 수정하지 않으며 첫 번째 이미지가 있는 폴더에 새 파일을 만듭니다. 매우 긴 이미지는 메모리 보호를 위해 여러 장으로 자동 분할됩니다."
                ])
                guideCard(icon: "character.cursor.ibeam", title: "4. 수천 개 대량 파일 촬영일자 이름 일괄 변환 (RENAME)", items: [
                    "2,000개 이상의 사진이나 영상도 한꺼번에 잡고 TOOLS 또는 ACTIONS 휠의 [RENAME]에 놓으면 누락 없이 전수 스캔하여 일괄 변경합니다.",
                    "백그라운드 엔진이 작동하여 상단 메뉴바 아이콘 옆에 실시간 진행 퍼센트(%)가 표시됩니다."
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