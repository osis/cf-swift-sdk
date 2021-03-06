import Foundation
import Alamofire
import ObjectMapper

public enum CFRequest: URLRequestConvertible {
    case info(String)
    case tokenGrant(String, String, String)
    case tokenRefresh(String, String)
    case orgs()
    case apps(String, Int, String)
    case appSummary(String)
    case appStats(String)
    case appUpdate(String, [String:String])
    //TODO: case spaces(String) // Spaces for org
    case appSpaces([String])
    case events(String)
    case recentLogs(String)
    
    var baseURLString: String {
        switch self {
        case .tokenGrant(let url, _, _),
             .tokenRefresh(let url, _),
             .info(let url):
            return url
        case .recentLogs(_):
            if let endpoint = CFApi.session?.info.dopplerLoggingEndpoint {
                if var components = URLComponents(string: endpoint) {
                    components.scheme = "https"
                    return components.string!
                }
            }
            return ""
        default:
            return CFApi.session!.target
        }
    }
    
    var path: String {
        switch self {
        case .info:
            return "/v2/info"
        case .tokenGrant,
             .tokenRefresh:
            return "/oauth/token"
        case .orgs:
            return "/v2/organizations"
        case .apps:
            return "/v2/apps"
        case .appSummary(let guid):
            return "/v2/apps/\(guid)/summary"
        case .appStats(let guid):
            return "/v2/apps/\(guid)/stats"
        case .appUpdate(let guid, _):
            return "/v2/apps/\(guid)"
        case .appSpaces:
            return "/v2/spaces"
        case .events:
            return "/v2/events"
        case .recentLogs(let guid):
            return "/apps/\(guid)/recentlogs"
        }
    }
    
    var keypath: String? {
        switch self {
        case .apps, .orgs, .appSpaces, .events:
            return "resources"
        default:
            return nil
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .tokenGrant, .tokenRefresh:
            return .post
        case .appUpdate(_, _):
            return .put
        default:
            return .get
        }
    }
    
    public func asURLRequest() throws -> URLRequest {
        switch self {
        case .tokenGrant(_, let username, let password):
            let loginParams = ["grant_type": "password", "username": username, "password": password, "scope": ""]
            return tokenURLRequest(params: loginParams)
        case .tokenRefresh(_, let refreshToken):
            let refreshParams = ["grant_type": "refresh_token", "refresh_token": refreshToken ]
            return tokenURLRequest(params: refreshParams)
        case .apps(let orgGuid, let page, let searchText):
            return appsURLRequest(orgGuid, page: page, searchText: searchText) as URLRequest
        case .appUpdate(let guid, let params):
            return appUpdateRequest(guid, params: params) as URLRequest
        case .appSpaces(let appGuids):
            return spacesURLRequest(appGuids) as URLRequest
        case .events(let appGuid):
            return eventsURLRequest(appGuid) as URLRequest
        default:
            return cfURLRequest()
        }
    }
    
    func cfURLRequest() -> URLRequest {
        let URL = Foundation.URL(string: baseURLString)!
        var mutableURLRequest = URLRequest(url: URL.appendingPathComponent(path))
        
        mutableURLRequest.httpMethod = method.rawValue
        
        if let token = CFApi.session?.accessToken {
            mutableURLRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return mutableURLRequest
    }
    
    func tokenURLRequest(params: [String : String]) -> URLRequest {
        var urlRequest = cfURLRequest()

        urlRequest.setValue("Basic \(CFSession.loginAuthToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        urlRequest = try! URLEncoding.default.encode(urlRequest, with: params)
        return urlRequest
    }
    
    func appsURLRequest(_ orgGuid: String, page: Int, searchText: String) -> NSMutableURLRequest{
        let mutableURLRequest = cfURLRequest()
        var appsParams: [String : Any] = [
            "order-direction": "desc",
            "q": ["organization_guid:\(orgGuid)"],
            "results-per-page": "25",
            "page": page
        ]
        
        if !searchText.isEmpty {
            var queries = appsParams["q"] as! [String]
            queries.append("name>=\(searchText)")
            queries.append("name<=\(searchText.bumpLastChar())")
            appsParams["q"] = queries
        }
        
        var request = try! URLEncoding.default.encode(mutableURLRequest, with: appsParams)
        
        if let query = request.url?.query {
            var URLComponents = Foundation.URLComponents(url: mutableURLRequest.url!, resolvingAgainstBaseURL: false)
            let trimmedQuery = query.replacingOccurrences(of: "%5B%5D", with: "")
            
            URLComponents?.percentEncodedQuery =  trimmedQuery
            request.url = URLComponents?.url
        }
        
        return request as! NSMutableURLRequest
    }
    
    func appUpdateRequest(_ appGuid: String, params: [String:String]) -> URLRequest {
        var mutableURLRequest = cfURLRequest()
        mutableURLRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return try! Alamofire.JSONEncoding.default.encode(mutableURLRequest, with: params)
    }
    
    func spacesURLRequest(_ appGuids: [String]) -> NSMutableURLRequest {
        let mutableURLRequest = cfURLRequest()
        let guidString = appGuids.joined(separator: ",")
        let spacesParams: [String : AnyObject] = [
            "q": "app_guid IN \(guidString)" as AnyObject,
            "results-per-page": "50" as AnyObject
        ]
        
        return try! URLEncoding.default.encode(mutableURLRequest as URLRequestConvertible, with: spacesParams) as! NSMutableURLRequest
    }
    
    func eventsURLRequest(_ appGuid: String) -> NSMutableURLRequest {
        let mutableURLRequest = cfURLRequest()
        let eventParams: [String : AnyObject] = [
            "order-direction": "desc" as AnyObject,
            "q": "actee:\(appGuid)" as AnyObject,
            "results-per-page": "50" as AnyObject
        ]
        
        return try! URLEncoding.default.encode(mutableURLRequest, with: eventParams) as! NSMutableURLRequest
    }
}
