//
//  MarkdownDocument.swift
//  QLMarkdown Viewer
//

import Cocoa

/// Read-only markdown document. The file is read by the renderer, so nothing is loaded here.
class MarkdownDocument: NSDocument {
    override class var autosavesInPlace: Bool {
        return false
    }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool {
        return true
    }

    override func read(from url: URL, ofType typeName: String) throws {
    }

    override func makeWindowControllers() {
        addWindowController(ViewerWindowController(document: self))
    }

    /// File that contains the markdown source (resolves TextBundle packages).
    var markdownUrl: URL? {
        return fileURL.map { Settings.getMarkdownFile(from: $0) }
    }
}
