module collections;

import std.range, 
       std.algorithm,
       tinyredis.redis,
	   tinyredis.parser;

/*
  Implements InputRange, OutputRange.

  Operations should be done on the server side as much as possible, to reflect the true state of
  the collection on the server.
*/

class SortedSet
{
    
}

class List{}
class Hash{}

unittest {
    
    assert(isInputRange!(Set));
    assert(isOutputRange!(Set, string));
    
    auto conn = new Redis("localhost", 6379);
    auto set = new Set(conn, "tinyRedisUnitTestSet");
    auto data = ["banana", "apple", "orange"];
    set = data;
    set.put("grapes");
    assert(set.scard() == 4);
    
    //opAssign resets the data
    set = ["adil", "baig"];
    assert(set.scard() == 2);
    set ~= "banana";
    set ~= "apple";
    set ~= ["orange", "mango"];
    assert(set.scard() == 6);
    
    set = data;
    foreach(s; set)
        assert(!std.algorithm.find(data, cast(string)s).empty);
    
    assert(set.empty());
    set.reset();
    assert(!set.empty());
    assert(set.scard() == 3);
}