# My Notes:
For this challenge, I used `zig (0.13)` and it seemed to work with no issues.

I attempted to focuse on using the built in http.server library, This seemed to do well and I didn't see any issues.

One issue I had when testing with concurrent connections, It would sometimes fail on the codecrafters side. 
This could simply be because my code didn't work properly or just an inherit bug when using zig, or specifically zig v0.13

By no means was this an "optimal" or the most efficient soluction, but it does work and has passed their tests.


[![progress-banner](https://backend.codecrafters.io/progress/http-server/c025957b-be48-497f-bb72-b0ad03139f99)](https://app.codecrafters.io/users/codecrafters-bot?r=2qF)

This is a starting point for Zig solutions to the
["Build Your Own HTTP server" Challenge](https://app.codecrafters.io/courses/http-server/overview).

[HTTP](https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol) is the
protocol that powers the web. In this challenge, you'll build a HTTP/1.1 server
that is capable of serving multiple clients.

Along the way you'll learn about TCP servers,
[HTTP request syntax](https://www.w3.org/Protocols/rfc2616/rfc2616-sec5.html),
and more.

**Note**: If you're viewing this repo on GitHub, head over to
[codecrafters.io](https://codecrafters.io) to try the challenge.

