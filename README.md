Tiny-Redis
==========
A simple Redis driver in D. It makes working with Redis trivial.

## Compilation Instructions

	rdmd src/tinyredis.d src/example.d

If you have *make* installed, run :

	make example
	
This will run the example program.

## Example
	auto redis = new Redis();
    
    writeln(redis.send("LASTSAVE"));
    writeln(redis.send("SET name adil"));
    writeln(redis.send("GET name"));
   
    writeln(redis.send("SADD myset adil"));
    writeln(redis.send("SADD myset 350001939"));
    writeln(redis.send("SADD myset $"));
    writeln(redis.send("SADD myset $"));
    writeln(redis.send("SMEMBERS myset"));
    //["adil", "350001939", "$"] 

If a command is incorrect a *RedisResponseException* is thrown. See [example.d](https://github.com/adilbaig/Tiny-Redis/blob/master/src/example.d) and [console.d](https://github.com/adilbaig/Tiny-Redis/blob/master/src/console.d) for more usage samples. 

## Interactive Console
The integrated interactive console works like redis-cli. To run it, run :

	make console

## Run Unittests

	make test

## Dependencies
This library does not have any dependencies. Tested only with dmd 2.059.  

## Contributions
Please download and play with this project. Open tickets for bugs. Patches, feature requests, suggestiongs to improve the code, documentation, performance and anything else are very welcome.

Adil Baig
<br />Blog : [adilbaig.posterous.com](http://adilbaig.posterous.com)
<br />Twitter : [@aidezigns](http://twitter.com/aidezigns)
