//
//  ViewController.swift
//  Mac Hardware Info
//
//  Created by User on 4/12/24.
//

import Cocoa
import QRCode

class ViewController: NSViewController {

    @IBOutlet weak var preventSharing: NSSwitch!
    
    private var identifiers: Data = try! getHwInfo().serializedData()
    @IBOutlet weak var qrCodeView: QRCodeDocumentView!
    
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
        qrState.design.shape.eye = QRCode.EyeShape.Circle()
        qrState.design.shape.pupil = QRCode.PupilShape.Circle()
        qrState.design.shape.onPixels = QRCode.PixelShape.Circle()
        qrState.design.backgroundColor(.clear)
        qrCodeView.document = qrState
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
        updateQr()
    }
    
    @IBAction
    func copyActivationCode(_ button: NSButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([getData().base64EncodedString() as NSString])
    }


}

