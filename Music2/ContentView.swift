//
//  ContentView.swift
//  Music2
//
//  Created by grace keywork on 2/16/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var isPlaying = false
    @State private var showFilePicker = false
    @State private var uploadStatus = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                
                // CONNECTION STATUS DOT
                HStack {
                    Spacer()
                    Circle()
                        .fill(bleManager.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(bleManager.isConnected ? "Connected" : "Scanning...")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // TITLE
                Text("Music2")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                // PLAY/PAUSE BUTTON
                Button(action: {
                    isPlaying.toggle()
                    bleManager.sendCommand(isPlaying ? "PLAY" : "PAUSE")
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                        .frame(width: 120, height: 120)
                        .background(isPlaying ? Color.purple : Color.gray)
                        .clipShape(Circle())
                        .animation(.easeInOut, value: isPlaying)
                }
                .disabled(!bleManager.isConnected)
                
                // BUTTON PRESS COUNT
                if !bleManager.lastReceivedMessage.isEmpty {
                    let count = bleManager.lastReceivedMessage
                        .replacingOccurrences(of: "BUTTON_PRESSED:", with: "")
                    Text("Button presses: \(count)")
                        .foregroundColor(.green)
                        .font(.caption)
                        .padding()
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(10)
                }
                
                // UPLOAD WAV BUTTON
                Button("Upload WAV") {
                    showFilePicker = true
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(8)
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [UTType.audio],
                    allowsMultipleSelection: false
                ) { result in
                    if let url = try? result.get().first {
                        uploadWAV(url: url)
                    }
                }
                
                // UPLOAD STATUS
                if !uploadStatus.isEmpty {
                    Text(uploadStatus)
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    // UPLOAD FUNCTION
    func uploadWAV(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let audioData = try? Data(contentsOf: url) else {
            uploadStatus = "Could not read file"
            return
        }
        
        let serverURL = URL(string: "http://10.5.22.60:8000/uploadfile/")!
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        uploadStatus = "Uploading..."
        
        URLSession.shared.uploadTask(with: request, from: body) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    uploadStatus = "Error: \(error.localizedDescription)"
                } else if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    uploadStatus = "Uploaded!"
                } else {
                    uploadStatus = "Upload failed"
                }
            }
        }.resume()
    }
}

#Preview {
    ContentView()
        .environmentObject(BLEManager())
}

