import Testing

#if swift(>=6.1)
@Suite(.serialized, .scopeLocked)
struct AllAirgapUnitTests {}
#else
@Suite(.serialized)
struct AllAirgapUnitTests {}
#endif
