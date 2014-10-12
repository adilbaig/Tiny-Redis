Changelog
=========

v2.0.2 (2014-10-12)
-------------------
This is a minor bug fix and feature release.

- Minor changes were made to the encoder. The templated forms of the encoder now
    bypass the single string version. This makes encoding faster, as the single string version checks the 
    entire length of the string for escape sequences. LUA sequences don't need to be especially escaped 
    (unless passed to the single string version). Thanks to a bug report by @arjunadeltoso .
- Response struct now works with foreach_reverse.
- Response struct is now a BiDirectionalRange.
- Benchmark script now correctly reports the reqs/s.
- Minor bug fixes.    

The response struct is now a BiDirectionalRange, and supports opApply in reverse mode.

v2.0.1 (2014-09-19)
-------------------
Fix dub.json importPath. Now the first official release with DUB support. Fix by @rnakano

v2.0.0 (2014-08-28)
-------------------
This is a major release with lots of rewriting underneath the public interfaces. The goal of this release
was to reduce allocations and further split out functionality into different modules, while maintaining 
backwards compatibility with the public interfaces. The results are as follows :

- The encoder has been split into it's own namespace. Various templated functions were added, and the
	request struct has been removed. std.array.appender is used more often. Unit-tests have been maintained
	and the encoder fully passes all previous tests.
- The parser remains as is.
- The response struct is unchanged.
- The connection class has been removed in favor of a couple of functions used with UFCS.
- The redis class brings together the rest of the namespaces.

The benchmarking script has been slightly altered to mimic redis-benchmark. 

v1.2.4 (2014-05-24)
-------------------
- Minor bug fix
 
v1.2.3 (2013-08-25)
-------------------
- Added a new 'Request' struct. Allows RedisConnection.request to accurately predict number of responses.
- Moved folders around.
- Deleted downloads folder. May use github's "Attach binaries to release" feature in the future.
- Updated unittests

v1.2.2 (2013-01-20)
-------------------
- pipeline bug fix

v1.2.1 (2013-01-14)
-------------------
- improved encoder. EVAL works!
- added a new eval template.
- improved documentation per DDOC

v1.2 (2012-12-09)
-----------------
- Response struct now supports opCast. Casts to bool, byte, short, int, long & string.
- send template now allow's casting of Response based on Response.type.
- helper functions for Response struct : isInt, isString, isArray and others.
- opApply overloaded for Response struct. Allows looping Response in a foreach loop.
- handling ConvOverflowException when conv. string to int.
- Response.intval is now a long.
- more unit tests.
- other minor bug fixes.
- example.d rewritten per new features.

v1.1
-----------------
- factored out Redis into class and blocking client
- decoder factored out
- more unit tests

v1.0
-----------------
- stable working driver
