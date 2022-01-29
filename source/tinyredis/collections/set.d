module tinyredis.collections.set;

import tinyredis : Redis, Response;

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
	private {
		Redis conn;
		string name;
	}

	this(Redis conn, string name)
	{
		this.conn = conn;
		this.name = name;
	}
	
	auto smembers()
	{
		return conn.send("SMEMBERS", name);
	}
	
	int scard()
	{
		return conn.send!int("SCARD", name);
	}
	alias count = scard;
	
	
	int srem(const(char[])[] values...)
	{
		return conn.send!int("SREM", name, values);
	}
	
	int del()
	{
		return conn.send!int("DEL", name);
	}
	
	// OutputRange
	int put(in char[] value)
	{
		return conn.send!int("SADD", name, value);
	}
	
	int put(const(char[])[] values)
	{
		int count;
		foreach(value; values)
			count += put(value);
		return count;
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

	void opOpAssign(string op)(in char[] value) if (op == "~") {
		put(value);
	}

	void opOpAssign(string op)(in char[] value) if (op == "-") {
		srem(value);
	}
	
	void opOpAssign(string op)(const(char[])[] values) if (op == "~") {
		foreach(value; values)
			put(value);
	}

	void opOpAssign(string op)(const(char[])[] values) if (op == "-") {
		foreach(value; values)
			srem(value);
	}
}

unittest {
	import std.range : isOutputRange;

	static assert(isOutputRange!(Set, string));
	
	// Start a redis server on 127.0.0.1:6379
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
	
	import std.algorithm : canFind;
	foreach(fruit; set.smembers())
		assert(["guava", "pear", "banana", "apple", "orange"].canFind(fruit.toString));
}
