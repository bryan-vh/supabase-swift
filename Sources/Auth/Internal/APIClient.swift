import Foundation
@_spi(Internal) import _Helpers

struct APIClient: Sendable {
  var execute: @Sendable (_ request: Request) async throws -> Response
}

extension APIClient {
  static func live(http: HTTPClient) -> Self {
    var configuration: AuthClient.Configuration {
      Dependencies.current.value!.configuration
    }

    return APIClient(
      execute: { request in
        var request = request
        request.headers.merge(configuration.headers) { r, _ in r }

        let response = try await http.fetch(request, baseURL: configuration.url)

        guard (200 ..< 300).contains(response.statusCode) else {
          if let apiError = try? configuration.decoder.decode(
            AuthError.APIError.self,
            from: response.data
          ) {
            throw AuthError.api(apiError)
          }

          /// There are some GoTrue endpoints that can return a `PostgrestError`, for example the
          /// ``AuthAdmin/deleteUser(id:shouldSoftDelete:)`` that could return an error in case the
          /// user is referenced by other schemas.
          let postgrestError = try configuration.decoder.decode(
            PostgrestError.self,
            from: response.data
          )
          throw postgrestError
        }

        return response
      }
    )
  }
}

extension APIClient {
  @discardableResult
  func authorizedExecute(_ request: Request) async throws -> Response {
    let session = try await Dependencies.current.value!.sessionManager.session()

    var request = request
    request.headers["Authorization"] = "Bearer \(session.accessToken)"

    return try await execute(request)
  }
}
