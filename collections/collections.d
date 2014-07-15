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
class Set
{
	private :
		string name;
		Redis conn;
		
		//Loading members
		uint ctr = 0;
		int total = -1;
		Response _members;
		bool loaded;
		
	public :
	
	this(Redis conn, const(char[]) name)
	{
		this.conn = conn;
		this.name = cast(string)name;
	}
	
	Response smembers()
	{
	    return conn.send("SMEMBERS", name);
	}
	
	int scard()
    {
        return conn.send!(int)("SCARD", name);
    }
    
    bool srem(const(char[]) value)
    {
        return conn.send!(bool)("SREM", name, value);
    }
	
	// OutputRange
	void put(const(char[]) value)
	{
		conn.send("SADD", name, value);
	}
	
	void put(const(char[])[] values)
    {
        foreach(value; values)
            conn.send("SADD", name, value);
    }
    
    void opAssign(const(char[]) value)
    {
        conn.send("DEL", name);
        put(value);
    }
    
    void opAssign(const(char[])[] values)
    {
        conn.send("DEL", name);
        put(values);
    }

    void opOpAssign(string op)(const(char[]) value)
    {
        static if (op == "~") {
            put(value);
        } else static if (op == "-")
            srem(value);
        else 
            static assert(0, "Operator "~op~" not implemented");
    }
    
    void opOpAssign(string op)(const(char[])[] values)
    {
        static if (op == "~") {
            foreach(value; values)
                put(value);
        } else static if (op == "-")
            foreach(value; values)
                srem(value);
        else 
            static assert(0, "Operator "~op~" not implemented");
    }
	
	void reset()
	{
	    total = scard();
	    ctr = 0;
	    loaded = true;
	}
	
	// InputRange
	Response front()
	{
	    if(!loaded)
	    {
	        load();
	        loaded = true;
	    }
	    
	    return _members.values[ctr];
	}
	
	void popFront()
    {
        if(ctr < _members.values.length)
            ctr++;
    }

	bool empty()
	{
	    if(total == -1)
	        total = scard();
	        
	    return !(ctr < total);
	}
	
	private void load()
	{
	    _members = smembers();
	}
}

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