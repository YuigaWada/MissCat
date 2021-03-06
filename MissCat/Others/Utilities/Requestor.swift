//
//  UrlSummalyEntity.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/08/01.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation

internal typealias ResponseCallBack = (HTTPURLResponse?, String?) -> Void
internal enum Requestor {
    private static let boundary = UUID().uuidString
    
    // MARK: GET
    
    static func get(url: String, completion: @escaping ResponseCallBack) {
        get(url: URL(string: url)!, completion: completion)
    }
    
    static func get(url: URL, completion: @escaping ResponseCallBack) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let _ = error {
                completion(nil, nil)
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(nil, nil)
                return
            }
            
            if let data = data, let dataString = String(data: data, encoding: .utf8) {
                completion(response, dataString)
            }
        }
        task.resume()
    }
    
    // MARK: POST
    
    // With Attachment
    static func post(url: String, paramsDic: [String: Any], data: Data?, fileType: String?, completion: @escaping ResponseCallBack) {
        post(url: URL(string: url)!,
             paramsDic: paramsDic,
             data: data,
             fileType: fileType,
             completion: completion)
    }
    
    // Generate a "multipart/form-data" request
    static func post(url: URL, paramsDic: [String: Any], data: Data?, fileType: String?, completion: @escaping ResponseCallBack) {
        guard let data = data, let fileType = fileType else { completion(nil, nil); return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let uuid = UUID().uuidString
        var bodyData = Data()
        
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        paramsDic.forEach { params in
            let value = String(describing: params.value)
            
            bodyData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"\(params.key)\"\r\n\r\n".data(using: .utf8)!)
            bodyData.append(value.data(using: .utf8)!)
        }
        
        bodyData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(uuid)\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: \(fileType)\r\n\r\n".data(using: .utf8)!)
        bodyData.append(data)
        
        bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = bodyData
        
        let task = session.dataTask(with: request) { data, response, error in
            if let _ = error {
                completion(nil, nil)
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(nil, nil)
                return
            }
            
            if let data = data, let dataString = String(data: data, encoding: .utf8) {
                completion(response, dataString)
            }
        }
        task.resume()
    }
    
    // Without attachment
    static func post(url: String, rawJson: String, completion: @escaping ResponseCallBack) {
        post(url: URL(string: url)!,
             rawJson: rawJson,
             completion: completion)
    }
    
    static func post(url: URL, rawJson: String, completion: @escaping ResponseCallBack) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = rawJson.data(using: .utf8)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let _ = error {
                completion(nil, nil)
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(nil, nil)
                return
            }
            
            if let data = data, let dataString = String(data: data, encoding: .utf8) {
                completion(response, dataString)
            }
        }
        task.resume()
    }
}
