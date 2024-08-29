//
//  FileBrowserViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-05-01.
//
//  ---------------------------------------------------------------------------
//
//  © 2024 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import Combine
import AudioToolbox
import Defaults
import ControlUI
import URLUtils

/// Column identifiers for outline view.
private extension NSUserInterfaceItemIdentifier {
    
    static let node = NSUserInterfaceItemIdentifier("node")
}


final class FileBrowserViewController: NSViewController, NSMenuItemValidation {
    
    let document: DirectoryDocument
    
    @ViewLoading private var outlineView: NSOutlineView
    @ViewLoading private var addButton: NSPopUpButton
    
    private var defaultObservers: Set<AnyCancellable> = []
    private var treeObservationTask: Task<Void, Never>?
    
    
    // MARK: Lifecycle
    
    init(document: DirectoryDocument) {
        
        self.document = document
        
        super.init(nibName: nil, bundle: nil)
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func loadView() {
        
        let outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.addTableColumn(NSTableColumn())
        
        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        
        let addButton = NSPopUpButton()
        addButton.pullsDown = true
        addButton.isBordered = false
        addButton.addItem(withTitle: "")
        addButton.item(at: 0)!.image = NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: "Add", table: "Document"))
        
        self.view = NSVisualEffectView()
        self.view.addSubview(scrollView)
        self.view.addSubview(addButton)
        
        self.outlineView = outlineView
        self.addButton = addButton
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            addButton.topAnchor.constraint(equalToSystemSpacingBelow: scrollView.bottomAnchor, multiplier: 1),
            addButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -6),
            addButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 6),
        ])
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.outlineView.dataSource = self
        self.outlineView.delegate = self
        
        let contextMenu = NSMenu()
        contextMenu.items = [
            NSMenuItem(title: String(localized: "Show in Finder", table: "Document", comment: "menu item label"),
                       action: #selector(showInFinder), keyEquivalent: ""),
            NSMenuItem(title: String(localized: "Open with External Editor", table: "Document", comment: "menu item label"),
                       action: #selector(openWithExternalEditor), keyEquivalent: ""),
            NSMenuItem(title: String(localized: "Open in New Window", table: "Document", comment: "menu item label"),
                       action: #selector(openInNewWindow), keyEquivalent: ""),
            .separator(),
            
            NSMenuItem(title: String(localized: "New File", table: "Document", comment: "menu item label"),
                       action: #selector(addFile), keyEquivalent: ""),
            NSMenuItem(title: String(localized: "New Folder", table: "Document", comment: "menu item label"),
                       action: #selector(addFolder), keyEquivalent: ""),
            NSMenuItem(title: String(localized: "Move to Trash", table: "Document", comment: "menu item label"),
                       action: #selector(moveToTrash), keyEquivalent: ""),
            .separator(),
            
            NSMenuItem(title: String(localized: "Show Hidden Files", table: "Document", comment: "menu item label"),
                       action: #selector(toggleHiddenFileVisibility), keyEquivalent: ""),
        ]
        self.outlineView.menu = contextMenu
        
        self.addButton.menu!.items += [
            NSMenuItem(title: String(localized: "New File", table: "Document", comment: "menu item label"),
                       action: #selector(addFile), keyEquivalent: ""),
            NSMenuItem(title: String(localized: "New Folder", table: "Document", comment: "menu item label"),
                       action: #selector(addFolder), keyEquivalent: ""),
        ]
    }
    
    
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        self.outlineView.reloadData()
        
        self.treeObservationTask = Task {
            for await _ in NotificationCenter.default.notifications(named: DirectoryDocument.didUpdateFileNodeNotification, object: self.document).map(\.name) {
                let selectedNode = self.outlineView.item(atRow: self.outlineView.selectedRow)
                self.outlineView.reloadData()
                let index = self.outlineView.row(forItem: selectedNode)
                if index >= 0 {
                    self.outlineView.selectRowIndexes([index], byExtendingSelection: false)
                }
            }
        }
        
        self.defaultObservers = [
            UserDefaults.standard.publisher(for: .fileBrowserShowsHiddenFiles)
                .sink { [unowned self] _ in self.outlineView.reloadData() },
        ]
    }
    
    
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        self.treeObservationTask?.cancel()
        self.treeObservationTask = nil
        
        self.defaultObservers.removeAll()
    }
    
    
    // MARK: Actions
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        switch menuItem.action {
            case #selector(showInFinder):
                menuItem.isHidden = self.clickedNode == nil
                
            case #selector(openWithExternalEditor):
                menuItem.isHidden = self.clickedNode?.isDirectory != false
                
            case #selector(openInNewWindow):
                menuItem.isHidden = self.clickedNode == nil
                
            case #selector(addFile):
                return self.targetFolderNode(for: menuItem)?.isWritable != false
                
            case #selector(addFolder):
                return self.targetFolderNode(for: menuItem)?.isWritable != false
                
            case #selector(moveToTrash):
                menuItem.isHidden = self.clickedNode == nil
                return self.clickedNode?.isWritable == true
                
            case #selector(toggleHiddenFileVisibility):
                menuItem.state = self.showsHiddenFiles ? .on : .off
                
            case nil:
                return false
                
            default:
                break
        }
        
        return true
    }
    
    
    @IBAction func showInFinder(_ sender: Any?) {
        
        guard let node = self.clickedNode else { return }
        
        NSWorkspace.shared.activateFileViewerSelecting([node.fileURL])
    }
    
    
    @IBAction func openWithExternalEditor(_ sender: Any?) {
        
        guard let node = self.clickedNode else { return }
        
        NSWorkspace.shared.open(node.fileURL)
    }
    
    
    @IBAction func openInNewWindow(_ sender: Any?) {
        
        guard let node = self.clickedNode else { return }
        
        self.document.openInWindow(fileURL: node.fileURL)
    }
    
    
    @IBAction func addFile(_ sender: NSMenuItem) {
        
        guard let folderNode = self.targetFolderNode(for: sender) else { return }
        
        let node: FileNode
        do {
            node = try self.document.addFile(at: folderNode)
        } catch {
            return self.presentErrorAsSheet(error)
        }
        
        // update UI
        if let index = folderNode.children?.firstIndex(of: node) {
            let parent = (folderNode == self.document.fileNode) ? nil : folderNode
            self.outlineView.insertItems(at: [index], inParent: parent, withAnimation: .effectGap)
        }
        self.select(node: node, edit: true)
    }
    
    
    @IBAction func addFolder(_ sender: NSMenuItem) {
        
        guard let folderNode = self.targetFolderNode(for: sender) else { return }
        
        let node: FileNode
        do {
            node = try self.document.addFolder(at: folderNode)
        } catch {
            return self.presentErrorAsSheet(error)
        }
        
        // update UI
        if let index = folderNode.children?.firstIndex(of: node) {
            let parent = (folderNode == self.document.fileNode) ? nil : folderNode
            self.outlineView.insertItems(at: [index], inParent: parent, withAnimation: .effectGap)
        }
        self.select(node: node, edit: true)
    }
    
    
    @IBAction func moveToTrash(_ sender: Any?) {
        
        guard let node = self.clickedNode else { return }
        
        do {
            try self.document.trashItem(node)
        } catch {
            return self.presentErrorAsSheet(error)
        }
        
        let parent = self.outlineView.parent(forItem: node)
        let index = self.outlineView.childIndex(forItem: node)
        
        guard index >= 0 else { return assertionFailure() }
        
        self.outlineView.removeItems(at: [index], inParent: parent, withAnimation: .effectGap)
        AudioServicesPlaySystemSound(.moveToTrash)
    }
    
    
    @IBAction func toggleHiddenFileVisibility(_ sender: Any?) {
        
        self.showsHiddenFiles.toggle()
    }
    
    
    // MARK: Private Methods
    
    /// Whether displaying hidden files.
    private var showsHiddenFiles: Bool {
        
        get { UserDefaults.standard[.fileBrowserShowsHiddenFiles] }
        set { UserDefaults.standard[.fileBrowserShowsHiddenFiles] = newValue }
    }
    
    
    /// The outline item currently clicked.
    private var clickedNode: FileNode? {
        
        self.outlineView.item(atRow: self.outlineView.clickedRow) as? FileNode
    }
    
    
    /// Returns the target file node for the menu action.
    ///
    /// - Parameter menuItem: The sender of the action.
    /// - Returns: A file node.
    private func targetNode(for menuItem: NSMenuItem) -> FileNode? {
        
        let isContextMenu = (menuItem.menu == self.outlineView.menu)
        let row = isContextMenu ? self.outlineView.clickedRow : self.outlineView.selectedRow
        
        return self.outlineView.item(atRow: row) as? FileNode ?? self.document.fileNode
    }
    
    
    /// Returns the folder node to perform action of the menu item.
    ///
    /// - Parameter menuItem: The sender of the action.
    /// - Returns: A file node.
    private func targetFolderNode(for sender: NSMenuItem) -> FileNode? {
        
        guard let targetNode = self.targetNode(for: sender) else { return nil }
        
        return targetNode.isDirectory ? targetNode : targetNode.parent
    }
    
    
    /// Selects the specified item in the outline view.
    ///
    /// - Parameters:
    ///   - node: The note item to select.
    ///   - edit: If `true`, the text field will be in the editing mode.
    private func select(node: FileNode, edit: Bool = false) {
        
        if let parent = node.parent {
            self.outlineView.expandItem(parent)
        }
        
        let row = self.outlineView.row(forItem: node)
        
        guard row >= 0 else { return assertionFailure() }
        
        self.outlineView.selectRowIndexes([row], byExtendingSelection: false)
        
        if edit {
            self.outlineView.editColumn(0, row: row, with: nil, select: false)
        }
    }
}


extension FileBrowserViewController: NSOutlineViewDataSource {
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        
        self.children(of: item)?.count ?? 0
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        
        (item as! FileNode).isDirectory
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        
        self.children(of: item)![index]
    }
    
    
    /// Returns the casted children of the given item provided by an API of `NSOutlineViewDataSource`.
    ///
    /// - Parameter item: An item in the data source, or `nil` for the root.
    /// - Returns: An array of file nodes, or `nil` if no data source is provided yet.
    private func children(of item: Any?) -> [FileNode]? {
        
        (item as? FileNode ?? self.document.fileNode)?.children?
            .filter { self.showsHiddenFiles || !$0.isHidden }
    }
}


extension FileBrowserViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        
        let node = item as! FileNode
        let cellView = outlineView.makeView(withIdentifier: .node, owner: self) as? NSTableCellView ?? self.createCellView()
        
        cellView.imageView!.image = node.kind.image
        cellView.imageView!.alphaValue = node.isHidden ? 0.5 : 1
        
        cellView.textField!.stringValue = node.name
        cellView.textField!.textColor = node.isHidden ? .disabledControlTextColor : .labelColor
        
        return cellView
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        
        let outlineView = notification.object as! NSOutlineView
        let node = outlineView.item(atRow: outlineView.selectedRow) as? FileNode
        
        guard let node, !node.isDirectory else { return }
        
        Task {
            await self.document.openDocument(at: node.fileURL)
        }
    }
    
    
    /// Create a new cell view template for the outline view.
    ///
    /// - Returns: A table cell view.
    private func createCellView() -> NSTableCellView {
        
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.alignment = .center
        
        let textField = FilenameTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.drawsBackground = false
        textField.isBordered = false
        textField.lineBreakMode = .byTruncatingMiddle
        textField.isEditable = true
        textField.delegate = self
        
        let cellView = NSTableCellView()
        cellView.identifier = .node
        cellView.addSubview(textField)
        cellView.addSubview(imageView)
        cellView.textField = textField
        cellView.imageView = imageView
        
        NSLayoutConstraint.activate([
            imageView.firstBaselineAnchor.constraint(equalTo: textField.firstBaselineAnchor),
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
            imageView.widthAnchor.constraint(equalToConstant: 17),  // the value used in a sample code by Apple
            textField.leadingAnchor.constraint(equalToSystemSpacingAfter: imageView.trailingAnchor, multiplier: 1),
            textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -2),
        ])
        
        return cellView
    }
}


extension FileBrowserViewController: NSTextFieldDelegate {
    
    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
        
        // start editing only when the row has already been selected
        guard self.outlineView.row(for: control) == self.outlineView.selectedRow else { return false }
        
        let row = self.outlineView.row(for: control)
        
        guard let node = self.outlineView.item(atRow: row) as? FileNode else { return false }
        
        return node.isWritable
    }
    
    
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        
        let row = self.outlineView.row(for: control)
        
        guard let node = self.outlineView.item(atRow: row) as? FileNode else { return false }
        
        if fieldEditor.string == node.name { return true }  // not changed
        
        do {
            try self.document.renameItem(at: node, with: fieldEditor.string)
        } catch {
            self.presentErrorAsSheet(error)
            return false
        }
        
        return true
    }
}


private extension FileNode.Kind {
    
    /// The symbol image in `NSImage`.
    var image: NSImage {
        
        NSImage(systemSymbolName: self.symbolName, accessibilityDescription: self.label)!
    }
}