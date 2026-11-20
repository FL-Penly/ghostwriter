import CoreGraphics
import Foundation
import Testing
@testable import Capture

@Suite struct TerminalCellsTests {
    /// A Ghostty window measured on a Retina display: JetBrains Mono at 13 pt with 20% taller cells is 16 x 41
    /// pixels, 182 x 44 cells, with 2 points of padding on every side.
    private static let size = TerminalCells.WindowSize(rows: 44, columns: 182, xPixels: 2926, yPixels: 1818)
    private static let frame = CGRect(x: 100, y: 50, width: 2926.0 / 2 + 4, height: 1818.0 / 2 + 4)

    private static var grid: TerminalCells.Grid {
        TerminalCells.Grid(origin: CGPoint(x: 102, y: 52), cell: CGSize(width: 8, height: 20.5), rows: 44, columns: 182)
    }

    // MARK: Grid

    @Test func gridComesFromThePtyThatFitsTheView() throws {
        let grid = try #require(TerminalCells.grid(frame: Self.frame, sizes: [Self.size]))
        #expect(grid == Self.grid)
    }

    @Test func gridPicksThisViewsPtyAmongSplits() throws {
        let other = TerminalCells.WindowSize(rows: 44, columns: 90, xPixels: 1450, yPixels: 1818)
        let grid = try #require(TerminalCells.grid(frame: Self.frame, sizes: [other, Self.size]))
        #expect(grid.columns == 182)
    }

    @Test func balancedPaddingCentersTheGrid() throws {
        let balanced = TerminalCells.WindowSize(rows: 44, columns: 182, xPixels: 182 * 16, yPixels: 44 * 41)
        let grid = try #require(TerminalCells.grid(frame: Self.frame, sizes: [balanced]))
        #expect(grid.origin == CGPoint(x: 100 + (Self.frame.width - 1456) / 2, y: 50 + (Self.frame.height - 902) / 2))
        #expect(grid.cell == CGSize(width: 8, height: 20.5))
    }

    @Test func nonRetinaDisplayUsesWholePoints() throws {
        let size = TerminalCells.WindowSize(rows: 40, columns: 100, xPixels: 805, yPixels: 690)
        let frame = CGRect(x: 0, y: 0, width: 809, height: 694)
        let grid = try #require(TerminalCells.grid(frame: frame, sizes: [size]))
        #expect(grid.cell == CGSize(width: 8, height: 17))
        #expect(grid.origin == CGPoint(x: 2, y: 2))
    }

    @Test func noPtyFitsAViewItIsLargerThan() {
        let large = TerminalCells.WindowSize(rows: 80, columns: 300, xPixels: 9000, yPixels: 6000)
        #expect(TerminalCells.grid(frame: Self.frame, sizes: [large]) == nil)
        #expect(TerminalCells.grid(frame: Self.frame, sizes: []) == nil)
    }

    // MARK: Cells

    private static let rule = String(repeating: "─", count: 182)

    @Test func shortScreenStartsAtTheTopRow() {
        let screen = ["Last login: today", "~ % claude", "", Self.rule, "❯ hello", Self.rule, "  ? for shortcuts"]
            .joined(separator: "\n") as NSString
        let caret = screen.range(of: "❯ hello").location + 7
        let cell = TerminalCells.cell(at: caret, in: screen, isWholeScreen: true, grid: Self.grid)
        #expect(cell.row == 4)
        #expect(cell.column == 7)
    }

    @Test func longScreenEndsAtTheBottomRow() {
        let lines = (0..<60).map { "line \($0)" } + [Self.rule, "❯ hello", Self.rule, "  ? for shortcuts"]
        let screen = lines.joined(separator: "\n") as NSString
        let caret = screen.range(of: "❯ hello").location + 7
        let cell = TerminalCells.cell(at: caret, in: screen, isWholeScreen: true, grid: Self.grid)
        #expect(cell.row == 44 - 3)
    }

    @Test func tailOfAScreenEndsAtTheBottomRow() {
        let screen = ["output", Self.rule, "❯ hi", Self.rule, "  status"].joined(separator: "\n") as NSString
        let caret = screen.range(of: "❯ hi").location + 4
        let cell = TerminalCells.cell(at: caret, in: screen, isWholeScreen: false, grid: Self.grid)
        #expect(cell.row == 44 - 3)
    }

    @Test func wideCharactersTakeTwoColumns() {
        let screen = [Self.rule, "❯ 你好 world", Self.rule].joined(separator: "\n") as NSString
        let caret = screen.range(of: "world").location + 5
        let cell = TerminalCells.cell(at: caret, in: screen, isWholeScreen: true, grid: Self.grid)
        #expect(cell.column == 2 + 4 + 1 + 5)
    }

    @Test func softWrappedLinesAboveTakeTheirRows() {
        let long = String(repeating: "x", count: 182 + 10)
        let screen = [long, Self.rule, "❯ hi", Self.rule].joined(separator: "\n") as NSString
        let caret = screen.range(of: "❯ hi").location + 4
        let cell = TerminalCells.cell(at: caret, in: screen, isWholeScreen: true, grid: Self.grid)
        #expect(cell.row == 3)
    }

    @Test func caretRectSitsOnItsCell() {
        let rect = Self.grid.rect(row: 41, column: 7)
        #expect(rect == CGRect(x: 102 + 56, y: 52 + 41 * 20.5, width: 8, height: 20.5))
    }

    // MARK: UTF-16 columns

    @Test func columnMapsToTheCharacterStartingThere() {
        let row = "❯ 你好世界"
        #expect(TerminalCells.offset(ofColumn: 2, in: row) == 2)
        #expect(TerminalCells.offset(ofColumn: 4, in: row) == 3)
        #expect(TerminalCells.offset(ofColumn: 6, in: row) == 4)
        #expect(TerminalCells.offset(ofColumn: 10, in: row) == 6)
        #expect(TerminalCells.offset(ofColumn: 40, in: row) == 6)
    }

    @Test func asciiColumnsAreOffsets() {
        #expect(TerminalCells.offset(ofColumn: 5, in: "> hello world") == 5)
    }

    @Test func cellXCountsFromTheRowsFirstCell() {
        let first = CGRect(x: 40, y: 300, width: 7.5, height: 17)
        #expect(TerminalCells.x(ofColumn: 6, firstCell: first) == 40 + 6 * 7.5)
    }

    // MARK: Ghostty-shaped screens

    @Test func chineseDraftInAGhosttyPromptIsRead() throws {
        let screen = ["⏺ Done.", "", Self.rule, "❯ 帮我看看这个函数为什么", Self.rule, "  ? for shortcuts"].joined(separator: "\n")
        let prompt = try #require(TerminalAgentPrompt.find(in: screen, cursor: nil))
        #expect(prompt.textBefore == "帮我看看这个函数为什么")
        let cell = TerminalCells.cell(at: NSMaxRange(prompt.anchor), in: screen as NSString, isWholeScreen: true, grid: Self.grid)
        #expect(cell.row == 3)
        #expect(cell.column == 2 + 11 * 2)
    }
}
