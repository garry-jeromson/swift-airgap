import Testing

/// All Swift Testing integration tests are nested under a single serialized parent suite
/// because Airgap uses static state (violationHandler, isActive) that would race
/// if child suites ran in parallel.
#if swift(>=6.1)
@Suite(.serialized, .scopeLocked)
struct AllAirgapSwiftTestingTests {}
#else
@Suite(.serialized)
struct AllAirgapSwiftTestingTests {}
#endif
