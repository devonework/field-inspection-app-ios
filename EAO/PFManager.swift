//
//  PFManager.swift
//  EAO
//
//  Created by Amir Shayegh on 2018-01-16.
//  Copyright © 2018 FreshWorks. All rights reserved.
//

import Foundation
import AVFoundation
import Parse
import Photos

class PFManager {

    static let shared = PFManager()

    private init() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            // process files
            for url in fileURLs {
                print(url)
            }
        } catch {

        }
    }

    func uploadInspection(inspection: PFInspection, completion: @escaping (_ done: Bool) -> Void) {
        let object = PFObject(className: "Inspection")

        let userId = inspection.userId ?? ""
        let project = inspection.project ?? ""
        let title = inspection.title ?? ""
        let subtitle = inspection.subtitle ?? ""
        let subtext = inspection.subtext ?? ""
        let number = inspection.number ?? ""
        let start = inspection.start
        let end = inspection.end

        object["userId"] = userId
        object["project"] = project
        object["title"] = title
        object["subtitle"] = subtitle
        object["subtext"] = subtext
        object["number"] = number
        object["start"] = start
        object["end"] = end

        object["uploaded"] = false

        object.saveInBackground { (success, error) in
            if success {
                self.getObservationsFor(inspection: inspection, completion: { (success, observations) in
                    if success {
                        let temp: [PFObject] = [PFObject]()
                        self.recursiveObservationUpload(observations: observations!, inspection: object, objects: temp, completion: { (success, uploadedObjects) in
                            if success {
                                // get team
                                if inspection.teamID != nil && inspection.teamID != "" {
                                    let query = PFQuery(className: "Team")
                                    query.getObjectInBackground(withId: inspection.teamID!, block: { (teamobject, error) in
                                        if let teamobj = teamobject {
                                            object["team"] = teamobj
                                            object["uploaded"] = true
                                            object["isSubmitted"] = true
                                            object["isActive"] = true
                                            inspection.isSubmitted = true
                                            inspection.pinInBackground()
                                            object.saveInBackground(block: { (success, error) in
                                                if success {
                                                    return completion(true)
                                                } else {
                                                    return completion(false)
                                                }
                                            })
                                        }
                                    })
                                } else {
                                    object["uploaded"] = true
                                    object["isSubmitted"] = true
                                    object["isActive"] = true
                                    inspection.isSubmitted = true
                                    inspection.pinInBackground()
                                    object.saveInBackground(block: { (success, error) in
                                        if success {
                                            return completion(true)
                                        } else {
                                            return completion(false)
                                        }
                                    })
                                }
                            } else {
                                return completion(false)
                            }
                        })
                    } else {
                        return completion(false)
                    }
                })
            } else {
                return completion(false)
            }
        }

    }

    func recursiveObservationUpload(observations: [PFObservation], inspection: PFObject, objects: [PFObject], completion: @escaping (_ done: Bool, _ observations: [PFObject]?) -> Void) {
        var array = observations
        var results = objects
        let current = observations.last
        array.removeLast()

        uploadObserbation(observation: current!, inspection: inspection) { done, object  in
            if done {
                results.append(object!)
                if !array.isEmpty && array.count > 0 {
                    self.recursiveObservationUpload(observations: array,inspection: inspection, objects: results, completion: completion)
                } else {
                    return completion(true, results)
                }
            } else {
                return completion(false, nil)
            }
        }
    }

    func uploadObserbation(observation: PFObservation, inspection: PFObject, completion: @escaping (_ done: Bool, _ observation: PFObject?) -> Void) {
        print(observation)
        let object = PFObject(className: "Observation")

        let title = observation.title
        let requirement = observation.requirement ?? ""
        let coordinate = observation.coordinate ?? PFGeoPoint()
        let observationDescription = observation.observationDescription ?? ""

        object["title"] = title
        object["requirement"] = requirement
        object["coordinate"] = coordinate
        object["observationDescription"] = observationDescription
        object["inspection"] = inspection

        object.saveInBackground { (success, error) in
            if success {
                self.uploadVideos(for: observation, observObj: object, completion: { (done) in
                    if done {
                        self.uploadAudios(for: observation,  obsObj: object, completion: { (done) in
                            if done {
                                self.uploadPhotos(for: observation, obsObj: object, completion: { (done) in
                                    if done {
                                        return completion(true, object)
                                    } else {
                                        return completion(false, nil)
                                    }
                                })
                            } else {
                                return completion(false, nil)
                            }
                        })
                    } else {
                        return completion(false, nil)
                    }
                })
            } else {
                return completion(false, nil)
            }
        }
    }

    func getObservationsFor(inspection: PFInspection, completion: @escaping (_ done: Bool, _ observations: [PFObservation]?) -> Void) {
        PFObservation.load(for: inspection.id!) { (results) in
            guard let observations = results, !observations.isEmpty else{
                return completion(false, nil)
            }
            return completion(true, observations)
        }
    }

    // save locally
    func saveVideo(avAsset: AVAsset, thumbnail: UIImage,index: Int, observationID: String, description: String?, completion: @escaping (_ created: Bool) -> Void) {

        saveThumbnail(image: thumbnail, index: index, originalType: "video", observationID: observationID, description: description) { (done) in
            if !done{ return completion (false)}
            // then save video
            let video = PFVideo()
            video.id = "\(UUID().uuidString).mp4"
            video.observationId = observationID
            video.index = index as NSNumber
            video.notes = description
            let exportURL: URL = FileManager.directory.appendingPathComponent(video.id!, isDirectory: true)
            let exporter = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetHighestQuality)
            exporter?.outputFileType = AVFileType.mov
            exporter?.outputURL = exportURL
            exporter?.exportAsynchronously(completionHandler: {
                self.savePFVideo(video: video, completion: completion)
            })
        }
    }

    func savePFVideo(video: PFVideo, completion: @escaping (_ created: Bool) -> Void) {
        do {
            video.pinInBackground { (success, error) in
                if success && error == nil {
                    // success
                    return completion(true)
                } else {
                    // fail
                    return completion(false)
                }
            }
        } catch {
            // fail
            return completion(false)
        }
    }

    func getVideoAt(observationID: String, at: Int, completion: @escaping (_ success: Bool, _ video: PFVideo? ) -> Void) {
        getVideosFor(observationID: observationID) { (found, pfvideos) in
            if found {
                if (pfvideos?.count)! >= at {
                    return completion(true,  pfvideos?[at])
                } else {
                    return completion(false, nil)
                }
            }
        }
    }

    func uploadVideo(for observation: PFObservation, obsObj: PFObject, at index: Int, completion: @escaping (_ success: Bool, _ pfObject: PFObject? ) -> Void) {
        let video = PFObject(className: "Video")

        getVideoAt(observationID: observation.id!, at: index) { (found, pfvideo) in
            if !found {
                print("not found!")
            }

            let title: String = pfvideo?.title ?? ""
            let notes: String  = pfvideo?.notes ?? ""
            var vidIndex: Int = -1
            if let indx = pfvideo?.index {
                vidIndex = indx as! Int
            }

            let videoData = pfvideo?.get()
            if videoData == nil {
                return completion(false, nil)

            }
            let parseVideoFile = PFFile(name: "\(observation.id!)\(index).mp4", data: videoData!)
            parseVideoFile?.saveInBackground(block: { (success, error) -> Void in
                if success{
                    video["title"] = title
                    video["notes"] = notes
                    video["index"] = vidIndex
                    video["video"] = parseVideoFile
                    video["observation"] = obsObj
                    video.saveInBackground(block: { (success, error) in
                        if success  {
                            return completion(true, video)
                        } else {
                            print(error)
                            return completion(false, nil)
                        }
                    })
                } else {
                    print(error)
                    return completion(false, nil)
                }
            })
        }
    }

    // count instead of array of videos because i was resuing functions: there is a function to get video at index for observation
    func recursiveVideoUpload(last index: Int,for observation: PFObservation, observObj: PFObject, parseVideoObjects: [PFObject],completion: @escaping (_ done: Bool, _ videos: [PFObject]) -> Void) {
        if index > -1 {

            uploadVideo(for: observation, obsObj: observObj, at: index, completion: { (success, videoObjsect) in
                if success {
                    var objects = parseVideoObjects
                    objects.append(videoObjsect!)

                    let nextIndex = index - 1
                    if nextIndex > -1 {
                        self.recursiveVideoUpload(last: nextIndex, for: observation, observObj: observObj, parseVideoObjects: objects, completion: completion)
                    } else {
                        // done
                        completion(true, objects)
                    }
                } else {
                    // fail
                    completion(false, parseVideoObjects)
                }
            })
        } else {
            // done
            completion(true, parseVideoObjects)
        }
    }

    func getVideosFor(observationID: String, completion: @escaping (_ success: Bool, _ videos: [PFVideo]? ) -> Void) {
        guard let query = PFVideo.query() else {
            // fail
            return completion(false, nil)
        }

        query.fromLocalDatastore()
        query.whereKey("observationId", equalTo: observationID)
        query.findObjectsInBackground(block: { (videos, error) in
            guard let storedVideos = videos as? [PFVideo], error == nil else {
                // fail
                return completion(false, nil)
            }
            // success
            return completion(true, storedVideos)
        })
    }

    //    func getAudiosFor(observationID: String, completion: @escaping (_ success: Bool, _ sounds: [PFAudio]? ) -> Void) {
    //        guard let query = PFAudio.query() else {
    //            // fail
    //            return completion(false, nil)
    //        }
    //
    //        query.fromLocalDatastore()
    //        query.whereKey("observationId", equalTo: observationID)
    //        query.findObjectsInBackground(block: { (sounds, error) in
    //            guard let storedSounds = sounds as? [PFAudio], error == nil else {
    //                // fail
    //                return completion(false, nil)
    //            }
    //            // success
    //            return completion(true, storedSounds)
    //        })
    //    }
    func uploadAudio(for observation: PFObservation,  obsObj: PFObject, at index: Int, completion: @escaping (_ success: Bool, _ pfObject: PFObject? ) -> Void) {
        let audio = PFObject(className: "Audio")
        getAudiosFor(observationID: observation.id!) { (success, audios) in
            if success, let results = audios {
                let current = results[index]
                let observationId : String = current.observationId ?? ""
                let coordinate : PFGeoPoint = current.coordinate ?? PFGeoPoint()
                let index: Int = index
                let notes: String = current.notes ?? ""
                let title: String = current.title ?? ""
                let audioData = current.get()
                if audioData == nil { return completion(false, nil)}
                let parseAudioFile = PFFile(name: "\(observationId)\(index).mp4a", data: audioData!)
                parseAudioFile?.saveInBackground(block: { (success, error) -> Void in
                    if success {
                        audio["coordinate"] = coordinate
                        audio["notes"] = notes
                        audio["index"] = index
                        audio["title"] = title
                        audio["audio"] = parseAudioFile
                        audio["observation"] = obsObj
                        audio.saveInBackground(block: { (success, error) in
                            if success  {
                                return completion(true, audio)
                            } else {
                                return completion(false, nil)
                            }
                        })
                    } else {
                        return completion(false, nil)
                    }
                })
            }
        }
        /*
        getAudioFor(observationID: observation.id!, at: index) { (found, pfaudio) in
            let observationId : String = pfaudio?.observationId ?? ""
            let coordinate : PFGeoPoint = pfaudio?.coordinate ?? PFGeoPoint()
            let index: Int = index
            let notes: String = pfaudio?.notes ?? ""
            let title: String = pfaudio?.title ?? ""
            let audioData = pfaudio?.get()
            if audioData == nil { return completion(false, nil)}
            let parseAudioFile = PFFile(name: "\(observationId)\(index).mp4a", data: audioData!)
            parseAudioFile?.saveInBackground(block: { (success, error) -> Void in
                if success {
                    audio["coordinate"] = coordinate
                    audio["notes"] = notes
                    audio["index"] = index
                    audio["title"] = title
                    audio["audio"] = parseAudioFile
                    audio["observation"] = obsObj
                    audio.saveInBackground(block: { (success, error) in
                        if success  {
                            return completion(true, audio)
                        } else {
                            return completion(false, nil)
                        }
                    })
                } else {
                    return completion(false, nil)
                }
            })
        }*/
    }

    func recursiveAudioUpload(last index: Int,for observation: PFObservation,  obsObj: PFObject, parseAudioObjects: [PFObject],completion: @escaping (_ done: Bool, _ audios: [PFObject]) -> Void) {
        if index > -1 {
            uploadAudio(for: observation, obsObj: obsObj, at: index, completion: { (success, audioObjsect) in
                if success {
                    var objects = parseAudioObjects
                    objects.append(audioObjsect!)

                    let nextIndex = index - 1
                    if nextIndex > -1 {
                        self.recursiveAudioUpload(last: nextIndex, for: observation, obsObj: obsObj, parseAudioObjects: objects, completion: completion)
                    } else {
                        // done
                        completion(true, objects)
                    }
                } else {
                    // fail
                    completion(false, parseAudioObjects)
                }
            })
        } else {
            // done
            completion(true, parseAudioObjects)
        }
    }

    func uploadAudios(for observation: PFObservation, obsObj: PFObject, completion: @escaping (_ success: Bool) -> Void) {
        getAudiosFor(observationID: observation.id!) { (success, pfaudios) in
            if success {
                if let count = pfaudios?.count {
                    let parseSoundObjects: [PFAudio] = [PFAudio]()
                    self.recursiveAudioUpload(last: (count - 1), for: observation, obsObj: obsObj, parseAudioObjects: parseSoundObjects, completion: { (done, audios) in
                        if done {
                            return completion(true)
                            //                            let query = PFQuery(className:"Observation")
                            //                            query.getObjectInBackground(withId: obsObj.objectId!, block: { (foundObj, error) in
                            //                                if let obj = foundObj {
                            //                                    var audioIDs: [String] = [String]()
                            //                                    for paudio in audios{
                            //                                        audioIDs.append(paudio.objectId!)
                            //                                    }
                            //                                    obj["audios"] = audioIDs
                            //                                    obj.saveInBackground {
                            //                                        (success: Bool, error: Error?) in
                            //                                        if (success) {
                            //                                            return completion(true)
                            //                                        } else {
                            //                                            // couldn't update observation
                            //                                            return completion(false)
                            //                                        }
                            //                                    }
                            //                                } else {
                            //                                    // couldnt upload videos
                            //                                    return completion(false)
                            //                                }
                            //                            })
                        } else {
                            // couldnt upload
                            return completion(false)
                        }
                    })
                } else {
                    // couldnt upload
                    return completion(false)
                }
            } else {
                // couldnt upload
                return completion(false)

            }
        }
    }

    func uploadVideos(for observation: PFObservation, observObj: PFObject, completion: @escaping (_ success: Bool) -> Void) {
        getVideosFor(observationID: observation.id!) { (success, pfvideos) in
            if success {
                if let count = pfvideos?.count {
                    let parseVideObjects: [PFObject] = [PFObject]()
                    self.recursiveVideoUpload(last: (count - 1), for: observation, observObj: observObj, parseVideoObjects: parseVideObjects, completion: { (done, videos) in
                        if done {
                            return completion(true)
                            //                            let query = PFQuery(className:"Observation")
                            //                            query.getObjectInBackground(withId: observObj.objectId!, block: { (foundObj, error) in
                            //                                if let obj = foundObj {
                            //                                    var videoIDs: [String] = [String]()
                            //                                    for pvideo in videos {
                            //                                        videoIDs.append(pvideo.objectId!)
                            //                                    }
                            //                                    obj["videos"] = videoIDs
                            //                                    obj.saveInBackground {
                            //                                        (success: Bool, error: Error?) in
                            //                                        if (success) {
                            //                                            return completion(true)
                            //                                        } else {
                            //                                            // couldnt update observation
                            //                                            return completion(false)
                            //                                        }
                            //                                    }
                            //                                } else {
                            //                                    // couldnt find observation
                            //                                    return completion(false)
                            //                                }
                            //                            })
                        } else {
                            // fail
                            // couldnt upload videos
                            return completion(false)
                        }
                    })
                } else {
                    // unlikely yo get here
                    return completion(false)
                }
            } else {
                // fail.
                // could npt find videos
                return completion(false)
            }
        }
    }

    func uploadPhotos(for observation: PFObservation, obsObj: PFObject, completion: @escaping (_ success: Bool) -> Void) {
        getPhotosFor(observationID: observation.id!) { (success, pfphotos) in
            if success {
                if let count = pfphotos?.count {
                    let parsePhotoObjects: [PFObject] = [PFObject]()
                    self.recursivePhotoUpload(last: (count - 1), for: observation, obsObj: obsObj, parsePhotoObjects: parsePhotoObjects, completion: { (done, photos) in
                        if done {
                            return completion(true)
                            //                            let query = PFQuery(className:"Observation")
                            //                            query.getObjectInBackground(withId: obsObj.objectId!, block: { (foundObj, error) in
                            //                                if let obj = foundObj {
                            //                                    var photoIDs: [String] = [String]()
                            //                                    for pphoto in photos {
                            //                                        photoIDs.append(pphoto.objectId!)
                            //                                    }
                            //                                    obj["photos"] = photoIDs
                            //                                    obj.saveInBackground {
                            //                                        (success: Bool, error: Error?) in
                            //                                        if (success) {
                            //                                            return completion(true)
                            //                                        } else {
                            //                                            // couldnt update observation
                            //                                            return completion(false)
                            //                                        }
                            //                                    }
                            //                                } else {
                            //                                    // couldnt find observation
                            //                                    return completion(false)
                            //                                }
                            //                            })
                        } else {
                            // fail
                            return completion(false)
                        }
                    })
                } else {
                    return completion(false)
                }
            } else {
                return completion(false)
            }
        }
    }

    func recursivePhotoUpload(last index: Int,for observation: PFObservation, obsObj: PFObject, parsePhotoObjects: [PFObject],completion: @escaping (_ done: Bool, _ photos: [PFObject]) -> Void) {
        if index > -1 {
            uploadPhoto(for: observation, obsObj: obsObj, at: index, completion: { (success, photoObject) in
                if success {
                    var objects = parsePhotoObjects
                    objects.append(photoObject!)

                    let nextIndex = index - 1
                    if nextIndex > -1 {
                        self.recursivePhotoUpload(last: nextIndex, for: observation, obsObj: obsObj, parsePhotoObjects: objects, completion: completion)
                    } else {
                        // done
                        completion(true, objects)
                    }
                } else {
                    completion(false, parsePhotoObjects)
                }
            })
        } else {
            // done
            completion(true, parsePhotoObjects)
        }
    }

    func getPhotoAt(observationID: String, at: Int, completion: @escaping (_ success: Bool, _ photos: PFPhoto? ) -> Void) {
        getPhotosFor(observationID: observationID) { (found, pfphotos) in
            if found {
                if (pfphotos?.count)! >= at {
                    return completion(true,  pfphotos?[at])
                } else {
                    return completion(false, nil)
                }
            }
        }
    }


    func uploadPhoto(for observation: PFObservation, obsObj: PFObject, at index: Int, completion: @escaping (_ success: Bool, _ pfObject: PFObject? ) -> Void) {
        let photo = PFObject(className: "Photo")
        getPhotoAt(observationID: observation.id!, at: index) { (found, pfphoto) in
            if !found {
                print("Not found")
                return completion(false, nil)
            }

            let observationId : String = pfphoto?.observationId ?? ""
            let caption       : String = pfphoto?.caption ?? ""
            let timestamp     : Date?   = pfphoto?.timestamp ?? nil
            let coordinate    : PFGeoPoint = pfphoto?.coordinate ?? PFGeoPoint()
            //            let index: Int = index
            let photoData = pfphoto?.get()
            if photoData == nil { return completion(false, nil)}

            print(photoData?.count)

            let parsePhotoFile = PFFile(name: "\(observationId)\(index).jpeg", data: photoData!)
            parsePhotoFile?.saveInBackground(block: { (success, error) -> Void in
                if success {
                    var picIndex = -1
                    if let indx =  pfphoto?.index {
                        picIndex = indx as! Int
                    }
                    photo["coordinate"] = coordinate
                    photo["caption"] = caption
                    photo["index"] = picIndex
                    photo["timestamp"] = timestamp
                    photo["photo"] = parsePhotoFile
                    photo["observation"] = obsObj
                    photo.saveInBackground(block: { (success, error) in
                        if success  {
                            return completion(true, photo)
                        } else {
                            return completion(false, nil)
                        }
                    })
                } else {
                    print(error)
                    return completion(false, nil)
                }
            })
        }
    }

    func getVideoFor(observationID: String, at: Int, completion: @escaping (_ success: Bool, _ video: PFVideo? ) -> Void) {
        guard let query = PFVideo.query() else {
            // fail
            return completion(false, nil)
        }

        let vidindex = at as NSNumber

        query.fromLocalDatastore()
        query.whereKey("observationId", equalTo: observationID)
        query.whereKey("index", equalTo: vidindex)
        query.findObjectsInBackground(block: { (videos, error) in
            guard let storedVideos = videos as? [PFVideo], error == nil else {
                // fail
                return completion(false, nil)
            }
            print(storedVideos.count)
            print(storedVideos)
            if storedVideos.first?.get() == nil{
                // fail
                print(storedVideos.first?.file)
                print(storedVideos.first?.getURL())
                print(storedVideos.first?.get())
                return completion(false, nil)
            }
            // success
            print(storedVideos.first?.getURL())
            print(storedVideos.first?.get())
            return completion(true, storedVideos.first)
        })
    }

    func getAudioFor(observationID: String, at: Int, completion: @escaping (_ success: Bool, _ audio: PFAudio? ) -> Void) {
        guard let query = PFAudio.query() else {
            // fail
            return completion(false, nil)
        }

        let audindex = at as NSNumber

        query.fromLocalDatastore()
        query.whereKey("observationId", equalTo: observationID)
        query.whereKey("index", equalTo: audindex)
        query.findObjectsInBackground(block: { (audios, error) in
            guard let storedAudios = audios as? [PFAudio], error == nil else {
                // fail
                return completion(false, nil)
            }
            // success
            return completion(true, storedAudios.first)
        })
    }

    func saveAudio(audioURL: URL, index: Int, observationID: String, inspectionID: String, notes: String, title: String, completion: @escaping (_ created: Bool) -> Void) {
        let audio = PFAudio()
        audio.id = "\(UUID().uuidString).mp4a"
        audio.observationId = observationID
        audio.index = index as NSNumber
        audio.inspectionId = inspectionID
        audio.notes = notes
        audio.title = title
        let data = NSData(contentsOf: audioURL)
        do {
            try data?.write(to: FileManager.directory.appendingPathComponent(audio.id!, isDirectory: true))
            audio.pinInBackground { (success, error) in
                if success && error == nil {
                    // success
                    return completion(true)
                } else {
                    // fail
                    return completion(false)
                }
            }
        } catch {
            // fail
            return completion(false)
        }
    }

    func getAudiosFor(observationID: String, completion: @escaping (_ success: Bool, _ audios: [PFAudio]? ) -> Void) {
        var foundAudios = [PFAudio]()
        guard let query = PFAudio.query() else {
            // fail
            return completion(false, nil)
        }

        query.fromLocalDatastore()
        query.whereKey("observationId", equalTo: observationID)
        query.findObjectsInBackground(block: { (audios, error) in
            guard let storedAudios = audios as? [PFAudio], error == nil else {
                // fail
                return completion(false, nil)
            }

            for audio in storedAudios {
                foundAudios.append(audio)
                //                if let id = audio.id{
                //                    let url = URL(fileURLWithPath: FileManager.directory.absoluteString).appendingPathComponent(id, isDirectory: true)
                //                    //                    audio.url = url
                //                    foundAudios.append(audio)
                //                }
            }
            print(foundAudios.count)
            // success
            return completion(true, foundAudios)
        })
    }

    func savePhoto(image: UIImage, index: Int, location: CLLocation?, observationID: String, description: String?, completion: @escaping (_ created: Bool) -> Void) {
        saveThumbnail(image: image, index: index, originalType: "photo", observationID: observationID, description: description) { (done) in
            if !done{ return completion (false)}

            self.saveFull(image: image, index: index, location: location, observationID: observationID, description: description) { (success) in
                if !success{ return completion (false)}

                return completion(true)
            }
        }
    }

    func saveFull(image: UIImage, index: Int, location: CLLocation?, observationID: String, description: String?, completion: @escaping (_ created: Bool) -> Void) {
        let photo = PFPhoto()
        photo.caption = description
        photo.observationId = observationID
        photo.id = "\(UUID().uuidString).jpeg"
        photo.timestamp = Date()
        photo.index = index as NSNumber
        photo.coordinate = PFGeoPoint(location: location)
        let data = image.toData(quality: .uncompressed)
        print("full size of \(index) is \(data.count)")
        do {
            try data.write(to: FileManager.directory.appendingPathComponent(photo.id!, isDirectory: true))
            photo.pinInBackground { (success, error) in
                if success && error == nil {
                    // success
                    return completion(true)
                } else {
                    // fail
                    return completion(false)
                }
            }
        } catch {
            // fail
            return completion(false)
        }
    }

    func saveThumbnail(image: UIImage, index: Int, originalType: String, observationID: String, description: String?, completion: @escaping (_ created: Bool) -> Void) {
        let data: Data = UIImageJPEGRepresentation(resizeImage(image: image), 0)!
        print("thumb size of \(index) is \(data.count)")
        let photo = PFPhotoThumb()
        photo.observationId = observationID
        photo.id = "\(UUID().uuidString).jpeg"
        photo.originalType = originalType
        photo.index = index as NSNumber
        do {
            try data.write(to: FileManager.directory.appendingPathComponent(photo.id!, isDirectory: true))
            photo.pinInBackground { (success, error) in
                if success && error == nil {
                    // success
                    return completion(true)
                } else {
                    // fail
                    return completion(false)
                }
            }
        } catch {
            // fail
            return completion(false)
        }
    }

    func getThumbnailFor(observationID: String, at: Int, completion: @escaping (_ success: Bool, _ photos: PFPhotoThumb? ) -> Void) {
        var foundPhotos = [PFPhotoThumb]()
        guard let query = PFPhotoThumb.query() else {
            // fail
            return completion(false, nil)
        }
        let photoindex = at as NSNumber

        query.fromLocalDatastore()
        query.whereKey("observationId", equalTo: observationID)
        query.whereKey("index", equalTo: photoindex)
        query.findObjectsInBackground(block: { (photos, error) in
            guard let storedPhotos = photos as? [PFPhotoThumb], error == nil else {
                // fail
                return completion(false, nil)
            }

            for photo in storedPhotos {
                if let id = photo.id{
                    let url = URL(fileURLWithPath: FileManager.directory.absoluteString).appendingPathComponent(id, isDirectory: true)
                    photo.image = UIImage(contentsOfFile: url.path)
                    foundPhotos.append(photo)
                }
            }
            print(foundPhotos.count)
            // success
            return completion(true, foundPhotos.first)
        })
    }

    func getPhotoFor(observationID: String, at: Int, completion: @escaping (_ success: Bool, _ photos: PFPhoto? ) -> Void) {
        var foundPhotos = [PFPhoto]()
        guard let query = PFPhoto.query() else {
            // fail
            return completion(false, nil)
        }
        let photoindex = at as NSNumber

        query.fromLocalDatastore()
        query.whereKey("observationId", equalTo: observationID)
        query.whereKey("index", equalTo: photoindex)
        query.findObjectsInBackground(block: { (photos, error) in
            guard let storedPhotos = photos as? [PFPhoto], error == nil else {
                // fail
                return completion(false, nil)
            }

            for photo in storedPhotos {
                if let id = photo.id{
                    let url = URL(fileURLWithPath: FileManager.directory.absoluteString).appendingPathComponent(id, isDirectory: true)
                    photo.image = UIImage(contentsOfFile: url.path)
                    foundPhotos.append(photo)
                }
            }
            print(foundPhotos.count)
            print(foundPhotos.last?.id)
            // success
            return completion(true, foundPhotos.first)
        })
    }

    func getThumbnailsFor(observationID: String, completion: @escaping (_ success: Bool, _ photos: [PFPhotoThumb]? ) -> Void) {
        var foundPhotos = [PFPhotoThumb]()
        guard let query = PFPhotoThumb.query() else {
            // fail
            return completion(false, nil)
        }

        query.fromLocalDatastore()
        query.whereKey("observationId", equalTo: observationID)
        query.findObjectsInBackground(block: { (photos, error) in
            guard let storedPhotos = photos as? [PFPhotoThumb], error == nil else {
                // fail
                return completion(false, nil)
            }

            for photo in storedPhotos {
                if let id = photo.id{
                    let url = URL(fileURLWithPath: FileManager.directory.absoluteString).appendingPathComponent(id, isDirectory: true)
                    photo.image = UIImage(contentsOfFile: url.path)
                    foundPhotos.append(photo)
                }
            }
            print(foundPhotos.count)
            // success
            return completion(true, foundPhotos)
        })
    }

    //    func getVideosFor(observationID: String, completion: @escaping (_ success: Bool, _ videos: [PFVideo]? ) -> Void) {
    //        guard let query = PFVideo.query() else {
    //            // fail
    //            return completion(false, nil)
    //        }
    //
    //        query.fromLocalDatastore()
    //        query.whereKey("observationId", equalTo: observationID)
    //        query.findObjectsInBackground(block: { (videos, error) in
    //            guard let storedVideos = videos as? [PFVideo], error == nil else {
    //                // fail
    //                return completion(false, nil)
    //            }
    //            // success
    //            return completion(true, storedVideos)
    //        })
    //    }

    func getPhotosFor(observationID: String, completion: @escaping (_ success: Bool, _ photos: [PFPhoto]? ) -> Void) {
        var foundPhotos = [PFPhoto]()
        guard let query = PFPhoto.query() else {
            // fail
            return completion(false, nil)
        }

        query.fromLocalDatastore()
        query.whereKey("observationId", equalTo: observationID)
        query.findObjectsInBackground(block: { (photos, error) in
            guard let storedPhotos = photos as? [PFPhoto], error == nil else {
                // fail
                return completion(false, nil)
            }

            for photo in storedPhotos {
                if let id = photo.id{
                    let url = URL(fileURLWithPath: FileManager.directory.absoluteString).appendingPathComponent(id, isDirectory: true)
                    photo.image = UIImage(contentsOfFile: url.path)
                    foundPhotos.append(photo)
                }
            }
            print(foundPhotos.count)
            // success
            return completion(true, foundPhotos)
        })
    }

    func resizeImage(image: UIImage) -> UIImage {
        var actualHeight: Float = Float(image.size.height)
        var actualWidth: Float = Float(image.size.width)
        let maxHeight: Float = 120.0
        let maxWidth: Float = 120.0
        var imgRatio: Float = actualWidth / actualHeight
        let maxRatio: Float = maxWidth / maxHeight
        let compressionQuality: Float = 0.25
        //50 percent compression

        if actualHeight > maxHeight || actualWidth > maxWidth {
            if imgRatio < maxRatio {
                //adjust width according to maxHeight
                imgRatio = maxHeight / actualHeight
                actualWidth = imgRatio * actualWidth
                actualHeight = maxHeight
            }
            else if imgRatio > maxRatio {
                //adjust height according to maxWidth
                imgRatio = maxWidth / actualWidth
                actualHeight = imgRatio * actualHeight
                actualWidth = maxWidth
            }
            else {
                actualHeight = maxHeight
                actualWidth = maxWidth
            }
        }

        let rect = CGRect(x: 0.0, y: 0.0, width: CGFloat(actualWidth), height: CGFloat(actualHeight))
        UIGraphicsBeginImageContext(rect.size)
        image.draw(in: rect)
        let img = UIGraphicsGetImageFromCurrentImageContext()
        let imageData = UIImageJPEGRepresentation(img!,CGFloat(compressionQuality))
        UIGraphicsEndImageContext()
        return UIImage(data: imageData!)!
    }

    func isUserMobileAccessEnabled(completion: @escaping (_ success: Bool) -> Void) {
        let user = PFUser.current()
        if user != nil, let id = user?.objectId {
            let query: PFQuery = PFUser.query()!
            query.getObjectInBackground(withId: id) { (userObj, error) in
                if let obj = userObj,
                    let access: [String: Any] = obj["access"] as? [String : Any],
                    let mobileAccess: Bool = access["mobileAccess"] as? Bool,
                    let isActive: Bool = obj["isActive"] as? Bool {
                    print(access)
                    if mobileAccess && isActive {
                        return completion(true)
                    } else {
                        return completion(false)
                    }
                } else {
                    return completion(false)
                }
            }
        } else {
            return completion(false)
        }
    }

    func getUserTeams(user: User, completion: @escaping (_ success: Bool,_ teams: [PFObject]) -> Void) {
        let query = PFQuery(className: "Team")
//        query.findObjectsInBackground { (objects, error) in
//            print(objects)
//        }
        var downloadedTeams = [PFObject]()
        query.whereKey("users", equalTo: user)
        query.findObjectsInBackground { (teams, error) in
            print(teams)
            print("****")
            if let foundTeams: [PFObject] = teams {
                for team in foundTeams {
                    downloadedTeams.append(team)
                    team.pinInBackground()
                }
                return completion(true, downloadedTeams)
            }
            else {
                return completion(false, downloadedTeams)
            }
        }
    }

    func getTeams(completion: @escaping (_ success: Bool, _ teams: [Team]?) -> Void) {
        let user: User =  PFUser.current() as! User
        self.getUserTeams(user: user) { (done, downloaded)  in
            if done {
                var results = [Team]()
                for object: PFObject in downloaded {
                    results.append(Team(objectID: object.objectId!, name: (object["name"] as? String)!, isActive: (object["isActive"] as? Bool)!))
                }
                return completion(true, results)
            } else {
                let query = PFQuery(className: "Team")
                query.fromLocalDatastore()
                query.findObjectsInBackground { (objects, error) in
                    if objects != nil  {
                        var r = [Team]()
                        for object: PFObject in objects! {
                            r.append(Team(objectID: object.objectId!, name: (object["name"] as? String)!, isActive: (object["isActive"] as? Bool)!))
                        }
                        completion(true, r)
                    } else {
                        return completion(false, nil)
                    }
                }
            }
        }
    }
}
