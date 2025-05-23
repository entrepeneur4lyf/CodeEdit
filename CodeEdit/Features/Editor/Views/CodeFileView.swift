//
//  CodeFileView.swift
//  CodeEditModules/CodeFile
//
//  Created by Marco Carnevali on 17/03/22.
//

import Foundation
import SwiftUI
import CodeEditSourceEditor
import CodeEditTextView
import CodeEditLanguages
import Combine

/// CodeFileView is just a wrapper of the `CodeEditor` dependency
struct CodeFileView: View {
    @ObservedObject private var codeFile: CodeFileDocument

    /// The current cursor positions in the view
    @State private var cursorPositions: [CursorPosition] = []

    /// Any coordinators passed to the view.
    private var textViewCoordinators: [TextViewCoordinator]

    @AppSettings(\.textEditing.defaultTabWidth)
    var defaultTabWidth
    @AppSettings(\.textEditing.indentOption)
    var indentOption
    @AppSettings(\.textEditing.lineHeightMultiple)
    var lineHeightMultiple
    @AppSettings(\.textEditing.wrapLinesToEditorWidth)
    var wrapLinesToEditorWidth
    @AppSettings(\.textEditing.overscroll)
    var overscroll
    @AppSettings(\.textEditing.font)
    var settingsFont
    @AppSettings(\.theme.useThemeBackground)
    var useThemeBackground
    @AppSettings(\.theme.matchAppearance)
    var matchAppearance
    @AppSettings(\.textEditing.letterSpacing)
    var letterSpacing
    @AppSettings(\.textEditing.bracketHighlight)
    var bracketHighlight
    @AppSettings(\.textEditing.useSystemCursor)
    var useSystemCursor

    @Environment(\.colorScheme)
    private var colorScheme

    @ObservedObject private var themeModel: ThemeModel = .shared

    private var cancellables = Set<AnyCancellable>()

    private let isEditable: Bool

    private let undoManager = CEUndoManager()

    init(codeFile: CodeFileDocument, textViewCoordinators: [TextViewCoordinator] = [], isEditable: Bool = true) {
        self._codeFile = .init(wrappedValue: codeFile)
        self.textViewCoordinators = textViewCoordinators
            + [codeFile.contentCoordinator]
            + [codeFile.lspCoordinator].compactMap({ $0 })
        self.isEditable = isEditable

        if let openOptions = codeFile.openOptions {
            codeFile.openOptions = nil
            self.cursorPositions = openOptions.cursorPositions
        }

        codeFile
            .contentCoordinator
            .textUpdatePublisher
            .sink { _ in
                codeFile.updateChangeCount(.changeDone)
            }
            .store(in: &cancellables)

        codeFile
            .contentCoordinator
            .textUpdatePublisher
            .debounce(for: 1.0, scheduler: DispatchQueue.main)
            .sink { _ in
                // updateChangeCount is automatically managed by autosave(), so no manual call is necessary
                codeFile.autosave(withImplicitCancellability: false) { error in
                    if let error {
                        CodeFileDocument.logger.error("Failed to autosave document, error: \(error)")
                    }
                }
            }
            .store(in: &cancellables)

        codeFile.undoManager = self.undoManager.manager
    }

    private var currentTheme: Theme {
        themeModel.selectedTheme ?? themeModel.themes.first!
    }

    @State private var font: NSFont = Settings[\.textEditing].font.current

    @State private var bracketPairHighlight: BracketPairHighlight? = {
        let theme = ThemeModel.shared.selectedTheme ?? ThemeModel.shared.themes.first!
        let color = Settings[\.textEditing].bracketHighlight.useCustomColor
        ? Settings[\.textEditing].bracketHighlight.color.nsColor
        : theme.editor.text.nsColor.withAlphaComponent(0.8)
        switch Settings[\.textEditing].bracketHighlight.highlightType {
        case .disabled:
            return nil
        case .flash:
            return .flash
        case .bordered:
            return .bordered(color: color)
        case .underline:
            return .underline(color: color)
        }
    }()

    @Environment(\.edgeInsets)
    private var edgeInsets

    var body: some View {
        CodeEditSourceEditor(
            codeFile.content ?? NSTextStorage(),
            language: codeFile.getLanguage(),
            theme: currentTheme.editor.editorTheme,
            font: font,
            tabWidth: codeFile.defaultTabWidth ?? defaultTabWidth,
            indentOption: (codeFile.indentOption ?? indentOption).textViewOption(),
            lineHeight: lineHeightMultiple,
            wrapLines: codeFile.wrapLines ?? wrapLinesToEditorWidth,
            editorOverscroll: overscroll.overscrollPercentage,
            cursorPositions: $cursorPositions,
            useThemeBackground: useThemeBackground,
            contentInsets: edgeInsets.nsEdgeInsets,
            isEditable: isEditable,
            letterSpacing: letterSpacing,
            bracketPairHighlight: bracketPairHighlight,
            useSystemCursor: useSystemCursor,
            undoManager: undoManager,
            coordinators: textViewCoordinators
        )
        .id(codeFile.fileURL)
        .background {
            if colorScheme == .dark {
                EffectView(.underPageBackground)
            } else {
                EffectView(.contentBackground)
            }
        }
        .colorScheme(currentTheme.appearance == .dark ? .dark : .light)
        // minHeight zero fixes a bug where the app would freeze if the contents of the file are empty.
        .frame(minHeight: .zero, maxHeight: .infinity)
        .onChange(of: settingsFont) { newFontSetting in
            font = newFontSetting.current
        }
        .onChange(of: bracketHighlight) { _ in
            bracketPairHighlight = getBracketPairHighlight()
        }
    }

    private func getBracketPairHighlight() -> BracketPairHighlight? {
        let color = if Settings[\.textEditing].bracketHighlight.useCustomColor {
            Settings[\.textEditing].bracketHighlight.color.nsColor
        } else {
            currentTheme.editor.text.nsColor.withAlphaComponent(0.8)
        }

        switch Settings[\.textEditing].bracketHighlight.highlightType {
        case .disabled:
            return nil
        case .flash:
            return .flash
        case .bordered:
            return .bordered(color: color)
        case .underline:
            return .underline(color: color)
        }
    }
}

// This extension is kept here because it should not be used elsewhere in the app and may cause confusion
// due to the similar type name from the CETV module.
private extension SettingsData.TextEditingSettings.IndentOption {
    func textViewOption() -> IndentOption {
        switch self.indentType {
        case .spaces:
            return IndentOption.spaces(count: spaceCount)
        case .tab:
            return IndentOption.tab
        }
    }
}
