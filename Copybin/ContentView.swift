import SwiftUI
import AppKit
import Foundation

// MARK: - Modelo de dados para itens do clipboard
struct ClipboardItem: Identifiable, Codable {
    var id = UUID()
    let content: String
    let imageData: Data?
    let timestamp: Date
    let type: ClipboardType
    
    enum ClipboardType: String, Codable, CaseIterable {
        case text = "text"
        case url = "url"
        case email = "email"
        case image = "image"
        
        var icon: String {
            switch self {
            case .text: return "doc.text"
            case .url: return "link"
            case .email: return "envelope"
            case .image: return "photo"
            }
        }
    }
    
    init(content: String) {
        self.content = content
        self.imageData = nil
        self.timestamp = Date()
        
        // Detecta o tipo baseado no conteúdo
        if content.contains("@") && content.contains(".") && !content.contains(" ") {
            self.type = .email
        } else if content.hasPrefix("http") || content.hasPrefix("www.") {
            self.type = .url
        } else {
            self.type = .text
        }
    }
    
    init(imageData: Data) {
        self.content = "Imagem copiada"
        self.imageData = imageData
        self.timestamp = Date()
        self.type = .image
    }
}

// MARK: - Gerenciador do Clipboard
class ClipboardManager: ObservableObject {
    @Published var items: [ClipboardItem] = []
    private var lastClipboardContent: Any?
    private var timer: Timer?
    private let maxItems = 100
    
    init() {
        loadItems()
        startMonitoring()
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkClipboard()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Verifica se há uma imagem
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            if !isDataEqual(imageData, lastClipboardContent as? Data) {
                addImageItem(imageData: imageData)
                return
            }
        }
        
        // Verifica texto
        guard let content = pasteboard.string(forType: .string),
              content != lastClipboardContent as? String,
              !content.isEmpty else { return }
        
        lastClipboardContent = content
        addItem(content: content)
    }
    
    private func isDataEqual(_ data1: Data, _ data2: Data?) -> Bool {
        guard let data2 = data2 else { return false }
        return data1 == data2
    }
    
    func addImageItem(imageData: Data) {
        let newItem = ClipboardItem(imageData: imageData)
        
        // Remove duplicatas baseadas no timestamp (imagens são difíceis de comparar)
        if let lastItem = items.first,
           lastItem.type == .image,
           Date().timeIntervalSince(lastItem.timestamp) < 1.0 {
            return // Evita duplicatas de imagem muito próximas
        }
        
        items.insert(newItem, at: 0)
        
        // Limita o número de itens
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        lastClipboardContent = imageData
        saveItems()
    }
    
    func addItem(content: String) {
        let newItem = ClipboardItem(content: content)
        
        // Remove duplicatas
        items.removeAll { $0.content == content }
        
        // Adiciona no início
        items.insert(newItem, at: 0)
        
        // Limita o número de itens
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        saveItems()
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if item.type == .image, let imageData = item.imageData {
            pasteboard.setData(imageData, forType: .tiff)
            lastClipboardContent = imageData
        } else {
            pasteboard.setString(item.content, forType: .string)
            lastClipboardContent = item.content
        }
    }
    
    func copyAndPaste(_ item: ClipboardItem, shouldMinimize: Bool = true) {
        // Primeiro coloca no clipboard
        copyToClipboard(item)
        
        // Minimiza a janela se solicitado
        if shouldMinimize {
            DispatchQueue.main.async {
                if let window = NSApplication.shared.windows.first {
                    window.miniaturize(nil)
                }
            }
        }
        
        // Aguarda um momento para garantir que o clipboard foi atualizado e a janela minimizada
        DispatchQueue.main.asyncAfter(deadline: .now() + (shouldMinimize ? 0.3 : 0.1)) {
            // Simula Cmd+V
            self.simulatePaste()
        }
    }
    
    private func simulatePaste() {
        // Cria evento de Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Evento de pressionar Cmd
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) // Cmd key
        cmdDown?.flags = .maskCommand
        
        // Evento de pressionar V
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        vDown?.flags = .maskCommand
        
        // Evento de soltar V
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) // V key
        vUp?.flags = .maskCommand
        
        // Evento de soltar Cmd
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) // Cmd key
        
        // Envia os eventos
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
    
    func deleteItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        saveItems()
    }
    
    func clearAll() {
        items.removeAll()
        saveItems()
    }
    
    private func saveItems() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: "clipboardItems")
        }
    }
    
    private func loadItems() {
        if let data = UserDefaults.standard.data(forKey: "clipboardItems"),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            self.items = decoded
        }
    }
}

// MARK: - View do item individual
struct ClipboardItemView: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onCopyAndPaste: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Ícone do tipo ou preview da imagem
            if item.type == .image, let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            } else {
                Image(systemName: item.type.icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Conteúdo (limitado)
                if item.type == .image, let imageData = item.imageData {
                    HStack {
                        Text("Imagem")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(item.content)
                        .lineLimit(2)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                }
                
                // Timestamp
                Text(formatDate(item.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Botões de ação
            HStack(spacing: 8) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Copiar para clipboard")
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Excluir item")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture {
            // Um clique já cola automaticamente
            onCopyAndPaste()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        _ = Date()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            return "Ontem"
        } else {
            formatter.dateFormat = "dd/MM"
        }
        
        return formatter.string(from: date)
    }
}

// MARK: - View principal
struct ContentView: View {
    @StateObject private var clipboardManager = ClipboardManager()
    @State private var searchText = ""
    @State private var selectedType: ClipboardItem.ClipboardType? = nil
    @State private var autoMinimize = true
    
    var filteredItems: [ClipboardItem] {
        var items = clipboardManager.items
        
        // Filtro por tipo
        if let selectedType = selectedType {
            items = items.filter { $0.type == selectedType }
        }
        
        // Filtro por busca
        if !searchText.isEmpty {
            items = items.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
        
        return items
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Barra superior
            VStack(spacing: 12) {
                // Título e contador
                HStack {
                    Text("Histórico do Clipboard")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Text("\(filteredItems.count) itens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Botão limpar tudo
                    Button("Limpar Tudo") {
                        clipboardManager.clearAll()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.red)
                    
                    // Toggle para auto-minimizar
                    Toggle("Auto minimizar", isOn: $autoMinimize)
                        .toggleStyle(SwitchToggleStyle())
                        .scaleEffect(0.8)
                        .help("Minimiza a janela automaticamente ao colar")
                }
                
                // Barra de busca
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Buscar no histórico...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Filtros por tipo
                HStack {
                    Button(action: { selectedType = nil }) {
                        Text("Todos")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(selectedType == nil ? Color.blue : Color.clear)
                            .foregroundColor(selectedType == nil ? .white : .primary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    ForEach(ClipboardItem.ClipboardType.allCases, id: \.self) { type in
                        Button(action: { selectedType = type }) {
                            HStack(spacing: 4) {
                                Image(systemName: type.icon)
                                Text(type.rawValue.capitalized)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(selectedType == type ? Color.blue : Color.clear)
                            .foregroundColor(selectedType == type ? .white : .primary)
                            .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer()
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Lista de itens
            if filteredItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "Nenhum item no histórico" : "Nenhum item encontrado")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if searchText.isEmpty {
                        Text("Copie algo com Cmd+C para começar!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            ClipboardItemView(
                                item: item,
                                onCopy: {
                                    clipboardManager.copyToClipboard(item)
                                },
                                onCopyAndPaste: {
                                    clipboardManager.copyAndPaste(item, shouldMinimize: autoMinimize)
                                },
                                onDelete: {
                                    clipboardManager.deleteItem(item)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}

// MARK: - Configuração da janela (adicionar no AppDelegate se necessário)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configurações adicionais se necessário
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
