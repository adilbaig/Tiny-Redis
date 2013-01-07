Tiny Redis
==========
Redis driver for the D programming language. TinyRedis is fast, simple, intuitive, feature complete, unit-tested, forward compatible, has no dependencies and makes working with Redis trivial.

It supports all of Redis's data types; keys, hashes, lists and sets. It also has simple functions for pipelining and transactions.

Read more : [adilbaig.github.com/Tiny-Redis](http://adilbaig.github.com/Tiny-Redis)

Changelog
---------

v1.2.1 (2012-12-09)
-----------------
- improved encoder. EVAL works!
- improved documentation per DDOC

v1.2 (2012-12-09)
- Response struct now supports opCast. Casts to bool, byte, short, int, long & string.
- send template now allow's casting of Response based on Response.type.
- helper functions for Response struct : isInt, isString, isArray and others.
- opApply overloaded for Response struct. Allows looping Response in a foreach loop.
- handling ConvOverflowException when conv. string to int.
- Response.intval is now a long.
- more unit tests.
- other minor bug fixes.
- example.d rewritten per new features.

Adil Baig
<br />Blog : [adilbaig.posterous.com](http://adilbaig.posterous.com)
<br />Twitter : [@aidezigns](http://twitter.com/aidezigns)
