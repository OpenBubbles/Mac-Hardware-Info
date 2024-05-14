//
//  ViewController.swift
//  Mac Hardware Info
//
//  Created by User on 4/12/24.
//

import Cocoa
import QRCode
import CryptoKit
import CommonCrypto

class ViewController: NSViewController {

    @IBOutlet weak var preventSharing: NSSwitch!
    
    private var identifiers: Data = try! getHwInfo().serializedData()
    @IBOutlet weak var qrCodeView: QRCodeDocumentView!
    @IBOutlet weak var onceDisclaimer: NSTextField!
    
    func getData() -> Data {
        var data = "OABS".data(using: .utf8)!
        data.append(preventSharing.state == .on ? 1 : 0)
        data.append(identifiers)
        return data
    }
    
    func updateQr() {
        let qrState = QRCode.Document()
        qrState.data = getData()
        qrState.errorCorrection = .medium
        qrState.design.backgroundColor(.clear)
        qrState.design.foregroundColor(NSColor.labelColor.cgColor)
        qrCodeView.document  = qrState
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        updateQr()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    @IBAction func toggleChanged(_ sender: Any) {
        onceDisclaimer.isHidden = preventSharing.state != .on
        updateQr()
    }
    
    func deriveKeyAndIV(passphrase: String, salt: Data) -> (key: Data, iv: Data) {
        let password = passphrase.data(using: .utf8)! // because we're only using ASCII it's semantically the same as dart
        
        var concatenatedHashes = Data()
        var currentHash = Data()
        var preHash = Data()
        
        while concatenatedHashes.count < 48 {
            if !currentHash.isEmpty {
                preHash = currentHash + password + salt
            } else {
                preHash = password + salt
            }
            
            currentHash = Data(Insecure.MD5.hash(data: preHash))
            concatenatedHashes += currentHash
        }
        
        let keyBytes = concatenatedHashes[0..<32]
        let ivBytes = concatenatedHashes[32..<48]
        return (key: keyBytes, iv: ivBytes)
    }
    
    func encryptAESDart(textData: Data, passphrase: String) -> String {
        var salt = Data(count: 8)
        let status = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!)
        }
        if status != errSecSuccess {
            fatalError()
        }
        let keyAndIv = deriveKeyAndIV(passphrase: passphrase, salt: salt)
        
        var encryptedBytes = "Salted__".data(using: .utf8)! + salt
        
        keyAndIv.key.withUnsafeBytes { key in
            keyAndIv.iv.withUnsafeBytes { iv in
                textData.withUnsafeBytes { text in
                    let dataOutSize: Int = textData.count + kCCBlockSizeAES128
                    let dataOut = UnsafeMutableRawPointer.allocate(byteCount: dataOutSize, alignment: 1)
                    
                    defer { dataOut.deallocate() }
                    var numBytesEncrypted: size_t = 0
                    
                    let cryptStatus = CCCrypt(
                        CCOperation(kCCEncrypt),
                        UInt32(kCCAlgorithmAES),
                        UInt32(kCCOptionPKCS7Padding),
                        key.baseAddress,
                        size_t(kCCKeySizeAES256),
                        iv.baseAddress,
                        text.baseAddress,
                        textData.count,
                        dataOut,
                        dataOutSize,
                        &numBytesEncrypted
                    )
                    guard cryptStatus == kCCSuccess else { fatalError() }
                    encryptedBytes += Data(bytes: dataOut, count: numBytesEncrypted)
                }
            }
        }
        
        return encryptedBytes.base64EncodedString()
        
    }
    
    @IBAction
    func copyActivationCode(_ button: NSButton) {
        NSPasteboard.general.clearContents()
        if preventSharing.state == .on {
            let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ123456789")
            var code = "MB"
            
            for i in 0..<4 {
                var bytes = [UInt8](repeating: 0, count: 4)
                let status = SecRandomCopyBytes(kSecRandomDefault, 4, &bytes)
                if status != errSecSuccess {
                    fatalError()
                }
                code += bytes.map { chars[Int($0) % chars.count] }
                if i != 3 {
                    code += "-"
                }
            }
            
            let serverCode = Data(SHA256.hash(data: code.data(using: .utf8)!)).map { String(format: "%02x", $0) }.joined()
            
            let encrypted = encryptAESDart(textData: getData(), passphrase: code)
            let url = URL(string: "https://openbubbles.app/code")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            struct CodeMessage: Encodable {
                let data: String
                let id: String
            }
            
            request.httpBody = try! JSONEncoder().encode(CodeMessage(data: encrypted, id: serverCode))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            button.title = "Generating code..."
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                let statusCode = (response as! HTTPURLResponse).statusCode
                if statusCode != 200 {
                    print("Error!")
                    DispatchQueue.main.async {
                        button.title = "Error!"
                    }
                } else {
                    print("Done!")
                    DispatchQueue.main.async {
                        button.title = "Copied!"
                    }
                    NSPasteboard.general.writeObjects([code as NSString])
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    button.title = "Copy Activation Code"
                }
            }
            task.resume()
            
        } else {
            let output = getData().base64EncodedString()
            NSPasteboard.general.writeObjects([output as NSString])
            button.title = "Copied!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                button.title = "Copy Activation Code"
            }
        }
    }


}

