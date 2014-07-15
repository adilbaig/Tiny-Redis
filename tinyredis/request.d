module tinyredis.request;

public import tinyredis.encoder;

public :

	/**
     Represents a Request to be sent to the server
    */
    struct Request
    {
        string[] args; 
        
        @property void add(T)(T arg)
        {
            static if(isArray!(typeof(arg)) && !is(typeof(arg) == immutable(char)[])) {
                foreach(b; arg)
                    add(b);
            }
            else 
                args ~= text(arg);
        }
    
        @property @trusted string toString()
        {
            return argsToMultiBulk(args);
        }
        
        alias toMultiBulk toString;
    }
    
    private string[] stripAndChop(string cmd)
    {
        /*
         Sometimes a command is passed as a full string. Ex: command = "GET *s";
         This function breaks it down to its args
        */ 
        
        auto command = strip(cmd);
        
        string[] cmds;
        char[] buffer;
        
        //Loop through each char ..
        uint i = 0;
        while(i < command.length)
        {
            auto c = command[i++];
            
            // ..if the char is a ", accumalate all characters until another " is found.
            if(c == '"')
            {
                while(i < command.length)
                {
                    auto c1 = command[i++];
                    if(c1 == '"')
                        break;
                    buffer ~= c1;
                }
            } // if a space is found, cat the buffer to cmds ..
            else if(c == ' ')
            {
                cmds ~= cast(string)buffer;
                buffer.length = 0;
            }
            else // .. else cat everything else
                buffer ~= c;
        }
        
        cmds ~= cast(string)buffer;
        return cmds;
    }