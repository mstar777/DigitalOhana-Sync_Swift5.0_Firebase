// Google Firestore module

import UIKit
import Firebase
import FirebaseStorage
import FirebaseDatabase
import FirebaseFirestore
import GoogleSignIn
import GoogleAPIClientForREST
import GTMSessionFetcher

class PhotoField {
    static let taken: String = "taken"
    static let uploaded: String = "uploaded"
    static let location: String = "location"
    static let userid: String = "userid"
    static let email: String = "email"
    static let username: String = "username"
    static let sizeWidth: String = "sizeWidth"
    static let sizeHeight: String = "sizeHeight"
    static let tag: String = "tag"
    static let sourceType: String = "sourceType"
    static let sourceID: String = "sourceID"
    static let valid: String = "valid"
}

enum SourceType : Int {
    case asset = 0
    case drive = 1
}

class FSPhotoInfo {
    var id: String
    
    var userid: String                  // owner id, users collection on firestore db
    var email: String                   // owner email address
    var username: String                // owner name

    var sourceType: SourceType = .asset // from asset (0) or drive (1)
    var sourceID: String                // asset id or drive file id

    var taken: TimeInterval = 0         // photo taken time
    var uploaded: TimeInterval = 0      // photo uploaded time
    var location: String                // photo taken location
    
    var size: CGSize = CGSize(width: 0, height: 0) // photo dimensions
    var tag: String                     // tag

    var valid: Bool = false             // validation (false, true)
    
    init() {
        self.id = ""
        self.userid = Global.userid!
        self.email = Global.email!
        self.username = Global.username!

        self.sourceID = ""
        self.sourceType = .asset
        
        self.size = CGSize(width: 0, height: 0)
        self.location = ""
        self.tag = ""
        
        self.uploaded = Date().timeIntervalSince1970
        self.valid = false
    }
}

extension Dictionary {
    mutating func merge(dict: [Key: Value]){
        for (k, v) in dict {
            updateValue(v, forKey: k)
        }
    }
}

class GFSModule: NSObject {

    static func fetchUsers() {
        let db = Firestore.firestore()
        let refUsers = db.collection("users")
        
        refUsers.getDocuments { (querySnapshot, err) in
            if let err = err {
                print("Error getting users docuemts:\(err)")
            } else {
                for document in querySnapshot!.documents {
                    print("\(document.documentID) => \(document.data())")
                }
            }
        }
    }
    
    static func registerUser() {
        //fetchUsers()
        
        guard let userid = Global.userid else { return }
        guard let username = Global.username else { return }
        guard let email = Global.email else { return }

        let db = Firestore.firestore()
        
        db.collection("users").document(userid).updateData([
            "email": email,
            "name": username
        ]) { err in
            if let err = err {
                debugPrint(err)

                db.collection("users").document(userid).setData([
                    "email": email,
                    "name": username,
                    "allow": false
                ]) { err in
                    if let err = err {
                        debugPrint(err)
                    } else {
                        //self.userID = ref!.documentID
                    }
                }
            } else {
                
            }
        }
    }
    
    static func checkAllowOfUser(ID: String, onCompleted: @escaping (Bool) -> ()) {
        let db = Firestore.firestore()

        db.collection("users").document(ID).getDocument { (snapshot, error) in
            if let err = error {
                debugPrint(err)
            } else {
                let data = snapshot?.data()
                if data == nil {
                    onCompleted(false)
                } else {
                    let allow = data!["allow"] as? Bool
                    if allow == true {
                        onCompleted(true)
                    } else {
                        onCompleted(false)
                    }
                }
            }
        }
    }
    
    static func convertToPhotoInfo(document: QueryDocumentSnapshot) -> FSPhotoInfo {
        let photoInfo = FSPhotoInfo()
        
        let data = document.data()
        
        photoInfo.id = document.documentID
        
        photoInfo.userid = (data[PhotoField.userid] as! String)
        photoInfo.email = (data[PhotoField.email] as! String)
        photoInfo.username = (data[PhotoField.username] as! String)
        
        //let srcType = (data[PhotoField.sourceType] as! Int)
        //if srcType == 0 {
        //    photoInfo.sourceType = .asset
        //} else if srcType == 1 {
        //    photoInfo.sourceType = .drive
        //}

        let sourceType = data[PhotoField.sourceType]
        if sourceType == nil {
            photoInfo.sourceType = .asset
        } else if sourceType is SourceType {
            photoInfo.sourceType = (sourceType as! SourceType)
        } else if sourceType is Int {
            photoInfo.sourceType = SourceType(rawValue: sourceType as! Int) ?? .asset
        }
        
        photoInfo.sourceID = (data[PhotoField.sourceID] as! String)
        photoInfo.valid = (data[PhotoField.valid] as! Bool)
        
        let taken = data[PhotoField.taken]
        if taken is TimeInterval {
            photoInfo.taken = taken as! TimeInterval
        } else {
            photoInfo.taken = Date().timeIntervalSince1970
        }

        let uploaded = data[PhotoField.uploaded]
        if uploaded is TimeInterval {
            photoInfo.uploaded = uploaded as! TimeInterval
        } else {
            photoInfo.uploaded = Date().timeIntervalSince1970
        }
        
        let location = data[PhotoField.location]
        if location == nil {
            photoInfo.location = ""
        } else if location is String {
            photoInfo.location = (location as! String)
        } else {
            photoInfo.location = ""
        }

        let sizeWidth = data[PhotoField.sizeWidth]
        let sizeHeight = data[PhotoField.sizeHeight]
        if sizeWidth is CGFloat && sizeHeight is CGFloat  {
            photoInfo.size = CGSize(width: sizeWidth as! CGFloat, height: sizeHeight as! CGFloat)
        } else {
            photoInfo.size = CGSize(width: 0, height: 0)
        }
        
        return photoInfo
    }
    
    static func getAllPhotos(onCompleted: @escaping (Bool, [FSPhotoInfo]) -> ()) {
        let db = Firestore.firestore()
        let refPhotos = db.collection("photos")

        // order by uploaded date DESC
        refPhotos.order(by: PhotoField.uploaded, descending: true).getDocuments { (querySnapshot, err) in
            if let err = err {
                print("Error getting photos docuemts:\(err)")
                onCompleted(false, [])
            } else {
                var result = [FSPhotoInfo]()

                for document in querySnapshot!.documents {
                    // check validation
                    let data = document.data()
                    let valid = data["valid"] as! Bool
                    
                    if valid == true {
                        let info = self.convertToPhotoInfo(document: document)
                        result += [info]
                    }
                }
                
                Global.sharedCloudPhotos = result
                onCompleted(true, result)
            }
        }
    }
    
    static func searchPhoto(cloudDocumentID: String, onCompleted: @escaping (Bool, String?) -> ()) {
        let db = Firestore.firestore()

        db.collection("photos").document(cloudDocumentID).getDocument() { (document, error) in
            if let error = error {
                print("Error getting photos docuemts:\(error)")
                onCompleted(false, nil)
            } else {
                if let document = document {
                    if document.exists {
                        onCompleted(true, document.documentID)
                    } else {
                        onCompleted(false, nil)
                    }
                } else {
                    onCompleted(false, nil)
                }
            }
        }
    }

    static func searchPhoto(driveFileID: String, onCompleted: @escaping (Bool, String?) -> ()) {
        let email = Global.email!
        let db = Firestore.firestore()

        db.collection("photos")
            .whereField(PhotoField.email, isEqualTo: email)
            .whereField(PhotoField.sourceType, isEqualTo: "drive")
            .whereField(PhotoField.sourceID, isEqualTo: driveFileID)
            .getDocuments() { (querySnapshot, error) in
                if let error = error {
                    print("Error getting photos docuemts:\(error)")
                    onCompleted(false, nil)
                } else {
                    for document in querySnapshot!.documents {
                        onCompleted(true, document.documentID)
                        return
                    }
                    
                    onCompleted(false, nil)
                }
        }
    }
    
    static func registerPhoto(info: FSPhotoInfo, onCompleted: @escaping (Bool, String?) -> ()) {
        let data = [PhotoField.userid: info.userid,
            PhotoField.email: info.email,
            PhotoField.username: info.userid,
            PhotoField.taken: info.taken,
            PhotoField.uploaded: info.uploaded,
            PhotoField.sourceType: info.sourceType.rawValue,
            PhotoField.sourceID: info.sourceID,
            PhotoField.sizeWidth: info.size.width,
            PhotoField.sizeHeight: info.size.height,
            PhotoField.location: info.location,
            PhotoField.tag: info.tag,
            PhotoField.valid: false] as [String : Any]

        let db = Firestore.firestore()
        var ref: DocumentReference? = nil

        ref = db.collection("photos").addDocument(data: data) { err in
            if let err = err {
                debugPrint(err)
                onCompleted(false, nil)
            } else {
                onCompleted(true, ref!.documentID)
            }
        }
    }
    
    static func updatePhotoToValid(photoID: String, onCompleted: @escaping (Bool) -> ()) {
        let db = Firestore.firestore()

        db.collection("photos").document(photoID).updateData([
            "valid": true
        ]) { err in
            if let err = err {
                debugPrint(err)
                
            } else {
                onCompleted(true)
            }
        }
    }
    
    static func deletePhoto(photoID: String, onCompleted: @escaping (Bool) -> ()) {
        let db = Firestore.firestore()

        db.collection("photos").document(photoID).delete { (err) in
            if let err = err {
                debugPrint(err)
                onCompleted(false)
            } else {
                onCompleted(true)
            }
        }
    }
}
