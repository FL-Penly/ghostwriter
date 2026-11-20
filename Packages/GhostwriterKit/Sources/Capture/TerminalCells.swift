import CoreGraphics
import Darwin
import Foundation

/// Cell geometry for terminals whose Accessibility does not place every character on screen.
enum TerminalCells {
    // MARK: Terminals that count a column as a UTF-16 unit

    /// The UTF-16 offset in `row` of the cell `column` cells in: wide characters (CJK, emoji) take two cells.
    /// Past the row's last character it is the row's end.
    static func offset(ofColumn column: Int, in row: String) -> Int {
        var cells = 0
        var offset = 0
        for character in row {
            if cells >= column { return offset }
            cells += TerminalAgentPrompt.columns(String(character))
            offset += character.utf16.count
        }
        return offset
    }

    /// The x of the cell `column` of a row, from the first cell's bounds. A terminal that counts columns as
    /// UTF-16 units still places a row's first character right; later ones shift left by one cell per wide
    /// character before them.
    static func x(ofColumn column: Int, firstCell: CGRect) -> CGFloat {
        firstCell.minX + CGFloat(column) * firstCell.width
    }

    // MARK: Terminals without character bounds

    struct WindowSize: Equatable, Sendable {
        var rows: Int
        var columns: Int
        var xPixels: Int
        var yPixels: Int
    }

    /// A terminal view's cell grid in Accessibility screen coordinates (top-left origin).
    struct Grid: Equatable, Sendable {
        /// The top-left corner of the first cell.
        var origin: CGPoint
        var cell: CGSize
        var rows: Int
        var columns: Int

        func rect(row: Int, column: Int, cells: Int = 1) -> CGRect {
            CGRect(
                x: origin.x + CGFloat(column) * cell.width, y: origin.y + CGFloat(row) * cell.height,
                width: CGFloat(cells) * cell.width, height: cell.height
            )
        }
    }

    /// The grid of the terminal view at `frame`, from the window sizes of the terminal app's ptys. A pty's pixel
    /// size is the view less its padding at the display's scale, so the pty whose size fits the view with the
    /// least padding is this view's. Cell sizes are whole pixels and the space a cell does not fill is
    /// narrower than one pixel per column, so rounding down gives the exact cell.
    static func grid(frame: CGRect, sizes: [WindowSize]) -> Grid? {
        var best: (grid: Grid, padding: CGFloat)?
        for size in sizes where size.rows > 0 && size.columns > 0 && size.xPixels >= size.columns && size.yPixels >= size.rows {
            for scale: CGFloat in [2, 1, 3] {
                let paddingX = (frame.width - CGFloat(size.xPixels) / scale) / 2
                let paddingY = (frame.height - CGFloat(size.yPixels) / scale) / 2
                guard paddingX >= -0.5, paddingY >= -0.5, paddingX < Self.maxPadding, paddingY < Self.maxPadding else { continue }
                let padding = paddingX + paddingY
                if let best, best.padding <= padding { continue }
                let cell = CGSize(
                    width: CGFloat(size.xPixels / size.columns) / scale, height: CGFloat(size.yPixels / size.rows) / scale
                )
                let origin = CGPoint(x: frame.minX + max(0, paddingX), y: frame.minY + max(0, paddingY))
                best = (grid: Grid(origin: origin, cell: cell, rows: size.rows, columns: size.columns), padding: padding)
            }
        }
        return best?.grid
    }

    private static let maxPadding: CGFloat = 60

    /// The cell holding UTF-16 `offset` of `screen`, a terminal's text from its first line with text (when
    /// `isWholeScreen`) or a tail of it, and ending at its last line with text. Lines longer than the grid are
    /// soft-wrapped onto further rows. A screen that fits the grid starts at its top row; a longer one is
    /// scrolled to its end, which sits on the bottom row.
    static func cell(at offset: Int, in screen: NSString, isWholeScreen: Bool, grid: Grid) -> (row: Int, column: Int) {
        let lines = (screen as String).split(separator: "\n", omittingEmptySubsequences: false)
        let lineIndex = screen.substring(to: min(offset, screen.length)).reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        let lineStart = screen.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: min(offset, screen.length)))
        let start = lineStart.location == NSNotFound ? 0 : lineStart.location + 1
        let columnInLine = TerminalAgentPrompt.columns(screen.substring(with: NSRange(location: start, length: offset - start)))
        func rows(_ line: Substring) -> Int {
            max(1, (TerminalAgentPrompt.columns(String(line)) + grid.columns - 1) / grid.columns)
        }
        let wrapped = columnInLine / grid.columns
        let column = columnInLine % grid.columns
        let above = lines[..<lineIndex].reduce(0) { $0 + rows($1) }
        let total = lines.reduce(0) { $0 + rows($1) }
        let row = isWholeScreen && total <= grid.rows ? above + wrapped : grid.rows - (total - above) + wrapped
        return (min(max(row, 0), grid.rows - 1), column)
    }

    // MARK: Pty window sizes

    /// The window sizes of the terminals an app runs: the ptys of its child processes and of their children
    /// (a terminal starts `login`, which runs as root and cannot be inspected, and `login` starts the shell).
    static func windowSizes(of app: pid_t) -> [WindowSize] {
        var devices: Set<UInt32> = []
        var level = [app]
        for _ in 0..<3 {
            let children = level.flatMap(Self.children)
            for child in children {
                var info = proc_bsdinfo()
                let size = Int32(MemoryLayout<proc_bsdinfo>.size)
                guard proc_pidinfo(child, PROC_PIDTBSDINFO, 0, &info, size) == size, info.e_tdev != UInt32.max,
                      info.e_tdev != 0 else { continue }
                devices.insert(info.e_tdev)
            }
            level = children
        }
        return devices.compactMap { windowSize(device: $0) }
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 256)
        let count = pids.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, Int32($0.count)) }
        return count > 0 ? pids.prefix(min(Int(count), pids.count)).filter { $0 > 0 } : []
    }

    private static func windowSize(device: UInt32) -> WindowSize? {
        guard let name = devname(dev_t(bitPattern: device), mode_t(S_IFCHR)) else { return nil }
        let descriptor = open("/dev/" + String(cString: name), O_RDONLY | O_NONBLOCK | O_NOCTTY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var size = winsize()
        guard ioctl(descriptor, TIOCGWINSZ, &size) == 0 else { return nil }
        return WindowSize(
            rows: Int(size.ws_row), columns: Int(size.ws_col), xPixels: Int(size.ws_xpixel), yPixels: Int(size.ws_ypixel)
        )
    }
}
