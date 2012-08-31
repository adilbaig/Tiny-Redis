Tiny Redis
==========
Tiny Redis is a Redis driver for the D programming language (v2). It is intentionally minimal, but powerful and makes working with Redis trivial.

## Support
All the basic operations on all data types are supported :
- strings
- hashes
- lists
- sets
- sorted sets
- transactions (Yay!) 

The more esoteric features like Lua scripting and Pub/Sub have not been tested yet.

## Compilation Instructions

	rdmd src/tinyredis.d src/example.d

If you have *make* installed, run :

	make example
	
To run any of the example programs, or unittests, make sure you have a Redis server running on "localhost" on port 6379 (default Redis install)

## Example
	auto redis = new Redis("localhost", 6379);
    
    //An Int reply
    writeln(redis.send("LASTSAVE"));
    
    //Get/Set
    redis.send("SET name adil");
    auto r = redis.send("GET name");
    writeln("My name is ", r.value); //My name is adil
   
    //Or create a set
    redis.send("SADD", "myset", "adil");
    redis.send("SADD", "myset", 350001939);
    redis.send("SADD", "myset", 1.2);
    redis.send("SADD", "myset", true);
    redis.send("SADD", "myset", true);
    writeln(redis.send("SMEMBERS myset"));
    // Writes : ["adil", "350001939", "1.2", "true"]
    
    //Transactions
     writeln(redis.send("MULTI")); //OK
     writeln(redis.send("INCR foo")); //QUEUED
     writeln(redis.send("INCR bar")); //QUEUED
     writeln(redis.send("EXEC")); //[(Integer) 1, (Integer) 1] 

See [example.d](https://github.com/adilbaig/Tiny-Redis/blob/master/src/example.d) and [console.d](https://github.com/adilbaig/Tiny-Redis/blob/master/src/console.d) for more usage samples. You may also want to check out the unittests in [tinyredis.d](https://github.com/adilbaig/Tiny-Redis/blob/master/src/tinyredis.d#L220) 

## Interactive Console
The integrated interactive console works like redis-cli. To run it, run :

	make console

## Run Unittests

	make test

## Dependencies
This library does not have any dependencies. Tested with dmd 2.059 on Linux, and dmd-trunk (2.06ish) on Linux 64bit.  

## Contributions
Please download and play with this project. Open tickets for bugs. Patches, feature requests, suggestiongs to improve the code, documentation, performance and anything else are very welcome.

Adil Baig
<br />Blog : [adilbaig.posterous.com](http://adilbaig.posterous.com)
<br />Twitter : [@aidezigns](http://twitter.com/aidezigns)
