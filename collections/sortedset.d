module collections.sortedset;

import tinyredis.redis;

/**
  SortedSetRange 
  A class that allows you to iterate over a SortedSet
  It supports a full range of features, including :
  	- Iterating using filters
  	- Iterating in steps
  	- Iterate forwards or backwards
  	
 Uses ZADD, ZSCAN, ZRANGE and their *REV counterparts

*/
class SortedSetRange
{
	string name;
	Redis conn;
		
	public :
    	
	enum InsertOptions {
	    DEFAULT,
	    ONLY_UPDATE,
	    ONLY_ADD,
	}
    
	this(Redis conn, string name)
	{
		this.conn = conn;
		this.name = name;
	}
	
	int zadd(string value, double score, InsertOptions insertOption = InsertOptions.DEFAULT, bool returnChangedElements = false, bool incrementScore = false)
	{
	    string[] args = ["ZADD", name];
	    args.length = 5;
	    
	    final switch(insertOption) {
	        case InsertOptions.ONLY_ADD:
	            args ~= "NX";
	            break;
	            
            case InsertOptions.ONLY_UPDATE:
	            args ~= "XX";
	            break;
	            
            default:
                break;
	    }
	    
	    if (returnChangedElements) {
	        args ~= "CH";
	    }
	    
	    if (incrementScore) {
	        args ~= "INCR";
	    }
	    
	    import std.conv;
	    args ~= to!string(score);
	    args ~= value;
	    
	    return conn.send!int(args);
	}
	
	int zcard()
	{
	    return conn.send!int("ZCARD", name);
	}
	
	int zcount(int min, int max)
	{
	    return conn.send!int("ZCOUNT", name, min, max);
	}
	
	int zincrby(double increment, string member)
	{
	    return conn.send!int("ZCOUNT", name, increment, member);
	}
}

unittest {
    
}