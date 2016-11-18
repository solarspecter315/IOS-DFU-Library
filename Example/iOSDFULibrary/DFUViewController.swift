/*
 * Copyright (c) 2016, Nordic Semiconductor
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this
 * software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 * ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
 * USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import UIKit
import CoreBluetooth
import iOSDFULibrary

class DFUViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate, DFUServiceDelegate, DFUProgressDelegate, LoggerDelegate, UIAlertViewDelegate {

    //MARK: - Class Properties
    fileprivate var dfuPeripheral    : CBPeripheral?
    fileprivate var dfuController    : DFUServiceController?
    fileprivate var centralManager   : CBCentralManager?
    fileprivate var selectedFirmware : DFUFirmware?
    fileprivate var selectedFileURL  : URL?
    fileprivate var secureDFU        : Bool?
    
    //MARK: - View Outlets
    @IBOutlet weak var dfuActivityIndicator  : UIActivityIndicatorView!
    @IBOutlet weak var dfuStatusLabel        : UILabel!
    @IBOutlet weak var peripheralNameLabel   : UILabel!
    @IBOutlet weak var dfuUploadProgressView : UIProgressView!
    @IBOutlet weak var dfuUploadStatus       : UILabel!
    @IBOutlet weak var stopProcessButton     : UIButton!
    
    //MARK: - View Actions
    @IBAction func stopProcessButtonTapped(_ sender: AnyObject) {
        guard dfuController != nil else {
            print("No DFU peripheral was set")
            return
        }
        print("Action: DFU paused")
        dfuController!.pause()
        UIAlertView(title: "Warning", message: "Are you sure you want to stop the process?",
                    delegate: self, cancelButtonTitle: "No", otherButtonTitles: "Yes").show()
    }
    
    //MARK: - Class Implementation
    func secureDFUMode(_ secureDFU : Bool) {
        self.secureDFU = secureDFU
    }
    
    func getBundledFirmwareURLHelper() -> URL {
        if self.secureDFU! {
            return Bundle.main.url(forResource: "secure_dfu_test_app_hrm_s132", withExtension: "zip")!
        } else {
            return Bundle.main.url(forResource: "hrm_legacy_dfu_with_sd_s132_2_0_0", withExtension: "zip")!
        }
    }
    
    func setCentralManager(centralManager aCentralManager : CBCentralManager){
        self.centralManager = aCentralManager
    }

    func setTargetPeripheral(aPeripheral targetPeripheral : CBPeripheral) {
        self.dfuPeripheral = targetPeripheral
    }
    
    func startDFUProcess() {
        guard dfuPeripheral != nil else {
            print("No DFU peripheral was set")
            return
        }

        selectedFileURL  = self.getBundledFirmwareURLHelper()
        selectedFirmware = DFUFirmware(urlToZipFile: selectedFileURL!)

        let dfuInitiator = DFUServiceInitiator(centralManager: centralManager!, target: dfuPeripheral!)
        dfuInitiator.delegate = self
        dfuInitiator.progressDelegate = self
        dfuInitiator.logger = self
        dfuController = dfuInitiator.with(firmware: selectedFirmware!).start()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.peripheralNameLabel.text = "Flashing \((dfuPeripheral?.name)!)..."
        self.dfuActivityIndicator.startAnimating()
        self.dfuUploadProgressView.progress = 0.0
        self.dfuUploadStatus.text = ""
        self.dfuStatusLabel.text  = ""
        self.stopProcessButton.isEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.startDFUProcess()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if dfuController != nil {
            _ = dfuController?.abort()
        }
    }

    //MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("CM did update state: \(central.state.rawValue)")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name)")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name)")
    }

    //MARK: - DFUServiceDelegate
    func dfuStateDidChange(to state:DFUState) {
        switch state {
            case .completed, .disconnecting, .aborted:
                self.dfuActivityIndicator.stopAnimating()
                self.dfuUploadProgressView.setProgress(0, animated: true)
                self.stopProcessButton.isEnabled = false
            default:
                self.stopProcessButton.isEnabled = true
        }

        self.dfuStatusLabel.text = state.description()
        print("Changed state to: \(state.description())")
        
        // Forget the controller when DFU is done
        if state == .completed || state == .aborted {
            dfuController = nil
        }
    }

    func dfuError(_ error: DFUError, didOccurWithMessage message: String) {
        self.dfuStatusLabel.text = "Error \(error.rawValue): \(message)"
        self.dfuActivityIndicator.stopAnimating()
        self.dfuUploadProgressView.setProgress(0, animated: true)
        print("Error \(error.rawValue): \(message)")
        
        // Forget the controller when DFU finished with an error
        dfuController = nil
    }
    
    //MARK: - DFUProgressDelegate
    func dfuProgressDidChange(for part: Int, outOf totalParts: Int, to progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        self.dfuUploadProgressView.setProgress(Float(progress)/100.0, animated: true)
        self.dfuUploadStatus.text = String(format: "Part: %d/%d\nSpeed: %.1f KB/s\nAverage Speed: %.1f KB/s",
                                           part, totalParts, currentSpeedBytesPerSecond/1024, avgSpeedBytesPerSecond/1024)
    }

    //MARK: - LoggerDelegate
    func logWith(_ level:LogLevel, message:String) {
        print("\(level.name()): \(message)")
    }
    
    //MARK: - UIAlertViewDelegate
    func alertViewCancel(_ alertView: UIAlertView) {
        print("Action cancel: DFU resumed")
        if dfuController!.paused {
            dfuController!.resume()
        }
    }
    
    func alertView(_ alertView: UIAlertView, didDismissWithButtonIndex buttonIndex: Int) {
        guard dfuController != nil else {
            print("DFUController not set, cannot abort")
            return
        }

        switch buttonIndex {
        case 0:
            print("Action: DFU resumed")
            if dfuController!.paused {
                dfuController!.resume()
            }
        case 1:
            print("Action: DFU aborted")
            _ = dfuController!.abort()
        default:
            break
        }
    }

}
