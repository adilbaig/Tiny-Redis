Changelog
=========

v1.2.1 (2013-01-08)
-----------------
- improved encoder. EVAL works!
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
