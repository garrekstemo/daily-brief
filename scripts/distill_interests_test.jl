using Test
include(joinpath(@__DIR__, "distill_interests.jl"))

@testset "url_hash parity with brief-routine.md" begin
    @test url_hash("https://www.example.com/Foo/Bar/") ==
        "e54b9d6f8b4f9ceb3b709a2c5a0cd1da7d7057edb8ce04ea8f0f5fa02af61a31"
    @test url_hash("HTTP://Example.com/a?b=1#frag") ==
        "036cbe16b0015b0a30d733ca981c8ebb80535abe46b862bbb67d0affb9331be7"
    @test url_hash("https://nautil.us/") ==
        "c726d0edc78fe9aeaebc268a06469f3765ed845375543dbff8818ee55eeeeaf6"
    @test url_hash("https://www.MarginalRevolution.com") ==
        "127f69b4e3b0315ae231525be9f24c31fff9d267a16d98a43d0a0721e61f9002"
    @test url_hash("https://example.com/a") == url_hash("HTTP://Example.com/a?b=1#frag")
end
