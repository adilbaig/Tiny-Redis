Tiny-Redis
==========
A simple Redis driver in D. It makes working with Redis trivial.

## Compilation Instructions

	rdmd src/tinyredis.d src/example.d

If you have make installed, run :

	make example
	
This will run the example program.

## Usage Example
	auto redis = new Redis();
    
    writeln(redis.send("LASTSAVE"));
    writeln(redis.send("SET name adil"));
    writeln(redis.send("GET name"));
   
    writeln(redis.send("SADD myset $"));
    writeln(redis.send("SMEMBERS myset"));
    //["adil", "350001939", "$"] 

If a command is incorrect a _RedisResponseException_ is thrown. Examples are in example.d and console.d

## Interactive Console
The integrated interactive console works like redis-cli. To run it, run :

	make console

## D Compiler
Tested only with dmd 2.059. Does not have any other dependencies. 

## Contributions
Please download and play with this project. Open tickets for bugs. To contribute code simply fork this repository and send a pull request.
Any thoughts on how to improve the code, documentation, performance and anything else is very welcome.

Adil Baig
<br />Blog : [adilbaig.posterous.com](http://adilbaig.posterous.com)
<br />Twitter : [@aidezigns](http://twitter.com/aidezigns)
