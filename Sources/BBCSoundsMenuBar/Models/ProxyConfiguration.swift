import Foundation

struct ProxyConfiguration {
    let host: String
    let port: Int
    let user: String
    let pass: String
    let skipVerify: Bool
    
    var urlString: String {
        "https://\(user):\(pass)@\(host):\(port)"
    }
}
