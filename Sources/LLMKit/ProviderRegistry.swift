import DaybriefCore
import Foundation

/// Maps a ``Provider`` + ``ProviderConfig`` to a concrete ``ModelAdapter``.
///
/// The registry holds the injected transports so the app constructs one registry
/// and asks it for adapters as the user's provider/model selection changes
/// (design §8). Adapters differ in endpoint, auth header, body shape,
/// structured-output mechanism, and stream framing — the registry keeps those
/// differences isolated per adapter.
public struct ProviderRegistry: Sendable {
    private let transport: any HTTPTransport
    private let streamingTransport: any StreamingHTTPTransport
    private let attribution: OpenRouterAttribution?

    /// Creates a registry over the given transports.
    ///
    /// - Parameters:
    ///   - transport: The buffered HTTP seam (defaults to ``DaybriefCore/URLSessionHTTPTransport``).
    ///   - streamingTransport: The streaming seam (defaults to ``URLSessionStreamingTransport``).
    ///   - attribution: Optional OpenRouter app-attribution headers.
    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        streamingTransport: any StreamingHTTPTransport = URLSessionStreamingTransport(),
        attribution: OpenRouterAttribution? = nil
    ) {
        self.transport = transport
        self.streamingTransport = streamingTransport
        self.attribution = attribution
    }

    /// Builds the adapter for `provider` configured by `config`.
    ///
    /// Throws ``LLMError/missingAPIKey(provider:)`` when a key-requiring provider
    /// has no key, or ``LLMError/invalidBaseURL(provider:)`` if a needed base URL
    /// can't be resolved.
    public func makeAdapter(_ provider: Provider, config: ProviderConfig) throws -> any ModelAdapter {
        if provider.requiresAPIKey {
            guard let key = config.apiKey, !key.isEmpty else {
                throw LLMError.missingAPIKey(provider: provider.rawValue)
            }
            return try makeKeyedAdapter(provider, config: config, apiKey: key)
        }
        // Ollama (keyless).
        let baseURL = config.baseURL ?? OllamaAdapter.defaultBaseURL
        return OllamaAdapter(
            baseURL: baseURL,
            defaultModel: config.defaultModel,
            transport: transport,
            streamingTransport: streamingTransport
        )
    }

    private func makeKeyedAdapter(
        _ provider: Provider,
        config: ProviderConfig,
        apiKey: String
    ) throws -> any ModelAdapter {
        switch provider {
        case .openRouter:
            return OpenRouterAdapter(
                apiKey: apiKey,
                baseURL: config.baseURL ?? OpenRouterAdapter.defaultBaseURL,
                defaultModel: config.defaultModel,
                attribution: attribution,
                transport: transport,
                streamingTransport: streamingTransport
            )
        case .openAI:
            return OpenAIAdapter(
                apiKey: apiKey,
                baseURL: config.baseURL ?? OpenAIAdapter.defaultBaseURL,
                defaultModel: config.defaultModel,
                transport: transport,
                streamingTransport: streamingTransport
            )
        case .anthropic:
            return AnthropicAdapter(
                apiKey: apiKey,
                baseURL: config.baseURL ?? AnthropicAdapter.defaultBaseURL,
                defaultModel: config.defaultModel,
                transport: transport,
                streamingTransport: streamingTransport
            )
        case .gemini:
            return GeminiAdapter(
                apiKey: apiKey,
                baseURL: config.baseURL ?? GeminiAdapter.defaultBaseURL,
                defaultModel: config.defaultModel,
                transport: transport,
                streamingTransport: streamingTransport
            )
        case .ollama:
            // Keyless; handled in makeAdapter. Defensive fall-through.
            throw LLMError.missingAPIKey(provider: provider.rawValue)
        }
    }
}

/// OpenRouter app-attribution headers (`HTTP-Referer` + `X-Title`).
///
/// `HTTP-Referer` is the load-bearing header for OpenRouter's app ranking page;
/// `X-Title` alone does nothing. Both are optional for functionality (design §8).
public struct OpenRouterAttribution: Sendable, Equatable {
    /// A stable identifier URL (e.g. the project's repo URL).
    public let referer: String
    /// A display title (e.g. `"Daybrief"`).
    public let title: String

    /// Creates attribution headers.
    public init(referer: String, title: String) {
        self.referer = referer
        self.title = title
    }
}
