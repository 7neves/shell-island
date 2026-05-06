import XCTest
@testable import ShellIslandCore

final class AttentionDetectorTests: XCTestCase {

    // MARK: - 通用模式

    func testSudoPassword() {
        XCTAssertTrue(AttentionDetector.needsUserInput(
            text: "[sudo] password for seven:", kind: .brew))
    }

    func testPasswordColon() {
        XCTAssertTrue(AttentionDetector.needsUserInput(
            text: "Password: ", kind: .npmRun))
    }

    func testPassphrase() {
        XCTAssertTrue(AttentionDetector.needsUserInput(
            text: "Enter passphrase for key:", kind: .brew))
    }

    func testPressEnter() {
        XCTAssertTrue(AttentionDetector.needsUserInput(
            text: "Press Enter to continue", kind: .brew))
    }

    func testYN() {
        XCTAssertTrue(AttentionDetector.needsUserInput(
            text: "Are you sure? (y/n)", kind: .brew))
    }

    func testNormalOutputNoMatch() {
        XCTAssertFalse(AttentionDetector.needsUserInput(
            text: "Building project...\nCompiling...\nDone!", kind: .brew))
    }

    // MARK: - Claude Code 一层：强信号

    func testClaudeDoYouWantToProceed() {
        XCTAssertTrue(AttentionDetector.needsUserInput(
            text: "Claude Code\n\nDo you want to proceed?", kind: .claudeCode))
    }

    func testClaudeProceedAnyway() {
        XCTAssertTrue(AttentionDetector.needsUserInput(
            text: "Warning: this is risky\nProceed anyway?", kind: .claudeCode))
    }

    func testClaudeActionRequiresAllow() {
        XCTAssertTrue(AttentionDetector.needsUserInput(
            text: "This action requires approval. Allow?", kind: .claudeCode))
    }

    // MARK: - Claude Code 二层：TUI 按钮布局

    func testClaudeNumberedList() {
        // 实际 Claude Code "Do you want to proceed?" 对话框（截图确认的格式）
        let text = """
        Bash command

           ls /Users/seven/Documents/WorkSpace

        Check if node_modules exists

        Do you want to proceed?
        ❯ 1. Yes
          2. Yes, and don't ask again
          3. No

        Esc to cancel · Tab to amend
        """
        XCTAssertTrue(AttentionDetector.needsUserInput(text: text, kind: .claudeCode))
    }

    func testClaudeSideBySideButtons() {
        let text = """
        Claude Code

        This action requires filesystem access.

          Allow    Deny    Skip
        """
        XCTAssertTrue(AttentionDetector.needsUserInput(text: text, kind: .claudeCode))
    }

    func testSameDialogNotClaudeTask() {
        let text = """
        Claude Code

        This action requires filesystem access.

          Allow    Deny    Skip
        """
        // 非 claudeCode 任务：二层检测不会触发
        XCTAssertFalse(AttentionDetector.needsUserInput(text: text, kind: .brew))
    }

    func testYesNoOnSeparateLinesNotNumbered() {
        // 单独的 yes/no 行，没有编号前缀 → 不应命中
        let text = "Some output\n  yes\n  no\n"
        XCTAssertFalse(AttentionDetector.needsUserInput(text: text, kind: .claudeCode))
    }

    func testNormalClaudeOutputNoFalsePositive() {
        let text = """
        Claude Code v2.0.0
        Building project...
        Compiling TypeScript...
        Found 0 errors
        Watching for changes...
        """
        XCTAssertFalse(AttentionDetector.needsUserInput(text: text, kind: .claudeCode))
    }

    func testClaudeConversationWithYesNoNoFalsePositive() {
        // Claude 对话中自然出现的 yes/no/skip 行，但有对话上下文 → 不应误报
        let text = """
        I can help with that. Let me check the configuration.

        Yes, that approach should work fine.
        No need to worry about compatibility.
        Skip the optional step for now.

        Here's what I found:
        """
        XCTAssertFalse(AttentionDetector.needsUserInput(text: text, kind: .claudeCode))
    }

    func testClaudeNumberedOutputNoFalsePositive() {
        // Claude 正常输出中的编号列表（非权限对话框）
        let text = """
        Here's my analysis:

        1. First, let me analyze the codebase structure.
        2. Then check for potential issues in the model layer.
        3. Finally, propose the solution and implement it.

        Does that sound good?
        """
        XCTAssertFalse(AttentionDetector.needsUserInput(text: text, kind: .claudeCode))
    }

    func testNpmLogWithButtonWordsButNotClaudeTask() {
        let text = """
        Do you want to install dependencies? yes
        Continue with build? no
        Skip optional deps? skip
        """
        // 非 claudeCode 任务，二层不生效
        XCTAssertFalse(AttentionDetector.needsUserInput(text: text, kind: .npmRun))
    }

    // MARK: - 尾部限制

    func testLongOutputTailHasClaudeSignal() {
        var text = ""
        for i in 1...200 {
            text += "Line \(i): some normal output here\n"
        }
        text += "Claude Code\n\nDo you want to proceed?\n"
        XCTAssertTrue(AttentionDetector.needsUserInput(text: text, kind: .claudeCode))
    }

    func testSignalInFrontNotInTail() {
        var text = "Do you want to proceed?\n"
        for i in 1...200 {
            text += "Line \(i): some normal output here\n"
        }
        XCTAssertFalse(AttentionDetector.needsUserInput(text: text, kind: .claudeCode))
    }
}
