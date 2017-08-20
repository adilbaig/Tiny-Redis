#!/usr/bin/env rdmd
import std.stdio;
import std.file;
import std.regex;
import std.string;
import std.array;
import std.typecons;
import std.process;

enum Output { SHOW, SHOW_ERROR, HIDE }

void check(string arg, Output output) {
  auto res = executeShell(arg);
  if (res.status != 0) {
    if (output != Output.HIDE) {
      writeln(res.output);
      throw new Exception("problems executing " ~ arg);
    }
  }
  if (output == Output.SHOW) {
    writeln(res.output);
  }
}

void main()
{
  check("rm -f snippet_*", Output.HIDE);
  auto content = readText("index.html");
  auto pattern = ctRegex!("<code language=\"dlang\">(.*?)</code>", "sm");
  foreach (i, match; content.matchAll(pattern).array) {
    auto fileName = "snippet_%s.d".format(i);
    writeln("-------------------- Working on %s".format(fileName));
    std.file.write(fileName, match[1]);
    check("dmd -I~/.dub/packages/tinyredis-2.1.1/tinyredis/source %s ~/.dub/packages/tinyredis-2.1.1/tinyredis/libtinyredis.a".format(fileName), Output.SHOW_ERROR);
    check("./%s".format(fileName.replace(".d", "")), Output.SHOW);
  }
}
