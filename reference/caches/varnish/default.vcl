vcl 4.1;

# Varnish in front of the reference origin, which runs on the host.
#
# This file changes one thing. Varnish's built-in rules pass every
# request that carries a cookie to the origin without a lookup, so a
# visitor with a session is never served from the cache. `vcl_recv`
# below looks the request up anyway, which is what a site does when it
# wants its pages cached for visitors who have a session. Everything
# else is Varnish as shipped: how `vary` selects a stored response, and
# its refusal to store a response that sets a cookie.

backend default {
    .host = "host.docker.internal";
    .port = "4010";
}

sub vcl_recv {
    if (req.method == "GET" || req.method == "HEAD") {
        return (hash);
    }
}

sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
}
