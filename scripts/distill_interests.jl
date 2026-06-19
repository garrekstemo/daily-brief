using SHA

function url_hash(u::AbstractString)
    s = strip(u)
    s = replace(s, r"^https?://"i => "")
    s = first(split(s, '#'; limit=2))
    s = first(split(s, '?'; limit=2))
    parts = split(s, '/'; limit=2)
    host = parts[1]
    path = length(parts) > 1 ? parts[2] : ""
    host = replace(lowercase(host), r"^www\." => "")
    path = rstrip(path, '/')
    norm = isempty(path) ? host : host * "/" * path
    return bytes2hex(sha256(String(norm)))
end

function default_db()
    joinpath(homedir(), "Library", "Group Containers",
             "group.com.ngocluu.goodlinks", "Data", "data.sqlite")
end

function read_links(db_path::AbstractString)
    isfile(db_path) || error("GoodLinks DB not found at $db_path")
    uri = "file:$db_path?mode=ro&immutable=1"
    clean(col) = "replace(replace(replace(coalesce($col,''),char(9),' '),char(10),' '),char(13),' ')"
    cols = join(["url", clean("title"), clean("author"), "starred", "readAt"], ", ")
    sql = "SELECT $cols FROM link WHERE deletedAt = 0 ORDER BY readAt DESC;"
    out = read(`sqlite3 -separator $("\t") $uri $sql`, String)
    rows = NamedTuple[]
    for line in split(chomp(out), '\n')
        isempty(line) && continue
        c = split(line, '\t')
        length(c) < 5 && continue
        push!(rows, (url = String(c[1]), title = String(c[2]), author = String(c[3]),
                     starred = c[4] == "1", readAt = parse(Float64, c[5])))
    end
    return rows
end
