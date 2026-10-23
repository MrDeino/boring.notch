import Foundation

func runQuickCtxTests() {
    let d = JSONDecoder()
    func ctx(_ j: String) -> ChatContext? { (try! d.decode(ChatResponse.self, from: Data(#"{"running":true,"context":\#(j)}"#.utf8))).context }
    let t = Date(timeIntervalSince1970: 1_700_000_000)

    let full = contextReading(ctx(#"{"percent":23,"tokens":230000,"window":1000000}"#), at: t)!
    precondition(full == ContextReading(percent: 23, tokens: 230_000, window: 1_000_000, at: t))
    // percent missing: derived from tokens/window; negative percent counts as unknown
    precondition(contextReading(ctx(#"{"tokens":152000,"window":200000}"#), at: t)?.percent == 76)
    precondition(contextReading(ctx(#"{"percent":-1,"tokens":50,"window":100}"#), at: t)?.percent == 50)
    precondition(contextReading(ctx(#"{"percent":-1}"#), at: t) == nil)
    precondition(contextReading(ctx("{}"), at: t) == nil && contextReading(nil, at: t) == nil)
    precondition(contextReading(ctx(#"{"tokens":5,"window":0}"#), at: t) == nil)
    // wrong-typed fields never fail the decode
    precondition(contextReading(ctx(#"{"percent":"x","tokens":1,"window":4}"#), at: t)?.percent == 25)
    precondition(contextReading(ctx(#"{"percent":12}"#), at: t)?.tokens == nil)

    precondition(contextTokensLabel(tokens: 230_000, window: 1_000_000) == "230k / 1M")
    precondition(contextTokensLabel(tokens: 152_400, window: 200_000) == "152k / 200k")
    precondition(contextTokensLabel(tokens: 900, window: 1_500_000) == "900 / 1.5M")
    precondition(contextTokensLabel(tokens: nil, window: 200_000) == nil && contextTokensLabel(tokens: 1, window: nil) == nil)
}
