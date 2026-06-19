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
