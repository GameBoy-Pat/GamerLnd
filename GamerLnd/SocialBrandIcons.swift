import SwiftUI

private enum SocialBrand {
    case youtube
    case tiktok
    case twitch

    var svgPath: String {
        switch self {
        case .youtube:
            return "M581.7 188.1C575.5 164.4 556.9 145.8 533.4 139.5C490.9 128 320.1 128 320.1 128C320.1 128 149.3 128 106.7 139.5C83.2 145.8 64.7 164.4 58.4 188.1C47 231 47 320.4 47 320.4C47 320.4 47 409.8 58.4 452.7C64.7 476.3 83.2 494.2 106.7 500.5C149.3 512 320.1 512 320.1 512C320.1 512 490.9 512 533.5 500.5C557 494.2 575.5 476.3 581.8 452.7C593.2 409.8 593.2 320.4 593.2 320.4C593.2 320.4 593.2 231 581.8 188.1zM264.2 401.6L264.2 239.2L406.9 320.4L264.2 401.6z"
        case .tiktok:
            return "M544.5 273.9C500.5 274 457.5 260.3 421.7 234.7L421.7 413.4C421.7 446.5 411.6 478.8 392.7 506C373.8 533.2 347.1 554 316.1 565.6C285.1 577.2 251.3 579.1 219.2 570.9C187.1 562.7 158.3 545 136.5 520.1C114.7 495.2 101.2 464.1 97.5 431.2C93.8 398.3 100.4 365.1 116.1 336C131.8 306.9 156.1 283.3 185.7 268.3C215.3 253.3 248.6 247.8 281.4 252.3L281.4 342.2C266.4 337.5 250.3 337.6 235.4 342.6C220.5 347.6 207.5 357.2 198.4 369.9C189.3 382.6 184.4 398 184.5 413.8C184.6 429.6 189.7 444.8 199 457.5C208.3 470.2 221.4 479.6 236.4 484.4C251.4 489.2 267.5 489.2 282.4 484.3C297.3 479.4 310.4 469.9 319.6 457.2C328.8 444.5 333.8 429.1 333.8 413.4L333.8 64L421.8 64C421.7 71.4 422.4 78.9 423.7 86.2C426.8 102.5 433.1 118.1 442.4 131.9C451.7 145.7 463.7 157.5 477.6 166.5C497.5 179.6 520.8 186.6 544.6 186.6L544.6 274z"
        case .twitch:
            return "M455.4 167.5L416.8 167.5L416.8 277.2L455.4 277.2L455.4 167.5zM349.2 167L310.6 167L310.6 276.8L349.2 276.8L349.2 167zM185 64L88.5 155.4L88.5 484.6L204.3 484.6L204.3 576L300.8 484.6L378.1 484.6L551.9 320L551.9 64L185 64zM513.3 301.8L436.1 374.9L358.9 374.9L291.3 438.9L291.3 374.9L204.4 374.9L204.4 100.6L513.3 100.6L513.3 301.8z"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .youtube: return .white
        case .tiktok: return .white
        case .twitch: return .white
        }
    }

    var backgroundColor: Color {
        switch self {
        case .youtube: return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .tiktok: return Color.black
        case .twitch: return Color(red: 145/255, green: 70/255, blue: 255/255)
        }
    }

    var viewBox: CGSize { CGSize(width: 640, height: 640) }
}

struct SocialBrandIconView: View {
    let platform: String

    private var brand: SocialBrand? {
        switch platform.lowercased() {
        case "youtube": return .youtube
        case "tiktok": return .tiktok
        case "twitch": return .twitch
        default: return nil
        }
    }

    var body: some View {
        Group {
            if let brand {
                iconBody(for: brand)
            } else {
                Circle().fill(Color.gray)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func iconBody(for brand: SocialBrand) -> some View {
        switch brand {
        case .youtube:
            SVGPathShape(pathString: brand.svgPath, viewBox: brand.viewBox)
                .fill(Color.red)
        case .twitch:
            SVGPathShape(pathString: brand.svgPath, viewBox: brand.viewBox)
                .fill(brand.backgroundColor)
        case .tiktok:
            SVGPathShape(pathString: brand.svgPath, viewBox: brand.viewBox)
                .fill(.white)
        }
    }
}

private struct SVGPathShape: Shape {
    let pathString: String
    let viewBox: CGSize

    func path(in rect: CGRect) -> Path {
        let commands = SVGPathParser.parse(pathString)
        var path = Path()
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let xOffset = rect.minX + (rect.width - viewBox.width * scale) / 2
        let yOffset = rect.minY + (rect.height - viewBox.height * scale) / 2

        func point(_ raw: CGPoint) -> CGPoint {
            CGPoint(x: xOffset + raw.x * scale, y: yOffset + raw.y * scale)
        }

        for command in commands {
            switch command {
            case .move(let p):
                path.move(to: point(p))
            case .line(let p):
                path.addLine(to: point(p))
            case .curve(let c1, let c2, let p):
                path.addCurve(to: point(p), control1: point(c1), control2: point(c2))
            case .close:
                path.closeSubpath()
            }
        }

        return path
    }
}

private enum SVGPathCommand {
    case move(CGPoint)
    case line(CGPoint)
    case curve(CGPoint, CGPoint, CGPoint)
    case close
}

private enum SVGPathParser {
    static func parse(_ string: String) -> [SVGPathCommand] {
        var parser = Parser(text: string)
        var commands: [SVGPathCommand] = []

        while let token = parser.nextCommand() {
            switch token {
            case "M":
                if let first = parser.readPoint() {
                    commands.append(.move(first))
                    while let next = parser.readPointIfAvailable() {
                        commands.append(.line(next))
                    }
                }
            case "L":
                while let point = parser.readPointIfAvailable() {
                    commands.append(.line(point))
                }
            case "C":
                while let c1 = parser.readPointIfAvailable(),
                      let c2 = parser.readPointIfAvailable(),
                      let end = parser.readPointIfAvailable() {
                    commands.append(.curve(c1, c2, end))
                }
            case "z", "Z":
                commands.append(.close)
            default:
                break
            }
        }

        return commands
    }

    private struct Parser {
        let text: String
        var index: String.Index

        init(text: String) {
            self.text = text
            self.index = text.startIndex
        }

        mutating func nextCommand() -> String? {
            skipSeparators()
            if index >= text.endIndex { return nil }
            let char = text[index]
            if char.isLetter {
                text.formIndex(after: &index)
                return String(char)
            }
            return nil
        }

        mutating func readPoint() -> CGPoint? {
            guard let x = readNumber(), let y = readNumber() else { return nil }
            return CGPoint(x: x, y: y)
        }

        mutating func readPointIfAvailable() -> CGPoint? {
            skipSeparators()
            guard index < text.endIndex else { return nil }
            let char = text[index]
            guard !char.isLetter else { return nil }
            return readPoint()
        }

        mutating func readNumber() -> CGFloat? {
            skipSeparators()
            guard index < text.endIndex else { return nil }

            let start = index
            if text[index] == "-" || text[index] == "+" {
                text.formIndex(after: &index)
            }

            var sawDigit = false
            while index < text.endIndex, text[index].isNumber {
                sawDigit = true
                text.formIndex(after: &index)
            }

            if index < text.endIndex, text[index] == "." {
                text.formIndex(after: &index)
                while index < text.endIndex, text[index].isNumber {
                    sawDigit = true
                    text.formIndex(after: &index)
                }
            }

            guard sawDigit else { return nil }
            let value = String(text[start..<index])
            return CGFloat(Double(value) ?? 0)
        }

        mutating func skipSeparators() {
            while index < text.endIndex {
                let char = text[index]
                if char == " " || char == "," || char == "\n" || char == "\t" || char == "\r" {
                    text.formIndex(after: &index)
                } else {
                    break
                }
            }
        }
    }
}
