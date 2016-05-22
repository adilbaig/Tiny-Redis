import tinyredis.redis,
       tinyredis.subscriber,
       tinyredis.connection,
       tinyredis.response,
       tinyredis.parser,
       std.stdio,
       std.string,
       std.algorithm,
       std.functional
    ;

/**
 * Callback function for SUBSCRIBE messages.
 */
void handleMessage(string channel, string message)
{
    writefln("Channel '%s': %s", channel, message);
}

/**
 * Callback function for PSUBSCRIBE messages.
 */
void handlePatternMessage(string pattern, string channel, string message)
{
    writefln("Channel '%s' (matching '%s'): %s", channel, pattern, message);
}

/**
 * Report the number of remaining subscriptions
 */
void reportSubscriptions(size_t count)
{
    writefln("%s subscription%s", count, count == 1 ? "" : "s");
}

/**
 * This is a simple console to demonstrate Tiny Redis
 */
void main() 
{
    auto redis = new Redis();     // Regular connection
    auto sub = new Subscriber();  // Subscription connection
    size_t subCount = 0;          // Number of current subscriptions
    bool isSubscribed = false;    // Which connection to ping on (Redis's response differs)

    char[] buf;

    void updateSubscriptionState() {
        isSubscribed = (subCount != 0);
        reportSubscriptions(subCount);
    }

    writeln("Press Enter to process queued messages.");
    write("redis > "); 
    while (stdin.readln(buf))
    {
        string line = cast(string)buf[0 .. $-1].strip;

        if(line.length > 0)
            try{
                const found = line.findSplit(" ");
                const cmd = found[0].toLower;
                auto channels = found[2].splitter(' ');    // Used only under some cases; still...

                switch (cmd)
                {
                case "exit":
                    return;

                case "subscribe":
                    // .idup because buf is shared by all command lines
                    channels.each!(
                        c => subCount = sub.subscribe(c.idup, toDelegate(&handleMessage)));
                    updateSubscriptionState();
                    break;

                case "unsubscribe":
                    if (channels.empty)
                        subCount = sub.unsubscribe();
                    else
                        channels.each!(c => subCount = sub.unsubscribe(c));
                    updateSubscriptionState();
                    break;

                case "psubscribe":
                    // .idup because buf is shared by all command lines
                    channels.each!(
                        c => subCount = sub.psubscribe(c.idup, toDelegate(&handlePatternMessage)));
                    updateSubscriptionState();
                    break;

                case "punsubscribe":
                    if (channels.empty)
                        subCount = sub.punsubscribe();
                    else
                        channels.each!(c => subCount = sub.punsubscribe(c));
                    updateSubscriptionState();
                    break;

                case "quit":
                    Response resp = sub.quit();
                    writeln(resp);
                    subCount = 0;
                    updateSubscriptionState();
                    break;

                case "ping":
                    auto data = found[2];
                    Response resp = (isSubscribed ? sub.ping(data) : redis.send(line));
                    writeln(resp);
                    break;

                default:
                    Response resp = redis.send(line);
                    if (resp.isString) {
                        writeln('"', resp.toDiagnosticString(), '"');
                    } else {
                        writeln(resp.toDiagnosticString());
                    }
                }
            }
            catch(RedisResponseException e) {
                writeln("(error) ", e.msg);
            }
            catch(ConnectionException e) {
                writeln("(error) ", e.msg);
            }

        // Opportunity to process queued messages from subscribed channels
        sub.processMessages();

        write("redis > ");  
    }
}