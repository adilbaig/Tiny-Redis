module collections.set;

import tinyredis.redis;

/**
  Set 
  A class that represents a SET structure in redis. 
  Allows you to query and manipulate the set using methods.  
  Implements OutputRange.

  NOTE: Operations are done on the server side as much as possible, to reflect the true state of
  the collection.
*/
class Set
{
	private :
		string name;
		Redis conn;
		
	public :
	
	this(Redis conn, string name)
	{
		this.conn = conn;
		this.name = name;
	}
	
	Response smembers()
	{
	    return conn.send("SMEMBERS", name);
	}
	
	int scard()
    {
        return conn.send!(int)("SCARD", name);
    }
    alias count = scard;
    
    
    bool srem(const(char[]) value)
    {
        return conn.send!(bool)("SREM", name, value);
    }
    
    void del()
    {
        conn.send("DEL", name);
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
        del();
        put(value);
    }
    
    void opAssign(const(char[])[] values)
    {
        del();
        put(values);
    }

    void opOpAssign(string op)(const(char[]) value)
    {
        static if (op == "~")
            put(value);
        else static if (op == "-")
            srem(value);
        else 
            static assert(0, "Operator "~op~" not implemented");
    }
    
    void opOpAssign(string op)(const(char[])[] values)
    {
        static if (op == "~")
            foreach(value; values)
                put(value);
        else static if (op == "-")
            foreach(value; values)
                srem(value);
        else 
            static assert(0, "Operator "~op~" not implemented");
    }
	
}

unittest {
    
    import std.range.primitives : isOutputRange;
    assert(isOutputRange!(Set, string));
    
    auto conn = new Redis("localhost", 6379);
    auto set  = new Set(conn, "tinyRedisUnitTestSet");
    
    set = ["banana", "apple", "orange"]; // data can be assigned using opAssign
    set.put("grapes"); //the put() function appends a value
     
    assert(set.scard() == 4); // runs the SCARD command, presents a proper count of the set on the server
    assert(set.count() == 4); // count is an alias for SCARD command
    
    //opAssign resets the data
    set = ["guava", "pear"];
    assert(set.scard() == 2);
    
    set ~= "banana"; // implements opOpAssign so ~= appends data
    set ~= "apple";
    set ~= ["orange", "mango"];
    set ~= "apple"; //DUPLICATE!
    assert(set.count() == 6);
    
    set -= "mango"; //Not mango season!
    assert(set.count() == 5);
    
    import std.algorithm.searching : canFind;
    foreach(fruit; set.smembers())
        assert(["guava", "pear", "banana", "apple", "orange"].canFind(fruit.toString));
    
}