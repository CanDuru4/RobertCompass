//
//  ViewController.swift
//  Radventure
//
//  Created by Can Duru on 22.06.2023.
//

//MARK: Import
import UIKit
import MapKit
import CoreLocation
import FirebaseFirestore
import FirebaseCore
import FirebaseDatabase
import AVFoundation
import AudioToolbox
import FirebaseAuth
import SceneKit

//MARK: Pin Data Structure
struct PinLocationsStructure{
    let latitude, longitude: Double
    let name, question, answer, questionType, optionsList: String
}

//MARK: Game Name Structure
struct GameNameStructure{
    var name, score, time: String
    
    var firestoreData: [String: Any] {
        return [
            "name": name,
            "score": score,
            "time": time,
        ]
    }
}

//MARK: Team Name Structure
struct TeamStructure{
    let name, uid, email: String
}

struct TeamMemberStructure {
    let name, email: String
}



class HomeMapViewController: UIViewController, CLLocationManagerDelegate {

//MARK: Set Up

    
    
    //MARK: Variable Set Up
    var place_name = ""
    var user_answer = ""
    var passwordKeyDatabase = ""
    var useruid = Auth.auth().currentUser?.uid
    var db = Firestore.firestore()
    var score = 0
    var alert_count = 1
    var location_count = 0
    var start_check = 0
    var children_count = 999
    var children_count2 = 999
    var didSetCount1 = 0
    var didSetCount2 = 0
    var timerLabel = UILabel()
    var startButton = UIButton(type: .custom)
    var startButtoncheck = 1
    var forceQuitButtonCheck = 0
    var forceQuitButton = UIButton(type: .custom)
    var logOutButton = UIButton(type: .custom)
    var forceQuitPassword = ""
    var randomRoute = 100
    var RandomRouteChoice = ""
    var user_latitude = 0.0
    var user_longitude = 0.0
    var gameCount = ""
    var arrayCount: [String] = []
    var user_name = ""
    var searchParameter = 0.0
    var map_latitude = 0.0
    var map_longitude = 0.0
    var teamCheck = 0
    var teamPersonNumber = 0
    var gameNameList: [String] = []
    var gameChosen = ""
    var teammembers: [TeamStructure] = []
    var game_password = ""
    var arrayCheck: [String] = []
    var questionType = ""
    
    //MARK: Map Set Up
    private let map: MKMapView = {
        let map = MKMapView()
        return map
    }()
    
    //MARK: Pin Location Data Set Up
    var pinlocationsdata:[PinLocationsStructure] = [] {
        didSet{
            //MARK: Annotate Pin Locations
            for PinAnnotation in self.map.annotations {
                self.map.removeAnnotation(PinAnnotation)
            }
            if didSetCount1 == children_count {
                pinLocations()
                filteredpinlocationsdata = pinlocationsdata
            } else if didSetCount2 == children_count2 {
                pinLocations()
                filteredpinlocationsdata = pinlocationsdata
            }
        }
    }
    var done_array = [String]()
    var filteredpinlocationsdata:[PinLocationsStructure] = []
    
    //MARK: Compass Setup
    var sceneView: UIView = {
        let sceneView = UIView()
        return sceneView
    }()
    let canvasView = CanvasView()
    let locationManager = CLLocationManager()

    //MARK: Game Name Setup
    var gameNameData: [GameNameStructure] = []
    
//MARK: Load
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //MARK: General Load
        view.backgroundColor = UIColor(named: "AppColor1")
        self.navigationController?.setNavigationBarHidden(true, animated: true)
        
        //MARK: Map Load
        view.addSubview(map)
        setMapLayout()
        mapLocation()
        setButton()
        if #available(iOS 16.0, *) {
            map.preferredConfiguration = MKHybridMapConfiguration()
        } else {
            map.mapType = .hybrid
        }
        map.delegate = self

        //MARK: Compass Delegate
        locationManager.delegate = self
        locationManager.startUpdatingHeading()

        //MARK: User Info Load
        getUserData(){
            
            
            //MARK: User Started Before
            if self.start_check == 1 {
                self.contactDatabaseGames() {
                    self.contactDatabase {
                        let hour = Calendar.current.component(.hour, from: Date())
                        let min = Calendar.current.component(.minute, from: Date())
                        if (self.finishHourIntStart < hour) {
                            AudioServicesPlaySystemSound(SystemSoundID(1304))
                            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                            self.forceQuitButton.isHidden = true
                            self.startButton.isHidden = false
                            self.logOutButton.isHidden = false
                            self.forceQuitButtonCheck = 0
                            self.startButtoncheck = 1
                            self.gameDataUpdate(){
                                if self.teamPersonNumber != 0 {
                                    for teammember in self.teammembers {
                                        self.firebaseTeamConnect(uid: teammember.uid, email: teammember.email, name: teammember.name)
                                    }
                                }
                                self.score = 0
                                self.timer_label.invalidate()
                                self.timerLabel.text = "00:00"
                            }
                            ProfileViewController().getUserScoreData {
                                ProfileViewController().getUserScoreData2 {
                                }
                            }
                            for PinAnnotation in self.map.annotations {
                                self.map.removeAnnotation(PinAnnotation)
                            }
                            self.db.collection("users").document(self.useruid!).updateData(["start": 0, "locations": [String]()]) { (error) in
                                if error != nil {
                                    let alert = UIAlertController(title: "An error occured. Try again.", message: "", preferredStyle: .alert)
                                    alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                                    self.present(alert, animated: true, completion: nil)
                                }
                            }
                            let alert = UIAlertController(title: "Activity automatically stopped.", message: "Since the finishing time is passed, activity is stopped.", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        } else if (self.finishHourIntStart == hour && self.finishMinuteIntStart < min){
                            AudioServicesPlaySystemSound(SystemSoundID(1304))
                            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                            self.forceQuitButton.isHidden = true
                            self.startButton.isHidden = false
                            self.logOutButton.isHidden = false
                            self.forceQuitButtonCheck = 0
                            self.startButtoncheck = 1
                            self.gameDataUpdate(){
                                if self.teamPersonNumber != 0 {
                                    for teammember in self.teammembers {
                                        self.firebaseTeamConnect(uid: teammember.uid, email: teammember.email, name: teammember.name)
                                    }
                                }
                                self.score = 0
                                self.timer_label.invalidate()
                                self.timerLabel.text = "00:00"
                            }
                            ProfileViewController().getUserScoreData {
                                ProfileViewController().getUserScoreData2 {
                                }
                            }
                            for PinAnnotation in self.map.annotations {
                                self.map.removeAnnotation(PinAnnotation)
                            }
                            self.db.collection("users").document(self.useruid!).updateData(["start": 0, "locations": [String]()]) { (error) in
                                if error != nil {
                                    let alert = UIAlertController(title: "An error occured. Try again.", message: "", preferredStyle: .alert)
                                    alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                                    self.present(alert, animated: true, completion: nil)
                                }
                            }
                            let alert = UIAlertController(title: "Activity automatically stopped.", message: "Since the finishing time is passed, activity is stopped.", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        } else {
                            self.timerLabelFunction()
                            self.countPins2(choice_pin2: self.RandomRouteChoice) {
                                self.PinLocationData(choice_pinlocationdata: self.RandomRouteChoice){
                                    self.startButton.isHidden = true
                                    self.forceQuitButton.isHidden = false
                                    self.logOutButton.isHidden = true
                                    self.forceQuitButtonCheck = 1
                                    self.startButtoncheck = 0
                                    self.location_count = self.pinlocationsdata.count
                                    for i in self.done_array{
                                        self.pinlocationsdata = self.pinlocationsdata.filter { $0.name.lowercased() != i.lowercased() }
                                        self.didSetCount2 = self.didSetCount2 - 1
                                        self.children_count2 = self.children_count2 - 1
                                        self.location_count = self.location_count - 1
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            //MARK: User Starting First Time
            else {
                self.startButton.isHidden = false
                self.forceQuitButton.isHidden = true
                self.logOutButton.isHidden = false
                self.pinlocationsdata = []
                self.done_array = []
            }
        }


        
        //MARK: Back Button Set Up
        let backButton = UIBarButtonItem()
        backButton.title = "Back"
        self.navigationController?.navigationBar.topItem?.backBarButtonItem = backButton
    }
   
    
    
//MARK: Location Manager Function for Compass
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let angle = newHeading.trueHeading * .pi / 180
        UIView.animate(withDuration:0.1){
            self.canvasView.transform = CGAffineTransform(rotationAngle: -CGFloat(angle))
        }
    }

    
    
//MARK: Map
    func mapLocation(){
        LocationManager.shared.getUserLocation { [weak self] location in DispatchQueue.main.async {
                guard let strongSelf = self else {
                    return
                }
                self!.contactDatabaseLocationInfo {
                    
                    let centercoordinates = CLLocationCoordinate2D(latitude: self!.map_latitude, longitude: self!.map_longitude)
                    strongSelf.map.setRegion(MKCoordinateRegion(center: centercoordinates, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)), animated: true)
                    strongSelf.map.showsUserLocation = true
                }
            }
        }
    }
    
    func setMapLayout(){
        map.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([map.topAnchor.constraint(equalTo: view.topAnchor), map.bottomAnchor.constraint(equalTo: view.bottomAnchor), map.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), map.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)])
    }
    
    
    
//MARK: Buttons Setup
    func setButton(){
        
        
        
        //MARK: Start Button
        startButton.setTitle("Start", for: .normal)
        startButton.setTitleColor(UIColor(named: "AppColor2"), for: .normal)
        startButton.backgroundColor = UIColor(named: "AppColor1")
        startButton.titleLabel?.font = .systemFont(ofSize: 19.0, weight: .bold)
        startButton.layer.cornerRadius = 15
        startButton.clipsToBounds = true
        startButton.addTarget(self, action: #selector(startButtonAction), for: .touchUpInside)
        view.addSubview(startButton)
        
        startButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([startButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor), startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40), startButton.widthAnchor.constraint(equalToConstant: 250), startButton.heightAnchor.constraint(equalToConstant: 45)])
        
        //MARK: Current Location Button
        let currentlocationButton = UIButton(type: .custom)
        currentlocationButton.backgroundColor = UIColor(named: "AppColor1")
        currentlocationButton.setImage(UIImage(systemName: "location.fill")?.resized(to: CGSize(width: 25, height: 25)).withTintColor(.white), for: .normal)
        currentlocationButton.addTarget(self, action: #selector(pressed), for: .touchUpInside)
        view.addSubview(currentlocationButton)
        
        currentlocationButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([currentlocationButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10), currentlocationButton.centerYAnchor.constraint(equalTo: startButton.centerYAnchor), currentlocationButton.widthAnchor.constraint(equalToConstant: 50), currentlocationButton.heightAnchor.constraint(equalToConstant: 50)])
        currentlocationButton.layer.cornerRadius = 25
        currentlocationButton.layer.masksToBounds = true
        
        //MARK: Zoom Out Button
        let zoomOutButton = UIButton(type: .custom)
        zoomOutButton.backgroundColor = UIColor(named: "AppColor1")
        zoomOutButton.setImage(UIImage(systemName: "minus.square.fill")?.resized(to: CGSize(width: 25, height: 25)).withTintColor(.white), for: .normal)
        zoomOutButton.addTarget(self, action: #selector(zoomOut), for: .touchUpInside)
        view.addSubview(zoomOutButton)
        
        zoomOutButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([zoomOutButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10), zoomOutButton.bottomAnchor.constraint(equalTo: currentlocationButton.topAnchor, constant: -20), zoomOutButton.widthAnchor.constraint(equalToConstant: 50), zoomOutButton.heightAnchor.constraint(equalToConstant: 50)])
        zoomOutButton.layer.cornerRadius = 10
        zoomOutButton.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner] // Top right corner, Top left corner respectively
        
        //MARK: Zoom In Button
        let zoomInButton = UIButton(type: .custom)
        zoomInButton.backgroundColor = UIColor(named: "AppColor1")
        zoomInButton.setImage(UIImage(systemName: "plus.square.fill")?.resized(to: CGSize(width: 25, height: 25)).withTintColor(.white), for: .normal)
        zoomInButton.addTarget(self, action: #selector(zoomIn), for: .touchUpInside)
        view.addSubview(zoomInButton)
        
        zoomInButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([zoomInButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10), zoomInButton.bottomAnchor.constraint(equalTo: zoomOutButton.topAnchor), zoomInButton.widthAnchor.constraint(equalToConstant: 50), zoomInButton.heightAnchor.constraint(equalToConstant: 50)])
        zoomInButton.layer.cornerRadius = 10
        zoomInButton.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner] // Top right corner, Top left corner respectively
        
        //MARK: Map Satellite  Button
        let mapSatelliteButton = UIButton(type: .custom)
        mapSatelliteButton.backgroundColor = UIColor(named: "AppColor1")
        mapSatelliteButton.setImage(UIImage(systemName: "globe")?.resized(to: CGSize(width: 25, height: 25)).withTintColor(.white), for: .normal)
        mapSatelliteButton.addTarget(self, action: #selector(mapSatellite), for: .touchUpInside)
        view.addSubview(mapSatelliteButton)
        
        mapSatelliteButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([mapSatelliteButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10), mapSatelliteButton.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: 20), mapSatelliteButton.widthAnchor.constraint(equalToConstant: 50), mapSatelliteButton.heightAnchor.constraint(equalToConstant: 50)])
        mapSatelliteButton.layer.cornerRadius = 25
        mapSatelliteButton.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner] // Top right corner, Top left corner respectively
        
        //MARK: Map Standard Button
        let mapStandard = UIButton(type: .custom)
        mapStandard.backgroundColor = UIColor(named: "AppColor1")
        mapStandard.setImage(UIImage(systemName: "map.fill")?.resized(to: CGSize(width: 25, height: 25)).withTintColor(.white), for: .normal)
        mapStandard.addTarget(self, action: #selector(mapStandardAction), for: .touchUpInside)
        view.addSubview(mapStandard)
        
        mapStandard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([mapStandard.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10), mapStandard.bottomAnchor.constraint(equalTo: mapSatelliteButton.topAnchor), mapStandard.widthAnchor.constraint(equalToConstant: 50), mapStandard.heightAnchor.constraint(equalToConstant: 50)])
        mapStandard.layer.cornerRadius = 25
        mapStandard.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner] // Top right corner, Top left corner respectively
        
        //MARK: Log Out Button
        logOutButton.setTitle("Log Out", for: .normal)
        logOutButton.setTitleColor(UIColor(named: "AppColor1"), for: .normal)
        logOutButton.addTarget(self, action: #selector(logOutAction), for: .touchUpInside)
        logOutButton.layer.cornerRadius = 5
        logOutButton.clipsToBounds = true
        logOutButton.backgroundColor = UIColor(white: 100, alpha: 0.005)
        logOutButton.underline()
        view.addSubview(logOutButton)
        
        logOutButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([logOutButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 15), logOutButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5), logOutButton.widthAnchor.constraint(equalToConstant: 75), logOutButton.heightAnchor.constraint(equalToConstant: 20)])
        
        //MARK: Rules Button
        let rulesButton = UIButton(type: .custom)
        rulesButton.setTitle("Rules", for: .normal)
        rulesButton.setTitleColor(UIColor(named: "AppColor2"), for: .normal)
        rulesButton.backgroundColor = UIColor(named: "AppColor1")
        rulesButton.layer.cornerRadius = 15
        rulesButton.clipsToBounds = true
        rulesButton.addTarget(self, action: #selector(rules), for: .touchUpInside)
        view.addSubview(rulesButton)
        
        rulesButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([rulesButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 15), rulesButton.topAnchor.constraint(equalTo: logOutButton.bottomAnchor, constant: 2), rulesButton.widthAnchor.constraint(equalToConstant: 75), rulesButton.heightAnchor.constraint(equalToConstant: 30)])
        
        //MARK: Force Quit Button
        forceQuitButton.setTitle("Force Quit", for: .normal)
        forceQuitButton.setTitleColor(UIColor(named: "AppColor1"), for: .normal)
        forceQuitButton.addTarget(self, action: #selector(forceQuitButtonAction), for: .touchUpInside)
        forceQuitButton.layer.cornerRadius = 5
        forceQuitButton.clipsToBounds = true
        forceQuitButton.backgroundColor = UIColor(white: 100, alpha: 0.005)
        view.addSubview(forceQuitButton)
        forceQuitButton.underline()
        
        forceQuitButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([forceQuitButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -15), forceQuitButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5), forceQuitButton.widthAnchor.constraint(equalToConstant: 100), forceQuitButton.heightAnchor.constraint(equalToConstant: 20)])
        
        //MARK: Timer Label
        timerLabel.backgroundColor = UIColor(named: "AppColor1")
        timerLabel.textColor = UIColor(named: "AppColor2")
        timerLabel.text = "Time"
        timerLabel.layer.cornerRadius = 15
        timerLabel.textAlignment = .center
        timerLabel.clipsToBounds = true
        view.addSubview(timerLabel)
        
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([timerLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -15), timerLabel.topAnchor.constraint(equalTo: forceQuitButton.bottomAnchor, constant: 2), timerLabel.widthAnchor.constraint(equalToConstant: 100), timerLabel.heightAnchor.constraint(equalToConstant: 30)])
        
        //MARK: Compass View
        canvasView.backgroundColor = UIColor(named: "AppColor1")
        view.addSubview(canvasView)
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([canvasView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10), canvasView.centerYAnchor.constraint(equalTo: startButton.centerYAnchor), canvasView.widthAnchor.constraint(equalToConstant: 50), canvasView.heightAnchor.constraint(equalToConstant: 50)])
        canvasView.layer.cornerRadius = 25
        canvasView.layer.masksToBounds = true
        
        view.addSubview(sceneView)
    }

    
    
//MARK: Current Location Button Action
    @objc func pressed() {
        LocationManager.shared.getUserLocation { [weak self] location in DispatchQueue.main.async {
                guard let strongSelf = self else {
                    return
                }
                strongSelf.map.setRegion(MKCoordinateRegion(center: location.coordinate, span:MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)), animated: true)
            }
        }
    }
    
  
    
//MARK: Map Sattelite Button Action
    @objc func mapSatellite() {
        if #available(iOS 16.0, *) {
            map.preferredConfiguration = MKHybridMapConfiguration()
        } else {
            map.mapType = .hybrid
        }
    }



//MARK: Map Standard Button Action
    @objc func mapStandardAction() {
        if #available(iOS 16.0, *) {
            map.preferredConfiguration = MKStandardMapConfiguration()
        } else {
            map.mapType = .standard
        }
    }
    
    
    
//MARK: Zoom In Button Action
    @objc func zoomIn() {
        zoomMap(byFactor: 0.5)
    }

    
    
//MARK: Zoom Out Button Action
    @objc func zoomOut() {
        zoomMap(byFactor: 2)
    }
    
    
    
//MARK: Rules Button Action
    @objc func rules(){
        self.present(RulesViewController(), animated: true)
    }
    
    
    
//MARK: Log Out Button Action
    @objc func logOutAction(){
        let firebaseAuth = Auth.auth()
        updateUserlogin {
            do {
              try firebaseAuth.signOut()
            } catch let signOutError as NSError {
                print("Error signing out: %@", signOutError)
                self.db.collection("users").document(self.useruid!).updateData(["login": 1]) { (error) in
                    if error != nil {
                        let alert = UIAlertController(title: "An error occured. Try again.", message: "", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                    }
                }
            }
            self.didSetCount1 = 0
            self.didSetCount2 = 0
            self.tabBarController?.tabBar.isHidden = true
            let newViewControllers = NSMutableArray()
            newViewControllers.add(LogInViewController())
            self.navigationController?.setViewControllers(newViewControllers as! [UIViewController], animated: true)
        }
    }
    
    func updateUserlogin(completion: @escaping () -> ()){
        db.collection("users").document(self.useruid!).updateData(["login": 0]) { (error) in
            if error != nil {
                let alert = UIAlertController(title: "An error occured. Try again.", message: "", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
            completion()
        }
    }
    
    
    
//MARK: Start Button Action
    @objc func startButtonAction(){
        self.gameNameList = []
        self.teammembers = []
        self.teamMembersString = ""
        self.arrayCheck = []
        
        contactDatabaseGameNameList(){
            if self.gameNameList.count != 0 {
                let alert = UIAlertController(title: "Avaiable Game Names", message: "", preferredStyle: .actionSheet)
                let maxnumber = self.gameNameList.count - 1
                if maxnumber == 0 {
                    let okAction = UIAlertAction(title: self.gameNameList[0], style: .default, handler: { (_) in
                        self.gameChosen = self.gameNameList[0]
                        self.alertAction()
                    })
                    alert.addAction(okAction)
                } else {
                    for i in 0...maxnumber {
                        let okAction = UIAlertAction(title: self.gameNameList[i], style: .default, handler: { (_) in
                            self.gameChosen = self.gameNameList[i]
                            
                            self.alertAction()
                        })
                        alert.addAction(okAction)
                    }
                }
                let cancelAction = UIAlertAction(title: "Cancel", style: .default, handler: { (_) in
                    self.gameNameList = []
                    self.teammembers = []
                })
                alert.addAction(cancelAction)
                self.present(alert, animated: true, completion: nil)
                
            } else {
                let alert = UIAlertController(title: "No Avaliable Games Rigth Now! Please try again later.", message: "", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
    
    
    
//MARK: Star Button Game Choice Action
    var startingHourInt = 0
    var startingMinuteInt = 0
    var finishHourIntStart = 0
    var finishMinuteIntStart = 0
    var gameName = ""
    var teamMembersString = ""
    
    func alertAction(){
        self.contactDatabaseGames() {
            //MARK: Password Check
            let alert = UIAlertController(title: "Enter the Password of the Game", message: "Communicate with your administrator to enter the password.", preferredStyle: .alert)
            alert.addTextField { (textField) in
                textField.placeholder = "Password"
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.default, handler: nil))
            alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { [weak alert] (_) in
                
                if self.game_password == (alert?.textFields![0].text ?? "") {
                    let hour = Calendar.current.component(.hour, from: Date())
                    let min = Calendar.current.component(.minute, from: Date())
                    
                    self.contactDatabase() {
                        if (self.startingHourInt > hour) {
                            let alert = UIAlertController(title: "Please wait for starting time.", message: "", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        } else if (self.startingHourInt == hour && self.startingMinuteInt > min){
                            let alert = UIAlertController(title: "Please wait for starting time.", message: "", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        } else if (self.finishHourIntStart < hour) {
                            let alert = UIAlertController(title: "Please check for starting time.", message: "", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        } else if (self.finishHourIntStart == hour && self.finishMinuteIntStart < min){
                            let alert = UIAlertController(title: "Please check for starting time.", message: "", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        } else {
                            AudioServicesPlaySystemSound(SystemSoundID(1304))
                            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                            let alert = UIAlertController(title: "You are about to start the activity!", message: "When you start the activity, you will be not able to force quit from it without administration password.", preferredStyle: .alert)
                            let okAction = UIAlertAction(title: "I am aware of my action.", style: .default, handler: { (_) in
                                
                                self.teamPersonName(){
                                    self.contactDatabaseArrayCount(){
                                        var randomChoice = self.arrayCount.count
                                        if randomChoice == 0 {
                                            
                                        } else {
                                            randomChoice = randomChoice - 1
                                        }
                                        self.randomRoute = Int.random(in: 0...randomChoice)
                                        self.RandomRouteChoice = self.arrayCount[self.randomRoute]
                                        self.didSetCount1 = 0
                                        self.didSetCount2 = 0
                                        var count_array = 0

                                        for i in self.teammembers {
                                            count_array = count_array + 1
                                            if count_array != self.teammembers.count {
                                                self.teamMembersString.append("\(i.name), ")
                                            } else {
                                                self.teamMembersString.append("\(i.name)")
                                            }
                                        }
                                        self.updateUserDatato0()

                                        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference().child("scores").child(self.gameChosen).child(self.useruid!)
                                        ref.setValue(["username": self.user_name, "score": 0, "time": "", "uid": self.useruid!, "teammembers": self.teamMembersString] as [String : Any])
                                        self.timerLabelFunction()
                                        self.countPins(choice_pin: self.RandomRouteChoice) {
                                            self.PinLocationData(choice_pinlocationdata: self.RandomRouteChoice){
                                                self.startButton.isHidden = true
                                                self.forceQuitButton.isHidden = false
                                                self.logOutButton.isHidden = true
                                                self.forceQuitButtonCheck = 1
                                                self.startButtoncheck = 0
                                                self.score = 0
                                                self.done_array = []
                                            }
                                        }
                                    }
                                }
                            })
                            alert.addAction(okAction)
                            alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.default, handler: nil))
                            alert.preferredAction = okAction
                            self.present(alert, animated: true, completion: nil)
                        }
                    }
                } else {
                    let alert = UIAlertController(title: "Password is not Correct!", message: "", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                }
            }))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    
    
//MARK: Communication with Database for Game Names w/ Completion
    func contactDatabaseGameNameList(completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference().child("games")
        ref.observeSingleEvent(of: .value) { snapshot in
            let gameaAvailable = snapshot.value as! Dictionary<String, Any>
            for (gameName, gameValue) in gameaAvailable {
                let gameValueDictionary = gameValue as! Dictionary<String, Any>
                for (key, value) in gameValueDictionary {
                    if key == "validation" {
                        if value as! Int == 1 {
                            self.gameNameList.append(gameName)
                        }
                    }
                }
            }
            completion()
        }
    }
    
    
    
//MARK: Communication with Database for Games Information w/ Completion
    func contactDatabaseGames(completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference().child("games")

        ref.observeSingleEvent(of: .value) { snapshot in
            for case _ as DataSnapshot in snapshot.children {
                let gameaAvailable = snapshot.value as! Dictionary<String, Any>
    
                for (gameName, gameValue) in gameaAvailable {
                    let gameValueDictionary = gameValue as! Dictionary<String, Any>
                    
                    if gameName == self.gameChosen {
                        var document_count2 = 0
                        for (key2, value2) in gameValueDictionary {
                            document_count2 = document_count2 + 1
                            if key2 == "team" {
                                self.teamCheck = value2 as! Int
                            } else if key2 == "teamPersonNumber" {
                                self.teamPersonNumber = value2 as! Int
                            } else if key2 == "password" {
                                self.game_password = value2 as! String
                            }
                            if document_count2 == gameaAvailable.count {
                                completion()
                            }
                        }
                    }
                }
            }
        }
    }

    
    
//MARK: Team Members Name Function
    var textFieldName: [TeamMemberStructure] = []
    func teamPersonName(completion: @escaping () -> ()) {
        if teamPersonNumber != 0 {
            textFieldName = []
            let alert = UIAlertController(title: "Team Members", message: "Please write the all team members' full name to the fields.", preferredStyle: .alert)
                    
            for i in 1...teamPersonNumber {
                alert.addTextField { (textField) in
                    textField.placeholder = "Please enter name of the team member \(i)."
                }
                alert.addTextField { (textField) in
                    textField.placeholder = "Please enter robcol email of the team member \(i)."
                }
            }
            
            alert.addAction(UIAlertAction(title: "Submit", style: .default, handler: { [weak alert] (_) in
                var document_count = 0
                let text_field_count = alert!.textFields!.count
                var count_set = 0
                _ = ""
                for i in alert!.textFields! {
                    count_set = count_set + 1
                    if i.text == "" {
                        self.dismiss(animated: true)
                        let alert = UIAlertController(title: "Please fill the all fields!", message: "", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                        return
                    } else {
                        if count_set % 2  == 0 {
                            self.db.collection("users").getDocuments() { (querySnapshot, err) in
                                if let err = err {
                                    completion()
                                    print("Error getting documents: \(err)")
                                } else {
                                    let document_max = querySnapshot!.documents.count
                                    for document in querySnapshot!.documents {
                                        self.addingToDatabase(i: i, documentID: document.documentID) {
                                            document_count = document_count + 1
                                            if (document_max * ((text_field_count) / 2)) == document_count {
                                                for emailofmissing in self.arrayCheck {
                                                    for j in self.textFieldName {
                                                        if emailofmissing == j.email {
                                                            self.teammembers.append(TeamStructure(name: j.name, uid: UUID().uuidString, email: emailofmissing))
                                                        }
                                                    }
                                                }
                                            }
                                            if (document_max * ((text_field_count) / 2)) == document_count {
                                                completion()
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            self.textFieldName.append(TeamMemberStructure(name: i.text!, email: alert!.textFields![count_set].text!))
                        }

                    }
                }
            }))
            self.present(alert, animated: true, completion: nil)
        } else {
            completion()
        }
    }
    
    var appendText = 1
    func addingToDatabase(i: UITextField, documentID: String, completion: @escaping () -> ()) {
        let docRef = self.db.collection("users").document(documentID)
        docRef.getDocument { (document, error) in
            if let document = document, document.exists {
                let uid = document.data()?["uid"] as? String ?? ""
                var users_name = document.data()?["name"] as? String ?? ""
                var users_email = document.data()?["email"] as? String ?? ""
                
                if let paranthesisRange = users_name.range(of: ") ") {
                    users_name.removeSubrange(users_name.startIndex..<(paranthesisRange.upperBound))
                }
                
                let lowercased_userText = i.text!.lowercased()
                var finalizedText = lowercased_userText.replacingOccurrences(of: "ö", with: "o")
                finalizedText = finalizedText.replacingOccurrences(of: "ü", with: "u")
                finalizedText = finalizedText.replacingOccurrences(of: "ç", with: "c")
                finalizedText = finalizedText.replacingOccurrences(of: "ş", with: "s")
                finalizedText = finalizedText.replacingOccurrences(of: "ğ", with: "g")
                finalizedText = finalizedText.replacingOccurrences(of: "ı", with: "i")
                
                if self.arrayCheck.contains(finalizedText){
                } else {
                    for i in self.teammembers {
                        if i.email == finalizedText {
                            self.appendText = 0
                        }
                    }
                    if self.appendText == 1 {
                        self.arrayCheck.append(finalizedText)
                    }
                }
                
                if users_name.lowercased() == finalizedText.lowercased() {
                    self.teammembers.append(TeamStructure(name: users_name.lowercased(), uid: uid, email: users_email.lowercased()))
                    self.arrayCheck = self.arrayCheck.filter { $0 != finalizedText }
                }
            }
            completion()
        }
    }
    
    
    
//MARK: Force Quit Button Action
    @objc func forceQuitButtonAction(){
        let alert = UIAlertController(title: "Enter the Password", message: "Communicate with your administrator to enter the password.", preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.placeholder = "Password"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.default, handler: nil))
        alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { [weak alert] (_) in
            self.forceQuitPassword = alert?.textFields![0].text ?? ""
            self.forceQuitFunction()
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    

//MARK: Check Force Quit Password Function
    func forceQuitFunction(){
        contactDatabasePassword {
            if self.passwordKeyDatabase == self.forceQuitPassword{
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                let alert = UIAlertController(title: "Quitted from the activity.", message: "", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                self.forceQuitButton.isHidden = true
                self.startButton.isHidden = false
                self.logOutButton.isHidden = false
                self.forceQuitButtonCheck = 0
                self.startButtoncheck = 1
                self.gameDataUpdate(){
                    if self.teamPersonNumber != 0 {
                        for teammember in self.teammembers {
                            self.firebaseTeamConnect(uid: teammember.uid, email: teammember.email, name: teammember.name)
                        }
                    }
                    self.score = 0
                    self.timer_label.invalidate()
                    self.timerLabel.text = "00:00"
                }
                ProfileViewController().getUserScoreData {
                    ProfileViewController().getUserScoreData2 {
                    }
                }
                for PinAnnotation in self.map.annotations {
                    self.map.removeAnnotation(PinAnnotation)
                }
                self.db.collection("users").document(self.useruid!).updateData(["start": 0, "locations": [String]()]) { (error) in
                    if error != nil {
                        let alert = UIAlertController(title: "An error occured. Try again.", message: "", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                    }
                }
            } else {
                let alert = UIAlertController(title: "Password is incorrect.", message: "Communicate with an administrator to enter the password.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
    
    
    
//MARK: Zoom in and Out Function
    func zoomMap(byFactor delta: Double) {
        var region: MKCoordinateRegion = self.map.region
        var span: MKCoordinateSpan = map.region.span
        
        let newLatitudeDelta = span.latitudeDelta * delta
        let newLongitudeDelta = span.longitudeDelta * delta
        
        let maxDeltaValue: CLLocationDegrees = 180
        let minDeltaValue: CLLocationDegrees = 0.0001
        
        span.latitudeDelta = min(max(newLatitudeDelta, minDeltaValue), maxDeltaValue)
        span.longitudeDelta = min(max(newLongitudeDelta, minDeltaValue), maxDeltaValue)
        
        region.span = span
        map.setRegion(region, animated: true)
    }

    
    
//MARK: Timer Label Function
    var timer_label = Timer()
    var finishHourInt = 0
    var finishMinuteInt = 0
    func timerLabelFunction(){
        timer_label = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
            self.timer_database {
                let hour = Calendar.current.component(.hour, from: Date())
                let min = Calendar.current.component(.minute, from: Date())
                let sec = Calendar.current.component(.second, from: Date())
                let date1 = DateComponents(calendar: .current, year: 1, month: 1, day: 1, hour: hour, minute: min, second: sec).date!
                let date2 = DateComponents(calendar: .current, year: 1, month: 1, day: 1, hour: self.finishHourInt, minute: self.finishMinuteInt).date!
                let minutes = date2.minutes(from: date1)
                let seconds = date2.seconds(from: date1)
                let seconds_text = seconds % 60
                
                if minutes == 0 && seconds_text == 0 {
                    AudioServicesPlaySystemSound(SystemSoundID(1304))
                    AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                    let alert = UIAlertController(title: "Time finished!", message: "Please go back to the Maze.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                    self.startButton.isHidden = false
                    self.forceQuitButton.isHidden = true
                    self.logOutButton.isHidden = false
                    self.forceQuitButtonCheck = 0
                    self.startButtoncheck = 1
                    for PinAnnotation in self.map.annotations {
                        self.map.removeAnnotation(PinAnnotation)
                    }
                    self.db.collection("users").document(self.useruid!).updateData(["start": 0, "locations": [String]()]) { (error) in
                        if error != nil {
                            let alert = UIAlertController(title: "An error occured. Try again.", message: "", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        }
                    }
                    self.gameDataUpdate(){
                        if self.teamPersonNumber != 0 {
                            for teammember in self.teammembers {
                                self.firebaseTeamConnect(uid: teammember.uid, email: teammember.email, name: teammember.name)
                            }
                        }
                        self.timer_label.invalidate()
                        self.timerLabel.text = "00:00"
                    }
                    ProfileViewController().getUserScoreData {
                        ProfileViewController().getUserScoreData2 {
                        }
                    }
                } else if (seconds_text < 10) {
                    let timeString = String(minutes)
                    let secondString = String(seconds_text)
                    self.timerLabel.text = "\(timeString):0\(secondString)"
                } else if (minutes < 10) {
                    let timeString = String(minutes)
                    let secondString = String(seconds_text)
                    self.timerLabel.text = "0\(timeString):\(secondString)"
                } else if (seconds_text < 10 && minutes < 10) {
                    let timeString = String(minutes)
                    let secondString = String(seconds_text)
                    self.timerLabel.text = "0\(timeString):0\(secondString)"
                } else {
                    let timeString = String(minutes)
                    let secondString = String(seconds_text)
                    self.timerLabel.text = "\(timeString):\(secondString)"
                }
            }
        })
    }
    
    
    
//MARK: Pin Location Annotation
    var PinAnnotations: CustomPointAnnotation!
    var PinAnnotationView:MKPinAnnotationView!
    
    //MARK: Check and mark pin locations in every 15 second
    @objc func pinLocations(){
        let locationCount = pinlocationsdata.count - 1
        if ((locationCount+1) != 0) {
            let i = Int.random(in: 0...locationCount)
            let coordinate = CLLocationCoordinate2DMake(CLLocationDegrees(pinlocationsdata[i].latitude), CLLocationDegrees(pinlocationsdata[i].longitude))
            let PinAnnotation = CustomPointAnnotation()
            PinAnnotation.coordinate = coordinate
            PinAnnotation.title = pinlocationsdata[i].name
            PinAnnotation.customidentifier = "pinAnnotation"
            map.addAnnotation(PinAnnotation)
        }
    }

    
    
//MARK: Location Data
    func countPins(choice_pin: String, completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference().child("games").child(gameChosen).child(choice_pin)
        ref.observe(DataEventType.value, with: { (snapshot) in
            self.children_count = Int(snapshot.childrenCount)
            completion()
        })
    }
    
    func countPins2(choice_pin2: String, completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference().child("games").child(gameChosen).child(choice_pin2)
        ref.observe(DataEventType.value, with: { (snapshot) in
            self.children_count2 = Int(snapshot.childrenCount)
            completion()
        })
    }
    
    @objc func PinLocationData(choice_pinlocationdata: String, completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference().child("games").child(gameChosen).child(choice_pinlocationdata)
        var name = ""
        var latitude = 0.000
        var longitude = 0.000
        var question = ""
        var answer = ""
        var questionType = ""
        var options = ""
        
        ref.observeSingleEvent(of: .value) { snapshot in
            for case let child as DataSnapshot in snapshot.children {
                guard let dict = child.value as? [String:Any] else {
                    return
                }
                name = dict["name"] as! String
                latitude = dict["latitude"] as! Double
                longitude = dict["longitude"] as! Double
                question = dict["question"] as! String
                answer = dict["answer"] as! String
                questionType = dict["questionType"] as! String
                options = dict["options"] as! String

                self.didSetCount1 = self.didSetCount1 + 1
                self.didSetCount2 = self.didSetCount2 + 1
                self.pinlocationsdata.append(PinLocationsStructure(latitude: latitude, longitude: longitude, name: name, question: question, answer: answer, questionType: questionType, optionsList: options))
                self.location_count = self.pinlocationsdata.count
            }
            completion()
        }
    }
    
    
    
//MARK: Display Question Function
    @objc func displayQuestion(){
        location_check {
            self.filteredpinlocationsdata = self.filteredpinlocationsdata.filter { ($0.name.lowercased().contains(self.place_name.lowercased())) }
            let selectedItem = CLLocation(latitude: (self.filteredpinlocationsdata[0].latitude), longitude: (self.filteredpinlocationsdata[0].longitude))
            let userLocation = CLLocation(latitude: (self.user_latitude), longitude: (self.user_longitude))
            let distancetodestination = selectedItem.distance(from: userLocation)
        
            //MARK: Verification of Location
            self.contactDatabaseSearchParameter {
                if distancetodestination < self.searchParameter {
                    let name_chosen = self.filteredpinlocationsdata[0].name
                    let question_chosen = self.filteredpinlocationsdata[0].question
                    
                    if self.filteredpinlocationsdata[0].questionType == "mcq" {
                        let alert = UIAlertController(title: "Question of the \(name_chosen)", message: question_chosen, preferredStyle: .alert)
                        let result = self.filteredpinlocationsdata[0].optionsList.components(separatedBy: ", ")
                        for i in result {
                            alert.addAction(UIAlertAction(title: i, style: .default, handler: { (_) in
                                self.user_answer = i
                                self.answercheck()
                            }))
                        }
                        alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                        
                    } else {
                        let alert = UIAlertController(title: "Question of the \(name_chosen)", message: question_chosen, preferredStyle: .alert)
                        alert.addTextField { (textField) in
                            textField.placeholder = "Please enter your answer"
                        }
                        alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.default, handler: nil))
                        alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { [weak alert] (_) in
                            self.user_answer = alert?.textFields![0].text ?? ""
                            self.answercheck()
                        }))
                        self.present(alert, animated: true, completion: nil)
                    }
                } else {
                    let alert = UIAlertController(title: "You are not in the correct location.", message: "You should be in \(Int((self.searchParameter))) meter perimeter circle around the point.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                }
            }
        }
    }
    
    
    
//MARK: User Location for Area Check
    func location_check(completion: @escaping () -> ()) {
        LocationManager.shared.getUserLocation { [weak self] location in DispatchQueue.main.async {
            guard self != nil else {
                    return
            }
            self!.user_longitude = location.coordinate.longitude
            self!.user_latitude = location.coordinate.latitude
            completion()
            }
        }
    }
    
    
    
//MARK: Team Members Firebase Data Update
    func firebaseTeamConnect(uid: String, email: String, name: String) {
        df.dateFormat = "dd/MM/yyyy HH:mm:ss"
        let dateString = df.string(from: date)
        var teamFirebase = ""
        teamFirebase = teamMembersString
        if teamFirebase.contains(", \(name)") {
            teamFirebase = teamFirebase.replacingOccurrences(of: ", \(name)", with: "")
        } else {
            teamFirebase = teamFirebase.replacingOccurrences(of: "\(name) ,", with: "")
        }
        var current_user_name = user_name.capitalized
        if let paranthesisRange = current_user_name.range(of: ") ") {
            current_user_name.removeSubrange(current_user_name.startIndex..<(paranthesisRange.upperBound))
        }
        teamFirebase.append(", \(current_user_name)")
        teamFirebase = teamFirebase.capitalized
        
        db.collection("users").document(uid).getDocument { (document, error) in
            if let document = document, document.exists {
                let user_game_count = document.data()?["gameCount"] as? Int ?? 0
                
                self.db.collection("users").document(uid).updateData(["gameCount": user_game_count+1, "gameName.\(self.gameCount).name": self.gameChosen, "gameName.\(self.gameCount).score": String(self.score),"gameName.\(self.gameCount).teamMembers": teamFirebase, "gameName.\(self.gameCount).date": dateString, "gameName.\(self.gameCount).remainingTime": self.timerLabel.text!]) { (error) in
                    if error != nil {
                    }
                }
            } else {
                self.db.collection("users").document(uid).setData([
                    "name": name,
                    "email": email,
                    "uid": uid,
                ]) { err in
                    if let err = err {
                        print("Error writing document: \(err)")
                    } else {
                        print("Document successfully written!")
                    }
                }
                self.db.collection("users").document(uid).updateData([
                    "gameCount": 1,
                    "gameName.1.name": self.gameChosen,
                    "gameName.1.score": String(self.score),
                    "gameName.1.teamMembers": teamFirebase,
                    "gameName.1.date": dateString,
                    "gameName.1.remainingTime": self.timerLabel.text!
                ])
            }
        }
    }
    
    
    
//MARK: Check Answer Function
    func answercheck(){
        let real_answer = filteredpinlocationsdata[0].answer.lowercased()
        if user_answer.lowercased() == real_answer {
            self.location_count = self.location_count - 1
            self.children_count = self.children_count - 1
            self.children_count2 = self.children_count2 - 1
            self.didSetCount1 = self.didSetCount1 - 1
            self.didSetCount2 = self.didSetCount2 - 1

            self.done_array.append(filteredpinlocationsdata[0].name)
            pinlocationsdata = pinlocationsdata.filter { $0.name.lowercased() != filteredpinlocationsdata[0].name.lowercased() }
            score = score + 100
            
            self.db.collection("users").document(self.useruid!).updateData(["locations": self.done_array,"score": self.score, "time": self.timerLabel.text!, "uid": self.useruid ?? ""]) { (error) in
                if error != nil {
                    let alert = UIAlertController(title: "An error occured. Try again.", message: "", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                }
            }
            let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference().child("scores").child(gameChosen).child(useruid!)
            ref.setValue(["username": user_name, "score": self.score, "time": self.timerLabel.text!, "uid": useruid!, "teammembers": self.teamMembersString] as [String : Any])
            
            if self.location_count == 0 {
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                AudioServicesPlaySystemSound(SystemSoundID(1304))
                let alert = UIAlertController(title: "You finished the activity!", message: "Please return to the starting point.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                forceQuitButton.isHidden = true
                startButton.isHidden = false
                logOutButton.isHidden = false
                forceQuitButtonCheck = 0
                startButtoncheck = 1
                self.gameDataUpdate(){
                    if self.teamPersonNumber != 0 {
                        for teammember in self.teammembers {
                            self.firebaseTeamConnect(uid: teammember.uid, email: teammember.email, name: teammember.name)
                        }
                    }
                    self.timer_label.invalidate()
                    self.timerLabel.text = "00:00"
                }
                ProfileViewController().getUserScoreData {
                    ProfileViewController().getUserScoreData2 {
                    }
                }
                for PinAnnotation in self.map.annotations {
                    self.map.removeAnnotation(PinAnnotation)
                }
                self.db.collection("users").document(self.useruid!).updateData(["start": 0, "locations": [String]()]) { (error) in
                    if error != nil {
                        let alert = UIAlertController(title: "An error occured. Try again.", message: "", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                    }
                }
            }
        } else {
            let alert = UIAlertController(title: "Answer is not correct.", message: "Please try again.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }


    
//MARK: Game Data Update
    func gameDataUpdate(completion: @escaping () -> ()){
        gameDataUpdateDatabase(){
            ProfileViewController().getUserScoreData {
                completion()
            }
        }
    }
    
    let date = Date()
    let df = DateFormatter()
    func gameDataUpdateDatabase(completion: @escaping () -> ()){
        df.dateFormat = "dd/MM/yyyy HH:mm:ss"
        let dateString = df.string(from: date)
        gameCount = String(Int(gameCount)! + 1)
        self.db.collection("users").document(self.useruid!).updateData(["gameCount": self.gameCount, "gameName.\(self.gameCount).name": self.gameChosen, "gameName.\(self.self.gameCount).score": String(self.score),"gameName.\(self.gameCount).teamMembers": self.teamMembersString, "gameName.\(self.gameCount).date": dateString, "gameName.\(self.gameCount).remainingTime": self.timerLabel.text!]) { (error) in
            if error != nil {
                let alert = UIAlertController(title: "An error occured. Try again.", message: "", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
            completion()
        }
    }
    
    
    
//MARK: Timer Data
    func timer_database(completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference().child("games")
        ref.observeSingleEvent(of: .value) { snapshot in
            for case let child as DataSnapshot in snapshot.children {
                guard let dict = child.value as? [String:Any] else {
                    return
                }
//                if child.key == "time" {
//                    self.finishHourInt = dict["finishHourInt"] as! Int
//                    self.finishMinuteInt = dict["finishMinuteInt"] as! Int
//                    completion()
//                }
                
                let timeCheck = snapshot.value as! Dictionary<String, Any>
                for (gameName, _) in timeCheck {
                    if gameName == self.gameChosen {
                        let info = dict
                        for (key, value) in info {
                            if key == "time" {
                                let info2 = value as! Dictionary<String, Any>
                                for (key2, value2) in info2 {
                                    if key2 == "finishHourInt" {
                                        self.finishHourInt = value2 as? Int ?? 0
                                    } else if key2 == "finishMinuteInt" {
                                        self.finishMinuteInt = value2 as? Int ?? 0
                                    }
                                }
                                completion()
                            }
                        }
                    }
                }
            }
        }
    }
        
    
    
//MARK: Communication with Database w/ Completion
    func contactDatabase(completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference().child("games")
        ref.observeSingleEvent(of: .value) { snapshot in
            for case let child as DataSnapshot in snapshot.children {
                guard let dict = child.value as? [String:Any] else {
                    return
                }
//                if child.key == "time" {
//                    self.startingHourInt = dict["startingHourInt"] as! Int
//                    self.startingMinuteInt = dict["startingMinuteInt"] as! Int
//                    self.finishHourIntStart = dict["finishHourInt"] as! Int
//                    self.finishMinuteIntStart = dict["finishMinuteInt"] as! Int
//                    completion()
//                }
                
                let timeCheck = snapshot.value as! Dictionary<String, Any>
                for (gameName, _) in timeCheck {
                    if gameName == self.gameChosen {
                        let info = dict
                        for (key, value) in info {
                            if key == "time" {
                                let info2 = value as! Dictionary<String, Any>
                                for (key2, value2) in info2 {
                                    if key2 == "finishHourInt" {
                                        self.finishHourIntStart = value2 as? Int ?? 0
                                    } else if key2 == "finishMinuteInt" {
                                        self.finishMinuteIntStart = value2 as? Int ?? 0
                                    } else if key2 == "startingHourInt" {
                                        self.startingHourInt = value2 as? Int ?? 0
                                    } else if key2 == "startingMinuteInt" {
                                        self.startingMinuteInt = value2 as? Int ?? 0
                                    }
                                }
                                completion()
                            }
                        }
                    }
                }
            }
        }
    }
  
    
    
//MARK: Communication with Database for Search Parameter w/ Completion
    func contactDatabaseSearchParameter(completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference()
        ref.observeSingleEvent(of: .value) { snapshot in
            for case let child as DataSnapshot in snapshot.children {
                guard let dict = child.value as? [String:Any] else {
                    return
                }
                if child.key == "searchParameter" {
                    self.searchParameter = dict["searchParameter"] as! Double
                    completion()
                }
            }
        }
    }
    
    
    
//MARK: Communication with Database for Location w/ Completion
    func contactDatabaseLocationInfo(completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference()
        ref.observeSingleEvent(of: .value) { snapshot in
            for case let child as DataSnapshot in snapshot.children {
                guard let dict = child.value as? [String:Any] else {
                    return
                }
                if child.key == "locationData" {
                    self.map_latitude = dict["latitude"] as! Double
                    self.map_longitude = dict["longitude"] as! Double
                    completion()
                }
            }
        }
    }
    
    
    
//MARK: Communication with Database for Array Number w/ Completion
    func contactDatabaseArrayCount(completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app/").reference().child("games").child(gameChosen)
        ref.observeSingleEvent(of: .value) { snapshot in
            var count = snapshot.childrenCount
            for case let child as DataSnapshot in snapshot.children {
                let result = child.key.contains("coordinates")
                if result {
                    self.arrayCount.append(child.key)
                }
                
                count = count - 1
                if count == 0 {
                    completion()
                }
            }
        }
    }

    
    
//MARK: Communication with Database for Password w/ Completion
    func contactDatabasePassword(completion: @escaping () -> ()){
        let ref = Database.database(url: "https://radventure-robert-default-rtdb.europe-west1.firebasedatabase.app").reference()
        ref.observeSingleEvent(of: .value) { snapshot in
            for case let child as DataSnapshot in snapshot.children {
                guard let dict = child.value as? [String:Any] else {
                    return
                }
                if child.key == "password" {
                    self.passwordKeyDatabase = dict["password"] as! String
                    completion()
                }
            }
        }
    }
    
    
    
//MARK: Get User Data
    func getUserData(completion: @escaping () -> ()){
        let db = Firestore.firestore()
        let docRef = db.collection("users").document(useruid!)
        docRef.getDocument { (document, error) in
            if let document = document, document.exists {
                self.user_name = document.data()?["name"] as? String ?? ""
                self.start_check = document.data()?["start"] as? Int ?? 0
                self.done_array = document.data()?["locations"] as? Array ?? []
                self.score = document.data()?["score"] as! Int
                self.RandomRouteChoice = document.data()?["route"] as? String ?? "coordinates"
                self.gameCount = document.data()?["gameCount"] as? String ?? "0"
                self.gameChosen = document.data()?["gameNameString"] as? String ?? ""
                self.teamMembersString = document.data()?["teamMembers"] as? String ?? ""
                completion()
            } else {
                print("Document does not exist")
            }
        }
    }
 
        
        
//MARK: Update Score with starting
    func updateUserDatato0(){
        db.collection("users").document(self.useruid!).updateData(["teamMembers": teamMembersString,"gameNameString": gameChosen,"score": 0, "start": 1,"time": "", "uid": self.useruid!, "locations": [String](), "route": self.RandomRouteChoice]) { (error) in
            if error != nil {
                let alert = UIAlertController(title: "An error occured. Try again.", message: "", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
}



//MARK: Image Resize Extension
extension UIImage {
    public func resized(to target: CGSize) -> UIImage {
        let ratio = min(
            target.height / size.height, target.width / size.width
        )
        let new = CGSize(
            width: size.width * ratio, height: size.height * ratio
        )
        let renderer = UIGraphicsImageRenderer(size: new)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: new))
        }
    }
}



//MARK: Pin With Image Extension
extension HomeMapViewController : MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView?  {
        
        guard let annotation = annotation as? CustomPointAnnotation else {
            return nil
        }
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "reuseIdentifier")
        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: "reuseIdentifier")
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = annotation
        }
        
        //MARK: Pin Annotation
        if annotation.customidentifier == "pinAnnotation" {
            if #available(iOS 17.0, *) {
                let pinView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: String(annotation.hash))
                let rightButton = UIButton(type: .contactAdd)
                rightButton.setImage(UIImage(systemName: "questionmark.bubble.fill")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal), for: .normal)
                rightButton.tag = annotation.hash
                pinView.glyphImage = UIImage(systemName: "pin.fill")!.withRenderingMode(.alwaysOriginal).withTintColor(.systemBlue, renderingMode: .alwaysOriginal).resized(to: CGSize(width: 30, height: 30))
                pinView.canShowCallout = true
                pinView.rightCalloutAccessoryView = rightButton
                rightButton.addTarget(self, action: #selector(displayQuestion), for: .touchUpInside)
                return pinView
            } else {
                let pinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: String(annotation.hash))
                let rightButton = UIButton(type: .contactAdd)
                rightButton.setImage(UIImage(systemName: "questionmark.circle.fill")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal), for: .normal)
                rightButton.tag = annotation.hash
                pinView.image = UIImage(systemName: "pin.fill")!.withRenderingMode(.alwaysOriginal).withTintColor(.systemBlue, renderingMode: .alwaysOriginal).resized(to: CGSize(width: 25, height: 25))
                pinView.animatesDrop = false
                pinView.canShowCallout = true
                pinView.rightCalloutAccessoryView = rightButton
                rightButton.addTarget(self, action: #selector(displayQuestion), for: .touchUpInside)
                return pinView
            }
        }
        return annotationView
    }
    
//    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
//
//            var span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
//            var region = MKCoordinateRegion(center: self.coordinate, span: span)
//            mapView.setRegion(region, animated: true)
//
//    }
    
    //MARK: Select Annotation
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView)  {
        let annotation = view.annotation as? CustomPointAnnotation

        if annotation?.customidentifier == "pinAnnotation" {
            place_name = annotation?.title ?? ""
        }
    }
    
    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        let annotation = view.annotation as? CustomPointAnnotation

        if annotation?.customidentifier == "pinAnnotation" {
            place_name = ""
        }
    }
}



//MARK: Date Extension
extension Date {
    /// Returns the amount of years from another date
    func years(from date: Date) -> Int {
        return Calendar.current.dateComponents([.year], from: date, to: self).year ?? 0
    }
    /// Returns the amount of months from another date
    func months(from date: Date) -> Int {
        return Calendar.current.dateComponents([.month], from: date, to: self).month ?? 0
    }
    /// Returns the amount of weeks from another date
    func weeks(from date: Date) -> Int {
        return Calendar.current.dateComponents([.weekOfMonth], from: date, to: self).weekOfMonth ?? 0
    }
    /// Returns the amount of days from another date
    func days(from date: Date) -> Int {
        return Calendar.current.dateComponents([.day], from: date, to: self).day ?? 0
    }
    /// Returns the amount of hours from another date
    func hours(from date: Date) -> Int {
        return Calendar.current.dateComponents([.hour], from: date, to: self).hour ?? 0
    }
    /// Returns the amount of minutes from another date
    func minutes(from date: Date) -> Int {
        return Calendar.current.dateComponents([.minute], from: date, to: self).minute ?? 0
    }
    /// Returns the amount of seconds from another date
    func seconds(from date: Date) -> Int {
        return Calendar.current.dateComponents([.second], from: date, to: self).second ?? 0
    }
    /// Returns the a custom time interval description from another date
    func offset(from date: Date) -> String {
        if years(from: date)   > 0 { return "\(years(from: date))y"   }
        if months(from: date)  > 0 { return "\(months(from: date))M"  }
        if weeks(from: date)   > 0 { return "\(weeks(from: date))w"   }
        if days(from: date)    > 0 { return "\(days(from: date))d"    }
        if hours(from: date)   > 0 { return "\(hours(from: date))h"   }
        if minutes(from: date) > 0 { return "\(minutes(from: date))m" }
        if seconds(from: date) > 0 { return "\(seconds(from: date))s" }
        return ""
    }
}



//MARK: UIButton Extension for Underlined Text
extension UIButton {
    func underline() {
        guard let title = self.titleLabel else { return }
        guard let tittleText = title.text else { return }
        let attributedString = NSMutableAttributedString(string: (tittleText))
        attributedString.addAttribute(NSAttributedString.Key.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: (tittleText.count)))
        self.setAttributedTitle(attributedString, for: .normal)
    }
}
