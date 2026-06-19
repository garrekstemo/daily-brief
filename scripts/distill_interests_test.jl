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

@testset "read_links from fixture db (excludes deleted)" begin
    db = tempname() * ".sqlite"
    run(pipeline(`sqlite3 $db`, stdin = IOBuffer("""
    CREATE TABLE link (url TEXT, title TEXT, author TEXT, starred BOOLEAN NOT NULL,
                       readAt DOUBLE NOT NULL, deletedAt DOUBLE NOT NULL DEFAULT 0);
    INSERT INTO link VALUES ('https://example.com/a','Alpha','',0,100.0,0);
    INSERT INTO link VALUES ('https://www.example.org/b/','Bravo','',1,0.0,0);
    INSERT INTO link VALUES ('http://test.com/c?x=1','Charlie','',0,200.0,0);
    INSERT INTO link VALUES ('https://gone.com/x','Deleted','',0,300.0,5.0);
    """)))
    rows = read_links(db)
    @test length(rows) == 3
    @test Set(r.url for r in rows) ==
        Set(["https://example.com/a","https://www.example.org/b/","http://test.com/c?x=1"])
    @test any(r -> r.starred && r.title == "Bravo", rows)
    rm(db, force = true)
end
